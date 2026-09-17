; ============================================================================
;  AHK2 Builder & Compiler - engine core
;  Shared pipeline for both modes.  A profile describes a custom AutoHotkey
;  engine; when it carries a script, the same engine is built with that script
;  baked in.  So "compile" is "build (self-contained) + embed".
;
;  Pipeline:  AcquireSource -> ApplyProfile -> [EmbedScript] -> Build
;             -> PostProcess -> Verify
;
;  Pure AHK v2, no external runtime.  The GUI (AHK2BC.ahk) and the headless CLI
;  both drive Engine; nothing here touches the GUI.
; ============================================================================
#Requires AutoHotkey v2.0

; Growable little-endian byte writer for building binary resources (VERSIONINFO, icons).
class ByteBuf {
    __New(cap := 8192) {
        this.buf := Buffer(cap, 0), this.pos := 0, this.cap := cap
    }
    Ensure(n) {
        if (this.pos + n <= this.cap)
            return
        while (this.pos + n > this.cap)
            this.cap *= 2
        nb := Buffer(this.cap, 0)
        DllCall("RtlMoveMemory", "Ptr", nb.Ptr, "Ptr", this.buf.Ptr, "UPtr", this.pos)
        this.buf := nb
    }
    W(v) => (this.Ensure(2), NumPut("UShort", v & 0xFFFF, this.buf, this.pos), this.pos += 2)
    D(v) => (this.Ensure(4), NumPut("UInt", v & 0xFFFFFFFF, this.buf, this.pos), this.pos += 4)
    Byte(v) => (this.Ensure(1), NumPut("UChar", v & 0xFF, this.buf, this.pos), this.pos += 1)
    WStr(s) {                                   ; UTF-16, null-terminated (BMP)
        Loop Parse s
            this.W(Ord(A_LoopField))
        this.W(0)
    }
    Bytes(ptr, n) => (this.Ensure(n), DllCall("RtlMoveMemory", "Ptr", this.buf.Ptr + this.pos, "Ptr", ptr, "UPtr", n), this.pos += n)
    Align() {
        while (this.pos & 3)
            this.Byte(0)
    }
    Mark() => this.pos
    PatchW(at) => NumPut("UShort", this.pos - at, this.buf, at)  ; back-patch a length WORD
}

class Engine {
    ; ---- construction ------------------------------------------------------
    __New(appDir, logFn := "") {
        this.appDir    := appDir
        this.dataDir   := appDir "\data"
        this.patchDir  := appDir "\patches"
        this.extraDir  := appDir "\src-extra"
        this.buildRoot := appDir "\build"
        this.logFn     := logFn
        this.features  := this.LoadFeatures()
        this.cancelled := false
    }

    Log(msg) {
        if this.logFn
            (this.logFn)(msg)
        else
            FileAppend(msg "`n", "*")
    }

    ; ---- feature catalog ---------------------------------------------------
    LoadFeatures() {
        f := Map(), order := []
        path := this.dataDir "\features.ini"
        for section in StrSplit(IniRead(path), "`n") {
            section := Trim(section)
            if section = ""
                continue
            info := Map()
            info["define"]  := this.IniGet(path, section, "define")
            info["implies"] := this.IniGet(path, section, "implies")
            info["title"]   := this.IniGet(path, section, "title", section)
            info["group"]   := this.IniGet(path, section, "group", "Other")
            info["kb"]      := this.IniGet(path, section, "kb")
            info["desc"]    := this.IniGet(path, section, "desc")
            f[section] := info
            order.Push(section)
        }
        this.featureOrder := order
        return f
    }
    IniGet(path, sec, key, def := "") {
        v := IniRead(path, sec, key, "`f")
        return (v = "`f") ? def : v
    }

    ; Expand a remove-list to include implied features, validated.
    ExpandRemoved(removeCsv) {
        want := [], seen := Map()
        for name in this.SplitList(removeCsv) {
            if !this.features.Has(name)
                throw Error("Unknown feature: " name)
            if !seen.Has(name)
                seen[name] := true, want.Push(name)
            for dep in this.SplitList(this.features[name]["implies"])
                if !seen.Has(dep)
                    seen[dep] := true, want.Push(dep)
        }
        return want
    }

    ; remove-list -> array of preprocessor defines.
    DefinesFor(removeCsv) {
        defs := [], seen := Map()
        for name in this.ExpandRemoved(removeCsv)
            for d in this.SplitList(this.features[name]["define"])
                if !seen.Has(d)
                    seen[d] := true, defs.Push(d)
        return defs
    }

    SplitList(s) {
        out := []
        for x in StrSplit(s, [",", " ", "`t"])
            if (x := Trim(x)) != ""
                out.Push(x)
        return out
    }

    ; ---- environment -------------------------------------------------------
    FindMSBuild(override := "") {
        if (override != "" && FileExist(override))
            return override
        pf86 := EnvGet("ProgramFiles(x86)")
        if pf86 = ""
            pf86 := "C:\Program Files (x86)"
        vswhere := pf86 "\Microsoft Visual Studio\Installer\vswhere.exe"
        if !FileExist(vswhere)
            return ""
        tmp := A_Temp "\ahk2bc_msb.txt"
        ; -all + -prerelease so an "incomplete"-flagged Build Tools install is still found.
        RunWait(A_ComSpec ' /c ""' vswhere '" -all -prerelease -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe > "' tmp '""', , "Hide")
        path := FileExist(tmp) ? Trim(FileRead(tmp), " `t`r`n") : ""
        if FileExist(tmp)
            FileDelete(tmp)
        ; May list several; take the first line.
        return StrSplit(path, "`n", "`r")[1]
    }
    FindGit(override := "") {
        if (override != "" && FileExist(override))
            return '"' override '"'
        return (RunWait(A_ComSpec " /c git --version", , "Hide") = 0) ? "git" : ""
    }

    ; ---- source acquisition -----------------------------------------------
    ; build\pristine holds an untouched tree; build\src is rebuilt from it each run.
    AcquireSource(cfg) {
        pristine := this.buildRoot "\pristine"
        src      := this.buildRoot "\src"
        track    := this.buildRoot "\.source_id"
        id := (cfg.source_mode = "local")
            ? "local|" cfg.source_path
            : "git|" cfg.source_repo "|" cfg.source_branch
        haveId := FileExist(track) ? FileRead(track) : ""

        if !DirExist(this.buildRoot)
            DirCreate(this.buildRoot)

        needFetch := (haveId != id) || !DirExist(pristine) || !FileExist(pristine "\AutoHotkeyx.sln")
        if needFetch {
            if DirExist(pristine)
                this.RmDir(pristine)
            if (cfg.source_mode = "local") {
                if !FileExist(cfg.source_path "\AutoHotkeyx.sln")
                    throw Error("Local source not found (no AutoHotkeyx.sln in " cfg.source_path ")")
                this.Log("[*] Caching local source from " cfg.source_path)
                this.CopyTree(cfg.source_path, pristine)
            } else {
                this.FetchGit(cfg, pristine)
            }
            if FileExist(track)
                FileDelete(track)
            FileAppend(id, track, "UTF-8")
        } else {
            this.Log("[*] Reusing cached source (" id ")")
        }

        this.Log("[*] Restoring clean working tree...")
        if DirExist(src)
            this.RmDir(src)
        this.CopyTree(pristine, src)
        for d in ["\bin", "\bin_minimal", "\temp"]   ; clear any stale build output
            if DirExist(src d)
                this.RmDir(src d)
        this.srcDir := src
    }

    FetchGit(cfg, dest) {
        git := this.FindGit(cfg.HasOwnProp("override_git") ? cfg.override_git : "")
        if (git != "") {
            this.Log("[*] Cloning " cfg.source_repo " (" cfg.source_branch ")...")
            ; autocrlf=false + eol=lf force an LF checkout (the repo's .gitattributes
            ; would otherwise yield CRLF on Windows) so the LF feature patch applies.
            if (RunWait(A_ComSpec " /c " git " -c core.autocrlf=false -c core.eol=lf clone --branch " cfg.source_branch " --depth 1 " cfg.source_repo ' "' dest '"', , "Hide") != 0)
                throw Error("git clone failed")
            RunWait(A_ComSpec ' /c rmdir /s /q "' dest '\.git"', , "Hide")  ; not needed after clone
            return
        }
        ; No git: download the branch zip and flatten it.
        this.Log("[*] Git not found; downloading source zip...")
        cleanUrl := RegExReplace(cfg.source_repo, "i)\.git/?$", "")
        zip := this.buildRoot "\src.zip", ex := this.buildRoot "\src_zip"
        Download(cleanUrl "/archive/refs/heads/" cfg.source_branch ".zip", zip)
        if DirExist(ex)
            this.RmDir(ex)
        DirCreate(ex)
        RunWait('powershell -NoProfile -Command "Expand-Archive -Path \"' zip '\" -DestinationPath \"' ex '\" -Force"', , "Hide")
        FileDelete(zip)
        inner := ""
        Loop Files, ex "\*", "D" {
            inner := A_LoopFilePath
            break
        }
        if (inner = "" || !FileExist(inner "\AutoHotkeyx.sln"))
            throw Error("Downloaded zip did not contain the expected source tree")
        this.CopyTree(inner, dest)
        this.RmDir(ex)
    }

    ; ---- apply profile to the working tree ---------------------------------
    ApplyProfile(cfg) {
        this.Log("[*] Applying feature patch and build settings...")
        this.ApplyFeaturePatch()
        this.defines := this.DefinesFor(cfg.remove)
        if (cfg.HasOwnProp("extra_defines") && cfg.extra_defines != "")
            for d in this.SplitList(cfg.extra_defines)
                this.defines.Push(d)
        if (cfg.regex = "windows")
            this.EnableWindowsRegex()
        this.EditProjectFlags(cfg)
        this.ApplyBuildTargeting(cfg)
        if (cfg.HasOwnProp("scrub_strings") && cfg.scrub_strings)
            this.ScrubSignatureStrings()
        if (cfg.HasOwnProp("iat_hooks") && cfg.iat_hooks)
            this.InjectHooks()
        if (cfg.version != "")
            this.SetVersion(cfg.version)
    }

    ; Execution level (UAC), console subsystem, and Windows minimum version.
    ApplyBuildTargeting(cfg) {
        ; --- manifest: requested execution level ---
        lvl := cfg.HasOwnProp("exec_level") ? cfg.exec_level : "asInvoker"
        if (lvl != "" && lvl != "asInvoker") {
            man := this.srcDir "\source\resources\AutoHotkey.exe.manifest"
            if FileExist(man) {
                mt := FileRead(man, "UTF-8")
                mt := RegExReplace(mt, 'level="[^"]*"', 'level="' lvl '"')
                this.Save(man, mt)
                this.Log("[*] Execution level: " lvl)
            }
        }
        ; --- subsystem (console) + minimum Windows version ---
        console := cfg.HasOwnProp("console") && cfg.console
        minwin := cfg.HasOwnProp("min_win") ? cfg.min_win : ""     ; e.g. "10.0", "6.1", "" = default
        if (console || minwin != "") {
            vcx := this.srcDir "\AutoHotkeyx.vcxproj"
            t := FileRead(vcx, "UTF-8")
            if console {
                t := RegExReplace(t, "<SubSystem>.*?</SubSystem>", "<SubSystem>Console</SubSystem>")
                ; AHK's entry point is wWinMain, so keep it when switching to the console subsystem.
                t := RegExReplace(t, "\s*<EntryPointSymbol>.*?</EntryPointSymbol>", "")
                t := this.InjectBeforeFirst(t, "</Link>", "      <EntryPointSymbol>wWinMainCRTStartup</EntryPointSymbol>`r`n")
                this.Log("[*] Subsystem: Console")
            }
            if (minwin != "") {
                ; MSBuild-native: MinimumRequiredVersion -> /SUBSYSTEM:<type>,<ver>
                t := RegExReplace(t, "\s*<MinimumRequiredVersion>.*?</MinimumRequiredVersion>", "")
                t := this.InjectBeforeFirst(t, "</Link>", "      <MinimumRequiredVersion>" minwin "</MinimumRequiredVersion>`r`n")
                this.Log("[*] Minimum Windows version: " minwin)
            }
            this.Save(vcx, t)
        }
    }

    ; Apply every patches\*.patch in filename order.  Ship 0001 for v2.0; a new
    ; AutoHotkey line (e.g. 2.1-alpha) just needs its own 0002-*.patch dropped in -
    ; no code change.  Each is tried; a clean failure names the offending patch.
    ApplyFeaturePatch() {
        git := this.FindGit()
        if (git = "")
            throw Error("git is required to apply the feature patch (install Git for Windows).")
        ; Source is fetched with LF endings (clone uses core.eol=lf; github zips are LF),
        ; which is what the LF feature patch expects.  A local source that is CRLF would
        ; need converting to LF first.
        patches := []
        Loop Files, this.patchDir "\*.patch"
            patches.Push(A_LoopFilePath)
        if !patches.Length
            throw Error("No feature patches found in " this.patchDir)
        patches := this.SortStrings(patches)
        for patch in patches {
            out := A_Temp "\ahk2bc_patch.txt"
            ; autocrlf=false keeps the source's LF endings regardless of global config.
            RunWait(A_ComSpec ' /c ' git ' -c core.autocrlf=false -C "' this.srcDir '" apply --whitespace=nowarn --recount "' patch '" > "' out '" 2>&1', , "Hide")
            res := FileExist(out) ? FileRead(out) : ""
            if FileExist(out)
                FileDelete(out)
            if (res != "") {
                SplitPath(patch, &pn)
                throw Error("Patch '" pn "' did not apply - the source tree may not match this patch's AutoHotkey version.`n`n" res)
            }
        }
    }
    ; Strip CR from source files so LF patches apply regardless of how the tree
    ; was obtained (git checkout with text=auto yields CRLF on Windows).
    NormalizeSourceLF() {
        for ext in ["cpp", "h"] {
            Loop Files, this.srcDir "\source\*." ext, "R" {
                f := FileOpen(A_LoopFilePath, "r-d")
                n := f.Length, src := Buffer(n), f.RawRead(src), f.Close()
                dst := Buffer(n), j := 0, changed := false
                p := src.Ptr
                start := 1
                if (n >= 3 && NumGet(p, 0, "UChar") = 0xEF && NumGet(p, 1, "UChar") = 0xBB && NumGet(p, 2, "UChar") = 0xBF) {
                    start := 4, changed := true      ; strip leading UTF-8 BOM
                }
                Loop n - (start - 1) {
                    i := start + A_Index - 2          ; 0-based index into buffer
                    b := NumGet(p, i, "UChar")
                    if (b = 13 && i + 1 < n && NumGet(p, i + 1, "UChar") = 10) {
                        changed := true
                        continue                     ; drop CR before LF
                    }
                    NumPut("UChar", b, dst, j), j += 1
                }
                if changed {
                    o := FileOpen(A_LoopFilePath, "w-")
                    o.RawWrite(dst, j), o.Close()
                }
            }
        }
        ; text=auto in the source's .gitattributes would re-trigger conversion; drop it.
        if FileExist(this.srcDir "\.gitattributes")
            FileDelete(this.srcDir "\.gitattributes")
    }

    SortStrings(arr) {
        s := ""
        for x in arr
            s .= x "`n"
        out := []
        for line in StrSplit(Sort(RTrim(s, "`n"), ""), "`n")
            if (line != "")
                out.Push(line)
        return out
    }

    ; Route RegEx through the OS ICU engine instead of the bundled PCRE.
    EnableWindowsRegex() {
        this.Log("[*] RegEx backend: Windows (ICU) - dropping bundled PCRE.")
        FileCopy(this.extraDir "\regex_win.cpp", this.srcDir "\source\lib\regex_win.cpp", 1)
        vcx := this.srcDir "\AutoHotkeyx.vcxproj"
        t := FileRead(vcx, "UTF-8")
        ; drop the lib_pcre project reference (we supply pcre16_* via the shim)
        t := RegExReplace(t, "s)\s*<ProjectReference Include=`"source\\lib_pcre.*?</ProjectReference>", "")
        ; compile the shim (no PCH)
        if !InStr(t, "regex_win.cpp")
            t := StrReplace(t, '<ClCompile Include="source\lib\regex.cpp" />'
                , '<ClCompile Include="source\lib\regex.cpp" />' "`r`n    <ClCompile Include=`"source\lib\regex_win.cpp`"><PrecompiledHeader>NotUsing</PrecompiledHeader></ClCompile>")
        ; link the OS ICU import library
        if !InStr(t, "icu.lib")
            t := StrReplace(t, "uxtheme.lib;dwmapi.lib;", "uxtheme.lib;dwmapi.lib;icu.lib;")
        this.Save(vcx, t)
        this.defines.Push("REGEX_BACKEND_WINDOWS")
        ; With the shim, PCRE's own Unicode tables are irrelevant; NO_UCP would be a no-op.
    }

    EditProjectFlags(cfg) {
        optTag   := (cfg.optimize = "size") ? "MinSpace" : "MaxSpeed"
        favorTag := (cfg.optimize = "size") ? "Size" : "Speed"
        Loop Files, this.srcDir "\*.vcxproj", "R" {
            p := A_LoopFilePath, t := FileRead(p, "UTF-8")
            t := RegExReplace(t, "<Optimization>.*?</Optimization>", "<Optimization>" optTag "</Optimization>")
            t := RegExReplace(t, "<FavorSizeOrSpeed>.*?</FavorSizeOrSpeed>", "<FavorSizeOrSpeed>" favorTag "</FavorSizeOrSpeed>")
            this.Save(p, t)
        }
        ; Main project: CRT, delay-load, defines, extra link flags.
        vcx := this.srcDir "\AutoHotkeyx.vcxproj"
        t := FileRead(vcx, "UTF-8")

        crt := "MultiThreaded"                    ; static (default)
        if (cfg.crt = "dll")
            crt := "MultiThreadedDLL"
        t := RegExReplace(t, "<RuntimeLibrary>.*?</RuntimeLibrary>", "<RuntimeLibrary>" crt "</RuntimeLibrary>")

        ; Link additions injected before </Link> of the common item group.
        linkAdd := ""
        if (cfg.crt = "os")
            linkAdd .= "      <IgnoreSpecificDefaultLibraries>libucrt.lib;%(IgnoreSpecificDefaultLibraries)</IgnoreSpecificDefaultLibraries>`r`n      <AdditionalDependencies>ucrt.lib;%(AdditionalDependencies)</AdditionalDependencies>`r`n"
        if (cfg.HasOwnProp("iat_delayload") && cfg.iat_delayload) {
            dlls := "USER32.dll;GDI32.dll;COMCTL32.dll;ADVAPI32.dll;SHELL32.dll;OLEAUT32.dll;VERSION.dll;WININET.dll;WSOCK32.dll;WINMM.dll;PSAPI.DLL;UxTheme.dll;dwmapi.dll;ole32.dll;SHLWAPI.dll;%(DelayLoadDLLs)"
            linkAdd .= "      <DelayLoadDLLs>" dlls "</DelayLoadDLLs>`r`n"
        }
        t := RegExReplace(t, "\s*<DelayLoadDLLs>.*?</DelayLoadDLLs>", "")
        if (linkAdd != "")
            t := this.InjectBeforeFirst(t, "</Link>", linkAdd)

        ; Preprocessor defines for the whole project.
        if (this.defines.Length) {
            defStr := ""
            for d in this.defines
                defStr .= d ";"
            t := StrReplace(t, "WIN32;_WINDOWS;%(PreprocessorDefinitions)", "WIN32;_WINDOWS;" defStr "%(PreprocessorDefinitions)")
        }
        this.Save(vcx, t)

        ; Size-optimised builds turn off LTCG only if the user asked; otherwise keep WPO.
        this.wpo := (cfg.HasOwnProp("ltcg") && !cfg.ltcg) ? "false" : "true"
    }

    InjectBeforeFirst(text, needle, inject) {
        p := InStr(text, needle)
        if !p
            return text
        return SubStr(text, 1, p - 1) inject SubStr(text, p)
    }

    ; White-label the binary: replace AutoHotkey signature strings in the C++
    ; source so the compiled exe doesn't advertise itself (reduces naive
    ; heuristic/AV signatures).  Ported from the user's AHKCompiler ScrubFile.
    ScrubSignatureStrings() {
        this.Log("[*] Scrubbing AutoHotkey signature strings...")
        rules := Map(
            "autohotkey.com", "example.com",
            "AutoHotkeyGUI", "CustomAppGUI",
            ".exe.bat.com.cmd.hta", ".exe,.bat,.com,.cmd,.hta")
        n := 0
        for ext in ["cpp", "h"] {
            Loop Files, this.srcDir "\source\*." ext, "R" {
                t := FileRead(A_LoopFilePath, "UTF-8"), o := t
                for from, to in rules
                    t := StrReplace(t, from, to)
                if (t != o)
                    this.Save(A_LoopFilePath, t), n++
            }
        }
        this.Log("    scrubbed " n " file(s).")
    }

    ; Route selected OS imports through runtime resolution so they don't appear
    ; in the import table (cleaner IAT, fewer AV false-positives).  Writes
    ; source\Hooks.h and force-includes it after the last #include in each .cpp.
    ; Ported from the user's AHKCompiler InjectHooks.
    InjectHooks() {
        this.Log("[*] Injecting Win32 hooks (cleaning import table)...")
        src := this.extraDir "\Hooks.h"
        if !FileExist(src)
            throw Error("Missing src-extra\Hooks.h")
        FileCopy(src, this.srcDir "\source\Hooks.h", 1)
        n := 0
        Loop Files, this.srcDir "\source\*.cpp", "R" {
            t := FileRead(A_LoopFilePath, "UTF-8")
            if InStr(t, '#include "Hooks.h"')
                continue
            last := 0, pos := 1
            while (pos := RegExMatch(t, 'm)^#include[ \t]+["<]', &m, pos))
                last := pos, pos += m.Len[0]
            if last {
                eol := InStr(t, "`n", false, last)
                if eol
                    t := SubStr(t, 1, eol) '#include "Hooks.h"' "`r`n" SubStr(t, eol + 1), this.Save(A_LoopFilePath, t), n++
            }
        }
        this.Log("    hooked " n " file(s).")
    }

    SetVersion(ver) {
        ; "-" prerelease labels break #Requires; "+" is build metadata (ignored by compares).
        if RegExMatch(ver, "^[\d.]+-")
            ver := RegExReplace(ver, "^([\d.]+)-", "$1+")
        h := this.srcDir "\source\ahkversion.h"
        t := FileRead(h, "UTF-8")
        t := RegExReplace(t, '#define RAW_AHK_VERSION "[^"]*"', '#define RAW_AHK_VERSION "' ver '"')
        pos := 1, parts := []
        while (pos := RegExMatch(ver, "\d+", &mm, pos)) {
            parts.Push(mm[0]), pos += mm.Len
            if parts.Length = 3
                break
        }
        while parts.Length < 3
            parts.Push("0")
        t := RegExReplace(t, "#define AHK_VERSION_N [\d,]+", "#define AHK_VERSION_N " parts[1] "," parts[2] "," parts[3] ",0")
        this.SaveBom(h, t)
    }

    ; ---- build -------------------------------------------------------------
    Build(cfg, platform, config) {
        msb := this.FindMSBuild(cfg.HasOwnProp("override_msvc") ? cfg.override_msvc : "")
        if (msb = "" || !FileExist(msb))
            throw Error("MSBuild not found. Install Visual Studio Build Tools with the C++ workload.")
        sln := this.srcDir "\AutoHotkeyx.sln"
        wpo := this.HasOwnProp("wpo") ? this.wpo : "true"
        clFlags := (cfg.optimize = "size") ? "/O1 /Gw" : ""
        if (cfg.HasOwnProp("extra_cl") && cfg.extra_cl != "")     ; escape hatch: extra compiler flags
            clFlags .= " " cfg.extra_cl
        linkFlags := ""
        if (cfg.HasOwnProp("extra_link") && cfg.extra_link != "") ; escape hatch: extra linker flags
            linkFlags := cfg.extra_link
        out := A_Temp "\ahk2bc_build.txt", ec := A_Temp "\ahk2bc_ec.txt"
        for f in [out, ec]
            if FileExist(f)
                FileDelete(f)
        cmd := 'call "' this.VsDevCmdFor(msb) '" -arch=amd64 -no_logo >nul 2>&1'
             . ' && set "_CL_=' clFlags '"'
             . (linkFlags != "" ? ' && set "_LINK_=' linkFlags '"' : '')
             . ' && "' msb '" "' sln '" /t:Rebuild /m /nologo /v:m'
             . ' /p:Configuration=' config ' /p:Platform=' platform
             . ' /p:WholeProgramOptimization=' wpo
        pid := 0
        Run(A_ComSpec ' /c "' cmd ' > "' out '" 2>&1 & echo %errorlevel% > "' ec '""', , "Hide", &pid)
        lastLen := 0
        while ProcessExist(pid) {
            if (cfg.HasOwnProp("show_msbuild") && cfg.show_msbuild && FileExist(out)) {
                try {
                    all := FileRead(out, "UTF-8")
                    if StrLen(all) > lastLen
                        this.Log(RTrim(SubStr(all, lastLen + 1), "`r`n")), lastLen := StrLen(all)
                }
            }
            if this.cancelled {
                RunWait(A_ComSpec " /c taskkill /PID " pid " /T /F", , "Hide")
                throw Error("Build cancelled.")
            }
            Sleep(200)
        }
        exitStr := FileExist(ec) ? Trim(FileRead(ec), " `t`r`n") : ""
        exit := (exitStr != "" && IsInteger(exitStr)) ? Integer(exitStr) : (exitStr = "0" ? 0 : 1)
        errLines := ""
        if FileExist(out) {
            for line in StrSplit(FileRead(out, "UTF-8"), "`n", "`r")
                if RegExMatch(line, "i): error|error [A-Z]+\d|unresolved")
                    errLines .= Trim(line) "`n"
            FileDelete(out)
        }
        if FileExist(ec)
            FileDelete(ec)
        return { exit: exit, errors: errLines }
    }

    ; VsDevCmd next to the discovered MSBuild.exe.
    VsDevCmdFor(msbuild) {
        d := msbuild
        Loop {
            SplitPath(d, , &d)
            if (d = "" || !InStr(d, "\"))
                break
            cand := d "\Common7\Tools\VsDevCmd.bat"
            if FileExist(cand)
                return cand
        }
        throw Error("VsDevCmd.bat not found near " msbuild)
    }

    BuiltFile(platform, kind) {
        bits := (platform = "Win32") ? "32" : "64"
        pattern := (kind = "bin") ? "* " bits "-bit.bin" : "AutoHotkey" bits ".exe"
        newest := "", newestTime := 0
        Loop Files, this.srcDir "\" pattern, "R" {
            if (A_LoopFileTimeModified > newestTime)
                newest := A_LoopFilePath, newestTime := A_LoopFileTimeModified
        }
        return newest
    }

    ; ---- post ----------------------------------------------------------------
    Compact(path, mode) {
        if (mode = "none" || mode = "")
            return
        this.Log("[*] NTFS compression: " mode)
        RunWait(A_ComSpec ' /c compact /c /exe:' mode ' "' path '"', , "Hide")
    }

    CleanArtifacts() {
        for d in ["\temp", "\bin", "\source\autogenerated"]
            if DirExist(this.srcDir d)
                this.RmDir(this.srcDir d)
    }

    ; ---- script embedding (compile mode) -----------------------------------
    ; The script and any FileInstall / custom files are injected into the built
    ; exe with UpdateResource (exactly how Ahk2Exe does it) - reliable across
    ; source versions.  Icons and version-info are applied to the source before
    ; building.  Called in two halves: PrepareScript (before build) fills
    ; this.scriptBytes / this.embedResources and edits the source; then
    ; UpdateResources (after build) writes them into the output exe.
    EmbedScript(cfg) {
        this.Log("[*] Preparing script for embedding...")
        bundled := this.ResolveIncludes(cfg.script)
        ; @Ahk2Exe-* directives are comments - read them before cleaning removes them.
        this.ApplyAhk2ExeDirectives(bundled, cfg)
        if (cfg.HasOwnProp("clean_script") && cfg.clean_script)
            bundled := this.CleanAhkCode(bundled)

        SplitPath(cfg.script, , &mainDir)
        res := []
        for r in (cfg.HasOwnProp("resources") ? cfg.resources : [])
            res.Push(r)

        ; auto-detect FileInstall sources and add them as resources
        scan := this.CleanAhkCode(bundled)
        pos := 1
        while pos := RegExMatch(scan, "i)\bFileInstall\s*\(?\s*([`"'])(.*?)\1", &m, pos) {
            src := m[2], abs := src
            if !RegExMatch(abs, "^[a-zA-Z]:\\|^\\\\")
                abs := mainDir "\" abs
            rn := StrUpper(src), have := false
            for r in res
                if (StrUpper(r.Name) = rn)
                    have := true
            if (!have && FileExist(abs))
                res.Push({ Name: rn, Path: abs, Encrypt: false, Compress: false }), this.Log("    + FileInstall: " src)
            else if !have
                this.Log("    ! FileInstall source not found: " abs)
            pos += m.Len[0]
        }

        ; encrypted custom resources need a shared key + a runtime loader class
        masterKey := ""
        for r in res
            if r.Encrypt
                masterKey := masterKey = "" ? this.RandKey() : masterKey
        if (masterKey != "")
            bundled := this.AutoResourceLoaderClass(res, masterKey) "`r`n" bundled

        ; script payload bytes (+ optional transform)
        sb := Buffer(StrPut(bundled, "UTF-8") - 1)
        StrPut(bundled, sb, "UTF-8")
        keyStr := ""
        if (cfg.payload_encrypt)
            keyStr := this.RandKey(), this.EncryptRC4(sb, keyStr)
        if (cfg.payload_compress)
            this.CompressLZNT1(sb, &cb, &csz), sb := cb
        this.scriptBytes := sb
        if (cfg.payload_encrypt || cfg.payload_compress)
            this.InjectPayloadDecrypt(cfg, keyStr)

        ; resource payload bytes
        this.embedResources := []
        for r in res {
            ro := FileOpen(r.Path, "r-d"), rb := Buffer(ro.Length), ro.RawRead(rb, rb.Size), ro.Close()
            if r.Encrypt
                this.EncryptRC4(rb, masterKey)
            if r.Compress
                this.CompressLZNT1(rb, &rc2, &rsz), rb := rc2
            this.embedResources.Push({ name: StrUpper(r.Name), buf: rb })
        }

        ; Metadata/icons are edited in the source RC before a full build; in prebuilt
        ; mode there is no source tree, so they come from the base exe as-is.
        if (!cfg.HasOwnProp("base_mode") || cfg.base_mode != "prebuilt")
            this.ApplyMetadata(cfg)
    }

    RandKey() {
        k := ""
        Loop 16
            k .= Chr(Random(65, 90))
        return k
    }

    ; Write the script (>AUTOHOTKEY SCRIPT<) and files into the built exe.
    UpdateResources(exePath) {
        h := DllCall("BeginUpdateResourceW", "WStr", exePath, "Int", 0, "Ptr")
        if !h
            throw Error("BeginUpdateResource failed (is the exe writable?)")
        try {
            ; SC bases look for ">AUTOHOTKEY SCRIPT<"; interpreter bases look for RCDATA #1.
            ; Write both so any base (custom .bin or a stock AutoHotkey exe) runs the script.
            this.UpdateOne(h, ">AUTOHOTKEY SCRIPT<", this.scriptBytes)
            this.UpdateOneId(h, 1, this.scriptBytes)
            for r in this.embedResources
                this.UpdateOne(h, r.name, r.buf)
        } catch as e {
            DllCall("EndUpdateResourceW", "Ptr", h, "Int", 1) ; discard
            throw e
        }
        if !DllCall("EndUpdateResourceW", "Ptr", h, "Int", 0)
            throw Error("EndUpdateResource failed")
        this.Log("[*] Embedded script + " this.embedResources.Length " resource(s) via UpdateResource.")
    }
    UpdateOne(h, name, buf) {
        ; RT_RCDATA = 10, language 1033 (matches the exe's other resources)
        if !DllCall("UpdateResourceW", "Ptr", h, "Ptr", 10, "WStr", name, "UShort", 1033, "Ptr", buf.Ptr, "UInt", buf.Size)
            throw Error("UpdateResource failed for '" name "'")
    }
    UpdateOneId(h, id, buf) {           ; integer-named resource (MAKEINTRESOURCE)
        if !DllCall("UpdateResourceW", "Ptr", h, "Ptr", 10, "Ptr", id, "UShort", 1033, "Ptr", buf.Ptr, "UInt", buf.Size)
            throw Error("UpdateResource failed for #" id)
    }

    ; version-info fields (via rc) + icons (via file copy)
    ApplyMetadata(cfg) {
        rc := this.srcDir "\source\resources\AutoHotkey.rc"
        if !FileExist(rc)
            rc := this.srcDir "\source\resources\res_AutoHotkeySC.rc"
        if FileExist(rc) {
            t := FileRead(rc, "UTF-8")
            t := this.SetVerField(t, "FileDescription", cfg.filedesc)
            t := this.SetVerField(t, "CompanyName", cfg.company)
            t := this.SetVerField(t, "ProductName", cfg.product)
            t := this.SetVerField(t, "LegalCopyright", cfg.copyright)
            if (cfg.HasOwnProp("origfilename"))
                t := this.SetVerField(t, "OriginalFilename", cfg.origfilename)
            if (cfg.HasOwnProp("internalname"))
                t := this.SetVerField(t, "InternalName", cfg.internalname)
            if (cfg.HasOwnProp("trademarks"))
                t := this.SetVerField(t, "LegalTrademarks", cfg.trademarks)
            fv := (cfg.HasOwnProp("fileversion") && cfg.fileversion != "") ? cfg.fileversion : "1.0.0.0"
            t := this.SetVerField(t, "FileVersion", fv)
            t := this.SetVerField(t, "ProductVersion", fv)
            vc := StrReplace(fv, ".", ",")
            t := RegExReplace(t, "(?m)^(\s*FILEVERSION\s+).*", "$1" vc)
            t := RegExReplace(t, "(?m)^(\s*PRODUCTVERSION\s+).*", "$1" vc)
            this.Save(rc, t)
        }
        rd := this.srcDir "\source\resources"
        this.CopyIcon(cfg, "icon_main",         rd "\icon_main.ico")
        this.CopyIcon(cfg, "icon_suspend",      rd "\icon_suspend.ico")
        this.CopyIcon(cfg, "icon_pause",        rd "\icon_pause.ico")
        this.CopyIcon(cfg, "icon_pausesuspend", rd "\icon_pause_suspend.ico")
        this.CopyIcon(cfg, "icon_filetype",     rd "\icon_filetype.ico")
    }

    ; ---- Ahk2Exe directive compatibility -----------------------------------
    ; Reads ;@Ahk2Exe-<Directive> lines and fills matching profile fields that
    ; the user left blank (so the GUI still wins when set).  AddResource is
    ; always additive.  Values may use %A_ScriptName% / %A_ScriptDir% / dates.
    ApplyAhk2ExeDirectives(bundled, cfg) {
        SplitPath(cfg.script, &sName, &sDir, , &sNameNoExt)
        setIf(prop, val) {
            if (val != "" && (!cfg.HasOwnProp(prop) || cfg.%prop% = ""))
                cfg.%prop% := val
        }
        found := 0
        Loop Parse bundled, "`n", "`r" {
            line := Trim(A_LoopField, " `t")
            if !RegExMatch(line, "i)^;@Ahk2Exe-(\w+)\s*[, ]?\s*(.*)$", &m)
                continue
            found++
            dir := m[1], val := Trim(m[2], " `t")
            val := StrReplace(val, "%A_ScriptName%", sName)
            val := StrReplace(val, "%A_ScriptDir%", sDir)
            val := StrReplace(val, "%A_YYYY%", FormatTime(, "yyyy"))
            val := StrReplace(val, "%A_MM%", FormatTime(, "MM"))
            val := StrReplace(val, "%A_DD%", FormatTime(, "dd"))
            switch StrLower(dir) {
                case "setname", "setproductname":       setIf("product", val)
                case "setdescription", "setfiledescription": setIf("filedesc", val)
                case "setcompanyname":                   setIf("company", val)
                case "setcopyright", "setlegalcopyright":setIf("copyright", val)
                case "setversion", "setfileversion", "setproductversion": setIf("fileversion", val)
                case "setorigfilename":                  setIf("origfilename", val)
                case "setinternalname":                  setIf("internalname", val)
                case "setlegaltrademarks":               setIf("trademarks", val)
                case "consoleapp":                       (cfg.console := true)
                case "setlanguage", "useresourcelang":   this.Log("    (directive " dir " recognised; resources stay language-neutral)")
                case "setmainicon":                      setIf("icon_main", this.ResolveRel(val, sDir))
                case "exename":                          setIf("output", this.ResolveRel(val, sDir))
                case "addresource":
                    parts := StrSplit(val, ",", " `t")
                    file := this.ResolveRel(parts[1], sDir)
                    name := parts.Length >= 2 ? parts[2] : ""
                    if (name = "") {
                        SplitPath(parts[1], &fn)
                        name := StrUpper(fn)
                    }
                    if FileExist(file) {
                        if !cfg.HasOwnProp("resources")
                            cfg.resources := []
                        cfg.resources.Push({ Name: name, Path: file, Encrypt: false, Compress: false })
                    }
                default: ; SetOrigFilename/ConsoleApp/Bin/Base/etc. - not applied
                    found--
            }
        }
        if found
            this.Log("[*] Applied " found " @Ahk2Exe directive(s) from the script.")
    }
    ResolveRel(p, dir) {
        p := Trim(p, " `t`"'")
        if (p != "" && !RegExMatch(p, "^[a-zA-Z]:\\|^\\\\"))
            p := dir "\" p
        return p
    }

    ; Minimal AutoResourceLoader so scripts can read encrypted/compressed resources.
    AutoResourceLoaderClass(res, masterKey) {
        map := ""
        for r in res
            if (r.Encrypt || r.Compress)
                map .= '            if (n = "' StrUpper(r.Name) '") { e := ' (r.Encrypt ? "1" : "0") ', c := ' (r.Compress ? "1" : "0") ' }`r`n'
        return "
        (
class AutoResourceLoader {
    static Get(n) {
        e := 0, c := 0
" map "
        h := DllCall('GetModuleHandle','Ptr',0,'Ptr')
        ri := DllCall('FindResource','Ptr',h,'Str',n,'Ptr',10,'Ptr')
        if !ri
            throw Error('Resource not found: ' n)
        sz := DllCall('SizeofResource','Ptr',h,'Ptr',ri,'UInt')
        pd := DllCall('LockResource','Ptr',DllCall('LoadResource','Ptr',h,'Ptr',ri,'Ptr'),'Ptr')
        b := Buffer(sz), DllCall('RtlMoveMemory','Ptr',b,'Ptr',pd,'UPtr',sz)
        if (c) {
            us := NumGet(b,0,'UInt'), nb := Buffer(us), fs := 0
            DllCall('ntdll\RtlDecompressBuffer','UShort',0x102,'Ptr',nb,'UInt',us,'Ptr',b.Ptr+4,'UInt',sz-4,'UInt*',&fs)
            b := nb
        }
        if (e) {
            k := '" masterKey "', s := Buffer(256)
            i := 0
            Loop 256
                NumPut('UChar', A_Index-1, s, A_Index-1)
            j := 0, kl := StrLen(k)
            Loop 256 {
                i := A_Index-1
                j := (j + NumGet(s,i,'UChar') + Ord(SubStr(k, Mod(i,kl)+1, 1))) & 255
                t := NumGet(s,i,'UChar'), NumPut('UChar', NumGet(s,j,'UChar'), s, i), NumPut('UChar', t, s, j)
            }
            i := 0, j := 0
            Loop b.Size {
                i := (i+1)&255, j := (j+NumGet(s,i,'UChar'))&255
                t := NumGet(s,i,'UChar'), NumPut('UChar', NumGet(s,j,'UChar'), s, i), NumPut('UChar', t, s, j)
                o := A_Index-1
                NumPut('UChar', NumGet(b,o,'UChar') ^ NumGet(s, (NumGet(s,i,'UChar')+NumGet(s,j,'UChar'))&255, 'UChar'), b, o)
            }
        }
        return b
    }
}
        )"
    }

    SetVerField(content, field, val) {
        if (val = "")
            return content
        if InStr(content, 'VALUE "' field '"')
            return RegExReplace(content, '(VALUE "' field '",\s*).*', '$1"' val '"')
        ; insert before ProductName block if missing (e.g. LegalCopyright)
        return StrReplace(content, 'VALUE "ProductName",', 'VALUE "' field '", "' val '"' "`r`n            VALUE `"ProductName`",")
    }

    CopyIcon(cfg, prop, dest) {
        if (cfg.HasOwnProp(prop) && cfg.%prop% != "" && FileExist(cfg.%prop%))
            FileCopy(cfg.%prop%, dest, 1)
    }

    InjectPayloadDecrypt(cfg, keyStr) {
        cpp := this.srcDir "\source\script.cpp"
        if !FileExist(cpp)
            return
        t := FileRead(cpp, "UTF-8")
        inj := "`r`n    // --- payload decode (AHK2BC) ---`r`n"
        if (cfg.payload_compress)
            inj .= "    typedef long (__stdcall *RtlDecompressBuffer_t)(unsigned short, unsigned char*, unsigned long, unsigned char*, unsigned long, unsigned long*);`r`n    HMODULE hNtdll = GetModuleHandle(TEXT(`"ntdll.dll`"));`r`n    RtlDecompressBuffer_t __RtlDecompressBuffer = (RtlDecompressBuffer_t)GetProcAddress(hNtdll, `"RtlDecompressBuffer`");`r`n    unsigned long uncompressedSize = *(unsigned long*)((LPBYTE)textbuf.mBuffer);`r`n    LPBYTE pCompressed = ((LPBYTE)textbuf.mBuffer) + 4;`r`n    unsigned long compressedSize = (unsigned long)textbuf.mLength - 4;`r`n    LPBYTE newBuf = (LPBYTE)malloc(uncompressedSize);`r`n    unsigned long finalSize = 0;`r`n    if (__RtlDecompressBuffer) __RtlDecompressBuffer(2 | 0x100, newBuf, uncompressedSize, pCompressed, compressedSize, &finalSize);`r`n    textbuf.mBuffer = newBuf;`r`n    textbuf.mLength = finalSize;`r`n"
        if (cfg.payload_encrypt) {
            inj .= "    unsigned char S[256];`r`n    for (int i = 0; i < 256; i++) S[i] = i;`r`n    int j = 0;`r`n    const unsigned char key[] = `"" keyStr "`";`r`n    size_t keyLen = " StrLen(keyStr) ";`r`n    for (int i = 0; i < 256; i++) { j = (j + S[i] + key[i `% keyLen]) `% 256; unsigned char tt = S[i]; S[i] = S[j]; S[j] = tt; }`r`n"
            if (!cfg.payload_compress)
                inj .= "    LPBYTE newBufEnc = (LPBYTE)malloc(textbuf.mLength);`r`n    memcpy(newBufEnc, textbuf.mBuffer, textbuf.mLength);`r`n    textbuf.mBuffer = newBufEnc;`r`n"
            inj .= "    { int i2 = 0; j = 0; LPBYTE data = (LPBYTE)textbuf.mBuffer; size_t dataLen = textbuf.mLength; for (size_t k = 0; k < dataLen; k++) { i2 = (i2 + 1) `% 256; j = (j + S[i2]) `% 256; unsigned char tt = S[i2]; S[i2] = S[j]; S[j] = tt; data[k] ^= S[(S[i2] + S[j]) `% 256]; } }`r`n"
        }
        inj .= "    // --- end payload decode ---`r`n`r`n"
        t := StrReplace(t, "// NOTE: Ahk2Exe strips off the UTF-8 BOM.", inj "    // NOTE: Ahk2Exe strips off the UTF-8 BOM.")
        this.Save(cpp, t)
    }

    ResolveIncludes(filePath, visited := "") {
        if !visited
            visited := Map()
        SplitPath(filePath, &fName, &fDir)
        abs := fDir "\" fName
        if visited.Has(abs)
            return ""
        visited[abs] := true
        try content := FileRead(filePath, "UTF-8")
        catch
            return ""
        out := ""
        Loop Parse content, "`n", "`r" {
            line := A_LoopField
            if RegExMatch(line, "i)^\s*#Include(?:Again)?\s+(.+)$", &m) {
                inc := Trim(m[1], " `'`""), tp := ""
                if RegExMatch(inc, "^<(.+)>$", &lm) {
                    localLib := fDir "\Lib\" lm[1] ".ahk"
                    docs := EnvGet("USERPROFILE") "\Documents\AutoHotkey\Lib\" lm[1] ".ahk"
                    tp := FileExist(localLib) ? localLib : (FileExist(docs) ? docs : "")
                } else if FileExist(fDir "\" inc)
                    tp := fDir "\" inc
                if (tp != "")
                    out .= this.ResolveIncludes(tp, visited) "`r`n"
                else
                    out .= line "`r`n"
            } else
                out .= line "`r`n"
        }
        return out
    }

    CleanAhkCode(code) {
        code := RegExReplace(code, "s)/\*.*?\*/", "")
        out := ""
        Loop Parse code, "`n", "`r" {
            line := Trim(A_LoopField, " `t")
            if (line = "" || RegExMatch(line, "i)^#Requires"))
                continue
            inQ := "", cpos := 0, esc := false
            Loop StrLen(line) {
                c := SubStr(line, A_Index, 1)
                if esc {
                    esc := false
                    continue
                }
                if c = "``" {
                    esc := true
                    continue
                }
                if (inQ = "") {
                    if (c = '"' || c = "'")
                        inQ := c
                    else if (c = ";" && (A_Index = 1 || SubStr(line, A_Index - 1, 1) ~= "[ `t]")) {
                        cpos := A_Index
                        break
                    }
                } else if (c = inQ)
                    inQ := ""
            }
            if (cpos > 0)
                line := Trim(SubStr(line, 1, cpos - 1), " `t")
            if (line != "")
                out .= line "`r`n"
        }
        return out
    }

    EncryptRC4(buf, key) {
        s := Buffer(256)
        Loop 256
            NumPut("UChar", A_Index - 1, s, A_Index - 1)
        j := 0, keyLen := StrLen(key)
        Loop 256 {
            i := A_Index - 1
            j := (j + NumGet(s, i, "UChar") + Ord(SubStr(key, Mod(i, keyLen) + 1, 1))) & 255
            t := NumGet(s, i, "UChar")
            NumPut("UChar", NumGet(s, j, "UChar"), s, i), NumPut("UChar", t, s, j)
        }
        i := 0, j := 0
        Loop buf.Size {
            i := (i + 1) & 255
            j := (j + NumGet(s, i, "UChar")) & 255
            t := NumGet(s, i, "UChar")
            NumPut("UChar", NumGet(s, j, "UChar"), s, i), NumPut("UChar", t, s, j)
            k := NumGet(s, (NumGet(s, i, "UChar") + NumGet(s, j, "UChar")) & 255, "UChar")
            off := A_Index - 1
            NumPut("UChar", NumGet(buf, off, "UChar") ^ k, buf, off)
        }
    }

    CompressLZNT1(inBuf, &outBuf, &outSize) {
        wsSize := 0, fragSize := 0
        DllCall("ntdll\RtlGetCompressionWorkSpaceSize", "UShort", 2, "UInt*", &wsSize, "UInt*", &fragSize, "UInt")
        ws := Buffer(wsSize)
        cap := inBuf.Size + 4096, tmp := Buffer(cap), fin := 0
        DllCall("ntdll\RtlCompressBuffer", "UShort", 0x102, "Ptr", inBuf, "UInt", inBuf.Size, "Ptr", tmp, "UInt", cap, "UInt", 4096, "UInt*", &fin, "Ptr", ws, "UInt")
        outSize := fin + 4
        outBuf := Buffer(outSize)
        NumPut("UInt", inBuf.Size, outBuf, 0)
        DllCall("RtlMoveMemory", "Ptr", outBuf.Ptr + 4, "Ptr", tmp.Ptr, "UPtr", fin)
    }

    ; ---- orchestrator ------------------------------------------------------
    ; Returns an array of {label, ok, bytes, path, errors}.
    BuildProfile(cfg) {
        this.cancelled := false
        ; Fast path: compile a script into a prebuilt base (no source, no MSVC) - the
        ; Ahk2Exe-style workflow.  Feature stripping / regex backend / hardening that
        ; require a C++ rebuild do not apply here; metadata & icons come from the base.
        if (cfg.kind = "script" && cfg.HasOwnProp("base_mode") && cfg.base_mode = "prebuilt")
            return this.CompilePrebuilt(cfg)

        results := []
        this.AcquireSource(cfg)
        this.ApplyProfile(cfg)
        if (cfg.kind = "script")
            this.EmbedScript(cfg)

        platforms := []
        for p in this.SplitList(cfg.arch)
            platforms.Push((p = "x86" || p = "win32" || p = "32") ? "Win32" : "x64")
        if !platforms.Length
            platforms.Push("x64")

        ; engine can emit exe and/or bin; script always emits an exe from the SC base.
        targets := (cfg.kind = "script") ? ["bin"] : this.SplitList(cfg.HasOwnProp("targets") ? cfg.targets : "exe")
        config := "Release"
        for t in targets
            if (t = "bin")
                config := "Self-contained"

        for platform in platforms {
            for t in targets {
                cf := (t = "bin") ? "Self-contained" : "Release"
                this.Log("[*] MSBuild " cf " | " platform " ...")
                r := this.Build(cfg, platform, cf)
                built := this.BuiltFile(platform, t)
                if (r.exit != 0 || built = "") {
                    this.Log("[!] Build failed:`n" r.errors)
                    results.Push({ label: platform "/" t, ok: false, bytes: 0, path: "", errors: r.errors })
                    continue
                }
                final := this.PlaceOutput(cfg, platform, t, built)
                if (cfg.kind = "script")
                    this.UpdateResources(final)         ; inject script + files, Ahk2Exe-style
                this.Compact(final, cfg.HasOwnProp("compress_exe") ? cfg.compress_exe : "none")
                results.Push({ label: platform "/" t, ok: true, bytes: FileGetSize(final), path: final, errors: "" })
                this.Log("[+] " platform "/" t " -> " final " (" Round(FileGetSize(final) / 1024) " KB)")
            }
        }
        this.CleanArtifacts()
        return results
    }

    VerParts(v) {
        p := [], pos := 1
        while (pos := RegExMatch(v, "\d+", &m, pos))
            p.Push(Integer(m[0])), pos += m.Len
        while p.Length < 4
            p.Push(0)
        return p
    }

    ; Build a VS_VERSIONINFO (RT_VERSION) binary from the profile's metadata.
    BuildVersionResource(cfg) {
        get(p) => (cfg.HasOwnProp(p) ? cfg.%p% : "")
        fvs := (get("fileversion") != "") ? get("fileversion") : "1.0.0.0"
        fv := this.VerParts(fvs)
        SplitPath(cfg.HasOwnProp("output") && cfg.output != "" ? cfg.output : cfg.script, &outName)
        strings := []                              ; [name, value] pairs, only non-empty
        adds(k, v) => (v != "" ? strings.Push([k, v]) : 0)
        adds("CompanyName", get("company"))
        adds("FileDescription", get("filedesc"))
        adds("FileVersion", fvs)
        adds("InternalName", get("internalname"))
        adds("LegalCopyright", get("copyright"))
        adds("LegalTrademarks", get("trademarks"))
        adds("OriginalFilename", get("origfilename") != "" ? get("origfilename") : outName)
        adds("ProductName", get("product"))
        adds("ProductVersion", fvs)

        b := ByteBuf()
        viLen := b.Mark(), b.W(0)                  ; VS_VERSIONINFO wLength (patch)
        b.W(52)                                    ; wValueLength = sizeof VS_FIXEDFILEINFO
        b.W(0)                                     ; wType = binary
        b.WStr("VS_VERSION_INFO"), b.Align()
        ; VS_FIXEDFILEINFO
        b.D(0xFEEF04BD), b.D(0x00010000)
        b.D((fv[1] << 16) | fv[2]), b.D((fv[3] << 16) | fv[4])   ; FileVersion MS/LS
        b.D((fv[1] << 16) | fv[2]), b.D((fv[3] << 16) | fv[4])   ; ProductVersion MS/LS
        b.D(0x3F), b.D(0)                          ; FileFlagsMask, FileFlags
        b.D(4), b.D(1), b.D(0)                     ; FileOS=VOS_NT_WINDOWS32, FileType=APP, subtype
        b.D(0), b.D(0)                             ; FileDate MS/LS
        b.Align()
        ; StringFileInfo
        sfiLen := b.Mark(), b.W(0), b.W(0), b.W(1), b.WStr("StringFileInfo"), b.Align()
        stLen := b.Mark(), b.W(0), b.W(0), b.W(1), b.WStr("040904B0"), b.Align()   ; US English, Unicode
        for pair in strings {
            sLen := b.Mark(), b.W(0)
            b.W(StrLen(pair[2]) + 1)               ; wValueLength = chars incl null
            b.W(1)                                 ; wType = text
            b.WStr(pair[1]), b.Align()
            b.WStr(pair[2]), b.Align()
            b.PatchW(sLen)
        }
        b.PatchW(stLen), b.PatchW(sfiLen)
        ; VarFileInfo
        vfiLen := b.Mark(), b.W(0), b.W(0), b.W(1), b.WStr("VarFileInfo"), b.Align()
        vLen := b.Mark(), b.W(0), b.W(4), b.W(0), b.WStr("Translation"), b.Align()
        b.D(0x04B00409)                            ; 0x0409, 0x04B0
        b.PatchW(vLen), b.PatchW(vfiLen)
        b.PatchW(viLen)
        return b
    }

    ; Parse an .ico into RT_ICON images + build the RT_GROUP_ICON directory.
    ; Returns {images: [{id, buf, size}], group: ByteBuf} or "" on failure.
    BuildIconResources(icoPath, firstId) {
        if (icoPath = "" || !FileExist(icoPath))
            return ""
        f := FileOpen(icoPath, "r-d"), n := f.Length, raw := Buffer(n), f.RawRead(raw), f.Close()
        p := raw.Ptr
        if (NumGet(p, 2, "UShort") != 1)           ; idType must be 1 (icon)
            return ""
        count := NumGet(p, 4, "UShort")
        images := [], grp := ByteBuf()
        grp.W(0), grp.W(1), grp.W(count)           ; GRPICONDIR: reserved, type, count
        Loop count {
            e := 6 + (A_Index - 1) * 16            ; ICONDIRENTRY (16 bytes)
            bw := NumGet(p, e, "UChar"), bh := NumGet(p, e + 1, "UChar")
            cc := NumGet(p, e + 2, "UChar"), planes := NumGet(p, e + 4, "UShort")
            bits := NumGet(p, e + 6, "UShort"), sz := NumGet(p, e + 8, "UInt"), off := NumGet(p, e + 12, "UInt")
            id := firstId + A_Index - 1
            img := Buffer(sz)
            DllCall("RtlMoveMemory", "Ptr", img.Ptr, "Ptr", p + off, "UPtr", sz)
            images.Push({ id: id, buf: img, size: sz })
            ; GRPICONDIRENTRY (14 bytes): w,h,cc,reserved,planes,bits,bytesInRes(4),id(2)
            grp.Byte(bw), grp.Byte(bh), grp.Byte(cc), grp.Byte(0)
            grp.W(planes), grp.W(bits), grp.D(sz), grp.W(id)
        }
        return { images: images, group: grp }
    }

    ; Stamp version-info and main icon into a prebuilt exe (what Ahk2Exe does).
    StampVersionAndIcon(exePath, cfg) {
        hasMeta := false
        for p in ["company","product","filedesc","fileversion","copyright","origfilename","internalname","trademarks"]
            if (cfg.HasOwnProp(p) && cfg.%p% != "")
                hasMeta := true
        icons := this.BuildIconResources(cfg.HasOwnProp("icon_main") ? cfg.icon_main : "", 2000)
        if (!hasMeta && !icons)
            return
        h := DllCall("BeginUpdateResourceW", "WStr", exePath, "Int", 0, "Ptr")
        if !h
            throw Error("BeginUpdateResource failed for version/icon stamping")
        if hasMeta {
            vb := this.BuildVersionResource(cfg)
            DllCall("UpdateResourceW", "Ptr", h, "Ptr", 16, "Ptr", 1, "UShort", 1033, "Ptr", vb.buf.Ptr, "UInt", vb.pos)  ; RT_VERSION, id 1
            this.Log("[*] Stamped version info.")
        }
        if icons {
            gid := this.MainIconGroupId(exePath)
            for im in icons.images
                DllCall("UpdateResourceW", "Ptr", h, "Ptr", 3, "Ptr", im.id, "UShort", 1033, "Ptr", im.buf.Ptr, "UInt", im.size)   ; RT_ICON
            DllCall("UpdateResourceW", "Ptr", h, "Ptr", 14, "Ptr", gid, "UShort", 1033, "Ptr", icons.group.buf.Ptr, "UInt", icons.group.pos)   ; RT_GROUP_ICON
            this.Log("[*] Replaced main icon (group #" gid ").")
        }
        if !DllCall("EndUpdateResourceW", "Ptr", h, "Int", 0)
            throw Error("EndUpdateResource failed while stamping version/icon")
    }

    ; The lowest RT_GROUP_ICON id is the icon Explorer shows for the exe.
    MainIconGroupId(exePath) {
        ids := []
        EnumGrp(hMod, lpType, lpName, lParam) {
            if ((lpName >> 16) = 0)              ; integer-named resource only
                ids.Push(lpName)
            return 1
        }
        cb := CallbackCreate(EnumGrp, "F", 4)
        hMod := DllCall("LoadLibraryExW", "WStr", exePath, "Ptr", 0, "UInt", 0x2, "Ptr")  ; LOAD_LIBRARY_AS_DATAFILE
        if hMod {
            DllCall("EnumResourceNamesW", "Ptr", hMod, "Ptr", 14, "Ptr", cb, "Ptr", 0)
            DllCall("FreeLibrary", "Ptr", hMod)
        }
        CallbackFree(cb)
        min := 0
        for id in ids
            if (id > 0 && (min = 0 || id < min))
                min := id
        return min ? min : 159        ; AutoHotkey's IDI_MAIN fallback
    }

    ; Ahk2Exe-style: bake the script into an existing base exe/bin, no compiler.
    CompilePrebuilt(cfg) {
        base := cfg.base_file
        if (base = "" || !FileExist(base))
            base := this.FindInstalledBase(cfg.arch)   ; fall back to the installed AutoHotkey
        if (base = "" || !FileExist(base))
            throw Error("No prebuilt base found. Set a base .exe/.bin on the Script tab, or install AutoHotkey v2.")
        if (cfg.payload_encrypt || cfg.payload_compress)
            this.Log("[!] Note: payload encrypt/compress need a compiled decoder; ignored in prebuilt mode.")
        cfg.payload_encrypt := false, cfg.payload_compress := false
        this.EmbedScript(cfg)                       ; prepares scriptBytes + embedResources (+ directives, metadata parse)
        if (cfg.HasOwnProp("output") && Trim(cfg.output) != "") {
            final := Trim(cfg.output)
        } else {
            SplitPath(cfg.script, , &d, , &nameNoExt)
            final := d "\" nameNoExt ".exe"
        }
        this.Log("[*] Prebuilt base: " base)
        FileCopy(base, final, 1)
        this.UpdateResources(final)
        this.StampVersionAndIcon(final, cfg)        ; metadata + main icon (Ahk2Exe-style)
        this.Compact(final, cfg.HasOwnProp("compress_exe") ? cfg.compress_exe : "none")
        this.Log("[+] Compiled (prebuilt) -> " final " (" Round(FileGetSize(final) / 1024) " KB)")
        return [{ label: "prebuilt", ok: true, bytes: FileGetSize(final), path: final, errors: "" }]
    }

    ; Locate an installed AutoHotkey exe to use as a prebuilt base.
    FindInstalledBase(arch) {
        bits := InStr(arch, "x86") && !InStr(arch, "x64") ? "32" : "64"
        for p in [A_ProgramFiles "\AutoHotkey\v2\AutoHotkey" bits ".exe"
                , A_ProgramFiles "\AutoHotkey\AutoHotkey" bits ".exe"
                , A_ProgramFiles "\AutoHotkey\v2\AutoHotkey.exe"
                , A_ProgramFiles "\AutoHotkey\AutoHotkey.exe"]
            if FileExist(p)
                return p
        return ""
    }

    PlaceOutput(cfg, platform, target, built) {
        bits := (platform = "Win32") ? "32" : "64"
        if (cfg.kind = "script") {
            if (cfg.HasOwnProp("output") && Trim(cfg.output) != "")
                dest := Trim(cfg.output)
            else {
                SplitPath(cfg.script, , &d, , &nameNoExt)
                dest := d "\" nameNoExt ".exe"
            }
        } else {
            outDir := this.appDir "\out\" RegExReplace(cfg.name, '[\\/:*?"<>|]', "_")
            DirCreate(outDir)
            if (target = "bin")
                dest := outDir "\" (cfg.crt = "os" ? "Unicode" : "Unicode") " " bits "-bit.bin"
            else
                dest := outDir "\AutoHotkey" bits ".exe"
        }
        FileCopy(built, dest, 1)
        return dest
    }

    ; ---- helpers -----------------------------------------------------------
    Save(path, content) {
        if FileExist(path)
            FileDelete(path)
        FileAppend(content, path, "UTF-8-RAW")
    }
    SaveBom(path, content) {
        if FileExist(path)
            FileDelete(path)
        f := FileOpen(path, "w", "UTF-8")
        f.Write(content), f.Close()
    }
    CopyTree(from, to) {
        DirCreate(to)
        RunWait(A_ComSpec ' /c robocopy "' from '" "' to '" /MIR /XD .git bin temp .vs build /NFL /NDL /NJH /NJS /NP', , "Hide")
    }
    RmDir(path) {
        RunWait(A_ComSpec ' /c rmdir /s /q "' path '"', , "Hide")
    }
}

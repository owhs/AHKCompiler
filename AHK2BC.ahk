; ============================================================================
;  AHK2 Builder & Compiler
;  One app, one profile format, two modes that share the same pipeline:
;    - Build engine : produce a custom AutoHotkey.exe / .bin
;    - Compile      : bake a script into that same custom engine -> standalone .exe
;  The engine lives in core.ahk; this file is the front end.  Builds run in a
;  spawned headless process (cli.ahk) so the window stays responsive and cancellable.
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#include profiles.ahk
#include core.ahk

Global AppDir   := A_ScriptDir
Global Store    := ProfileStore(AppDir "\data\profiles.ini")
Global Eng      := Engine(AppDir)            ; used for feature catalog + env checks only
Global Cur      := ""                        ; current profile name
Global Loading  := false
Global BuildPid := 0, LogPos := 0, LogFile := AppDir "\build\gui.log"
Global SelfTest := A_Args.Length && A_Args[1] = "/selftest"
Global FeatureRows := Map()                  ; feature name -> listview row

SelfOut(msg) {                       ; self-test log that tolerates no-stdout
    try {
        FileAppend(msg, "*")
    } catch {
        try DirCreate(A_ScriptDir "\build")
        try FileAppend(msg, A_ScriptDir "\build\selftest.log")
    }
}
if SelfTest
    OnError((e, *) => (SelfOut("SELFTEST ERROR: " e.Message " (line " e.Line ")`n"), ExitApp(1)))

; ---------------------------------------------------------------- GUI layout
G := Gui("+Resize +MinSize980x680", "AHK2 Builder && Compiler")
G.SetFont("s9", "Segoe UI")
G.OnEvent("Close", (*) => ExitApp())
G.OnEvent("Size", OnResize)

; Left rail: profiles
G.Add("Text", "x12 y10 w200 Section", "Profiles")
LB := G.Add("ListBox", "x12 y30 w210 h300 vProfileList")
LB.OnEvent("Change", (*) => SelectProfile(LB.Text))
G.Add("Button", "x12 y334 w68", "New").OnEvent("Click", ShowWizard)
G.Add("Button", "x84 y334 w68", "Copy").OnEvent("Click", CopyProfile)
G.Add("Button", "x156 y334 w66", "Delete").OnEvent("Click", DeleteProfile)
G.SetFont("s8", "Consolas")
LastInfo := G.Add("Text", "x12 y368 w210 h120 +0x1000")
G.SetFont("s9", "Segoe UI")

; Mode: three-way choice (mirrors the intro wizard). Drives kind + base_mode.
G.Add("Text", "x240 y12 w42", "Task:")
RbEngine  := G.Add("Radio", "x284 y11 w120", "Custom binary")
RbBuildC  := G.Add("Radio", "x404 y11 w118", "Binary + script")
RbPrebuilt:= G.Add("Radio", "x522 y11 w150", "Compile (prebuilt)")
RbEngine.OnEvent("Click",   (*) => SetMode("engine"))
RbBuildC.OnEvent("Click",   (*) => SetMode("build"))
RbPrebuilt.OnEvent("Click", (*) => SetMode("prebuilt"))
G.Add("Text", "x684 y12 w42", "Desc:")
EdDesc := G.Add("Edit", "x728 y9 w242 vdescription")
EdDesc.OnEvent("Change", (*) => Touch())

Tabs := G.Add("Tab3", "x240 y36 w735 h470", ["Build", "Features", "Script", "Metadata", "Icons", "Resources", "Environment"])

; ---- Build tab ----
Tabs.UseTab("Build")
G.Add("GroupBox", "x256 y70 w700 h96", "Source")
G.Add("Radio", "x268 y90 vsrc_git", "Git repo").OnEvent("Click", (*) => (Touch(), RefreshRelevance()))
G.Add("Radio", "x350 y90 vsrc_local", "Local folder").OnEvent("Click", (*) => (Touch(), RefreshRelevance()))
G.Add("Text", "x268 y116 w40", "Repo:")
G.Add("Edit", "x312 y112 w440 vsource_repo").OnEvent("Change", (*) => Touch())
G.Add("Text", "x760 y116 w44", "Branch:")
G.Add("Edit", "x806 y112 w140 vsource_branch").OnEvent("Change", (*) => Touch())
G.Add("Text", "x268 y142 w40", "Path:")
G.Add("Edit", "x312 y138 w560 vsource_path").OnEvent("Change", (*) => Touch())
G.Add("Button", "x878 y137 w68", "Browse").OnEvent("Click", BrowseSource)

G.Add("GroupBox", "x256 y174 w700 h140", "Compiler")
G.Add("Text", "x268 y196 w70", "Platform:")
G.Add("CheckBox", "x344 y195 vplat_x64", "x64").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x410 y195 vplat_x86", "x86 (32-bit)").OnEvent("Click", (*) => Touch())
G.Add("Text", "x268 y224 w70", "Optimize:")
DdOpt := G.Add("DropDownList", "x344 y220 w150 voptimize_ui", ["Size (/O1)", "Speed (/O2, official)"])
DdOpt.OnEvent("Change", (*) => Touch())
G.Add("Text", "x520 y224 w70", "C runtime:")
DdCrt := G.Add("DropDownList", "x596 y220 w200 vcrt_ui", ["Windows 10/11 (smallest)", "Static (runs anywhere)", "VC++ DLL (needs redist)"])
DdCrt.OnEvent("Change", (*) => Touch())
G.Add("Text", "x268 y252 w70", "RegEx:")
DdRegex := G.Add("DropDownList", "x344 y248 w200 vregex_ui", ["PCRE (bundled)", "Windows ICU (drops ~130 KB)"])
DdRegex.OnEvent("Change", (*) => Touch())
G.Add("CheckBox", "x560 y251 vltcg", "LTCG").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x630 y251 vstringpool", "String pooling").OnEvent("Click", (*) => Touch())
G.Add("Text", "x268 y280 w70", "Version:")
G.Add("Edit", "x344 y276 w150 vversion").OnEvent("Change", (*) => Touch())
G.Add("Text", "x500 y280 w440 cGray", "Optional label (use + not -, e.g. 2.0+lite)")
G.Add("Text", "x268 y304 w70 vlbl_targets", "Outputs:")
G.Add("CheckBox", "x344 y303 vtarget_exe", "AutoHotkey.exe").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x470 y303 vtarget_bin", "Ahk2Exe base (.bin)").OnEvent("Click", (*) => Touch())

G.Add("GroupBox", "x256 y322 w700 h82", "Targeting")
G.Add("Text", "x268 y344 w70", "UAC level:")
DdExec := G.Add("DropDownList", "x344 y340 w170 vexec_level_ui", ["asInvoker (normal)", "requireAdministrator", "highestAvailable"])
DdExec.OnEvent("Change", (*) => Touch())
G.Add("Text", "x532 y344 w56", "Min Win:")
DdMinWin := G.Add("DropDownList", "x592 y340 w200 vmin_win_ui", ["(compiler default)", "Windows 7 (6.1)", "Windows 8.1 (6.3)", "Windows 10/11 (10.0)"])
DdMinWin.OnEvent("Change", (*) => Touch())
G.Add("CheckBox", "x812 y343 vconsole", "Console app").OnEvent("Click", (*) => Touch())
G.Add("Text", "x268 y374 w130", "Extra /D defines:")
G.Add("Edit", "x400 y370 w540 vextra_defines").OnEvent("Change", (*) => Touch())

; ---- Features tab ----
Tabs.UseTab("Features")
G.Add("Text", "x256 y72 w700", "Untick to strip. Removing a function makes scripts that call it fail at load with a clear error.")
FLV := G.Add("ListView", "x256 y92 w700 h370 Checked -Multi NoSortHdr", ["Feature", "Saves", "Group", "What it removes"])
FLV.OnEvent("ItemCheck", OnFeatureCheck)
FLV.OnEvent("ItemFocus", (c, r) => SetStatus(FeatureDescByRow(r)))
FTotal := G.Add("Text", "x256 y466 w700", "")

; ---- Script tab ----
Tabs.UseTab("Script")
G.Add("Text", "x256 y74 w80", "Script (.ahk):")
G.Add("Edit", "x344 y70 w540 vscript").OnEvent("Change", (*) => Touch())
G.Add("Button", "x890 y69 w64", "Browse").OnEvent("Click", (*) => (BrowseFile("script", "AutoHotkey Scripts (*.ahk)"), ReadDirectives(true)))
G.Add("Text", "x256 y106 w80", "Output (.exe):")
G.Add("Edit", "x344 y102 w540 voutput").OnEvent("Change", (*) => Touch())
G.Add("Button", "x890 y101 w64", "Browse").OnEvent("Click", (*) => BrowseSaveFile("output"))
G.Add("Text", "x256 y138 w84 vlbl_base", "Base binary:")
G.Add("Edit", "x344 y134 w540 vbase_file", "").OnEvent("Change", (*) => Touch())
G.Add("Button", "x890 y133 w64", "Base...").OnEvent("Click", (*) => BrowseFile("base_file", "AHK base (*.exe;*.bin)"))
G.Add("Text", "x344 y156 w610 cGray vbase_hint", "Prebuilt mode: leave blank to use your installed AutoHotkey, or pick a custom .bin you built.")
G.Add("GroupBox", "x256 y166 w700 h150", "Packaging")
G.Add("CheckBox", "x270 y186 vclean_script", "Strip comments / #Requires / blank lines before embedding").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x270 y208 vpayload_compress", "Compress embedded script (LZNT1)").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x560 y208 vpayload_encrypt", "Encrypt embedded script (RC4)").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x270 y228 viat_delayload", "Delay-load OS imports (cleaner import table, fewer AV false-positives)").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x270 y248 viat_hooks", "Route OS imports via runtime resolution (deeper import-table cleaning)").OnEvent("Click", (*) => Touch())
G.Add("CheckBox", "x270 y268 vscrub_strings", "Scrub AutoHotkey signature strings (white-label)").OnEvent("Click", (*) => Touch())
G.Add("Text", "x270 y292 w80", "Compress exe:")
DdCompress := G.Add("DropDownList", "x354 y288 w160 vcompress_exe_ui", ["none", "xpress4k", "xpress8k", "xpress16k", "lzx"])
DdCompress.OnEvent("Change", (*) => Touch())
G.Add("Text", "x524 y292 w420 cGray", "NTFS transparent compression (no packer, AV-safe)")
G.Add("Button", "x256 y326 w360", "Auto-fill from Ahk2Exe directives in script").OnEvent("Click", (*) => ReadDirectives(false))
G.Add("Text", "x624 y330 w330 cGray vDirStatus", "")

; ---- Metadata tab ----
Tabs.UseTab("Metadata")
MetaField(74,  "Company:",     "company")
MetaField(106, "Product:",     "product")
MetaField(138, "Description:", "filedesc")
MetaField(170, "Version:",     "fileversion")
MetaField(202, "Copyright:",   "copyright")
MetaField(234, "Orig. name:",  "origfilename")
MetaField(266, "Internal:",    "internalname")
MetaField(298, "Trademarks:",  "trademarks")
MetaField(y, label, vn) {
    G.Add("Text", "x256 y" y+4 " w90", label)
    G.Add("Edit", "x350 y" y " w420 v" vn).OnEvent("Change", (*) => Touch())
}

; ---- Icons tab ----
Tabs.UseTab("Icons")
IconRow(74,  "Main:",          "icon_main")
IconRow(106, "Suspend:",       "icon_suspend")
IconRow(138, "Pause:",         "icon_pause")
IconRow(170, "Pause+Suspend:", "icon_pausesuspend")
IconRow(202, "File type:",     "icon_filetype")
IconRow(y, label, vn) {
    G.Add("Text", "x256 y" y+4 " w100", label)
    G.Add("Edit", "x360 y" y " w500 v" vn).OnEvent("Change", (*) => Touch())
    G.Add("Button", "x866 y" y-1 " w88", "Browse").OnEvent("Click", (*) => BrowseFile(vn, "Icons (*.ico)"))
}

; ---- Resources tab ----
Tabs.UseTab("Resources")
G.Add("Text", "x256 y74 w90", "Name:")
G.Add("Edit", "x316 y70 w150 vResName", "CUSTOM_DATA")
G.Add("Text", "x476 y74 w40", "File:")
G.Add("Edit", "x516 y70 w300 vResPath")
G.Add("Button", "x822 y69 w60", "...").OnEvent("Click", (*) => BrowseInto("ResPath"))
G.Add("CheckBox", "x316 y98 vResEnc", "Encrypt")
G.Add("CheckBox", "x390 y98 vResCmp", "Compress")
G.Add("Button", "x470 y97 w70", "Add").OnEvent("Click", AddRes)
RLV := G.Add("ListView", "x256 y124 w700 h300 +Grid", ["Name", "File", "Enc", "Cmp"])
RLV.ModifyCol(1, 130), RLV.ModifyCol(2, 430), RLV.ModifyCol(3, 45), RLV.ModifyCol(4, 45)
G.Add("Button", "x256 y430 w120", "Remove selected").OnEvent("Click", RemoveRes)

; ---- Environment tab ----
Tabs.UseTab("Environment")
G.Add("Text", "x256 y76 w120", "Git:")
GitStat := G.Add("Text", "x380 y76 w560", "checking...")
G.Add("Text", "x256 y104 w120", "MSBuild / C++:")
MsvcStat := G.Add("Text", "x380 y104 w560", "checking...")
G.Add("Text", "x256 y140 w120", "RegEx (Windows):")
IcuStat := G.Add("Text", "x380 y140 w560", "checking...")
G.Add("GroupBox", "x256 y176 w700 h96", "Overrides (optional)")
G.Add("Text", "x268 y200 w110", "git.exe:")
G.Add("Edit", "x384 y196 w480 voverride_git").OnEvent("Change", (*) => Touch())
G.Add("Button", "x872 y195 w70", "...").OnEvent("Click", (*) => BrowseInto("override_git"))
G.Add("Text", "x268 y232 w110", "MSBuild.exe:")
G.Add("Edit", "x384 y228 w480 voverride_msvc").OnEvent("Change", (*) => Touch())
G.Add("Button", "x872 y227 w70", "...").OnEvent("Click", (*) => BrowseInto("override_msvc"))
G.Add("CheckBox", "x268 y276 vshow_msbuild", "Show live MSBuild output in the log").OnEvent("Click", (*) => Touch())
G.Add("GroupBox", "x256 y306 w700 h96", "Advanced build flags (escape hatch)")
G.Add("Text", "x268 y330 w110", "Extra CL flags:")
G.Add("Edit", "x384 y326 w560 vextra_cl").OnEvent("Change", (*) => Touch())
G.Add("Text", "x268 y362 w110", "Extra LINK flags:")
G.Add("Edit", "x384 y358 w560 vextra_link").OnEvent("Change", (*) => Touch())

Tabs.UseTab()

; Action bar + log
BtnGo := G.Add("Button", "x240 y514 w200 h34 Default", "Build engine")
BtnGo.OnEvent("Click", StartBuild)
BtnCancel := G.Add("Button", "x448 y514 w100 h34 Disabled", "Cancel")
BtnCancel.OnEvent("Click", CancelBuild)
BtnOpen := G.Add("Button", "x556 y514 w110 h34", "Open output")
BtnOpen.OnEvent("Click", OpenOutput)
G.SetFont("s9", "Consolas")
LogBox := G.Add("Edit", "x12 y556 w963 h150 ReadOnly -Wrap +HScroll")
G.SetFont("s9", "Segoe UI")
SB := G.Add("StatusBar")

BuildFeatureList()
RefreshProfiles()
SelectProfile(Store.List().Length ? Store.List()[1] : "")
SetTimer(CheckEnv, -50)

if SelfTest {
    RunSelfTest()
} else {
    G.Show("w987 h732")
    ShowWizard()
}
return

; ---------------------------------------------------------------- intro wizard
ShowWizard(*) {
    w := Gui("+Owner" G.Hwnd " -MinimizeBox -MaximizeBox +ToolWindow", "What do you want to do?")
    w.SetFont("s10", "Segoe UI")
    w.Add("Text", "x20 y16 w520", "AHK2 Builder && Compiler").SetFont("s13 Bold")
    w.SetFont("s9", "Segoe UI")
    w.Add("Text", "x20 y46 w520 cGray", "Pick a task. You can change it any time with the Task buttons up top.")
    mk(y, title, desc, mode) {
        b := w.Add("Button", "x20 y" y " w520 h30")
        b.SetFont("s10 Bold"), b.Text := title
        b.OnEvent("Click", (*) => (w.Destroy(), WizardPick(mode)))
        w.SetFont("s8", "Segoe UI")
        w.Add("Text", "x24 y" (y + 33) " w512 cGray", desc)
        w.SetFont("s9", "Segoe UI")
    }
    mk(76,  "①  Create a custom AHK binary",
        "Build a stripped / hardened AutoHotkey.exe or .bin base - no script attached.", "engine")
    mk(140, "②  Create a custom binary + compile a script",
        "Build a custom engine AND bake your script into it (full control, needs the compiler).", "build")
    mk(204, "③  Compile a script (prebuilt base)",
        "Fast: bake your script into an existing base exe / .bin - no compiler. Metadata, icon and resources still apply.", "prebuilt")
    w.Add("Button", "x20 y270 w130", "Open existing...").OnEvent("Click", (*) => (w.Destroy()))
    w.Show("w560 h314")
}

; Wizard choice -> create a fresh profile of that task and select it.
WizardPick(mode) {
    base := (mode = "engine") ? "engine" : (mode = "prebuilt") ? "compile-prebuilt" : "compile"
    name := base, i := 1
    while Store.Has(name)
        name := base " " (++i)
    seed := Map("description", WizardDesc(mode))
    if (mode = "engine")
        seed["kind"] := "engine", seed["optimize"] := "size", seed["crt"] := "os"
    else {
        seed["kind"] := "script", seed["optimize"] := "size", seed["crt"] := "os", seed["clean_script"] := "1", seed["compress_exe"] := "lzx"
        seed["base_mode"] := (mode = "prebuilt") ? "prebuilt" : "build"
    }
    Store.Save(name, seed)
    RefreshProfiles(), SelectProfile(name)
    ; jump to the most relevant tab
    Tabs.Value := (mode = "engine") ? 1 : 3
}
WizardDesc(mode) => (mode = "engine") ? "Custom AutoHotkey binary"
    : (mode = "prebuilt") ? "Script compiled into a prebuilt base" : "Custom binary with script compiled in"

; ---------------------------------------------------------------- profiles
RefreshProfiles() {
    LB.Delete()
    LB.Add(Store.List())
}

SelectProfile(name) {
    global Cur, Loading
    if (name = "" || !Store.Has(name))
        return
    Cur := name, LB.Choose(name)
    cfg := Store.ToConfig(name)
    Loading := true
    EdDesc.Value := cfg.description
    mode := (cfg.kind = "engine") ? "engine" : (cfg.base_mode = "prebuilt" ? "prebuilt" : "build")
    RbEngine.Value := (mode = "engine"), RbBuildC.Value := (mode = "build"), RbPrebuilt.Value := (mode = "prebuilt")
    G["src_git"].Value := (cfg.source_mode != "local"), G["src_local"].Value := (cfg.source_mode = "local")
    G["source_repo"].Value := cfg.source_repo, G["source_branch"].Value := cfg.source_branch
    G["source_path"].Value := cfg.source_path
    plats := "," StrReplace(cfg.arch, " ") ","
    G["plat_x64"].Value := InStr(plats, ",x64,") > 0
    G["plat_x86"].Value := RegExMatch(plats, "i),(x86|win32|32),") > 0
    DdOpt.Value := (cfg.optimize = "speed") ? 2 : 1
    DdCrt.Value := (cfg.crt = "static") ? 2 : (cfg.crt = "dll") ? 3 : 1
    DdRegex.Value := (cfg.regex = "windows") ? 2 : 1
    G["ltcg"].Value := cfg.ltcg, G["stringpool"].Value := cfg.stringpool
    G["version"].Value := cfg.version
    DdExec.Value := (cfg.exec_level = "requireAdministrator") ? 2 : (cfg.exec_level = "highestAvailable") ? 3 : 1
    DdMinWin.Value := Max(1, IndexOf(["", "6.1", "6.3", "10.0"], cfg.min_win))
    G["console"].Value := cfg.console
    G["extra_defines"].Value := cfg.extra_defines, G["extra_cl"].Value := cfg.extra_cl, G["extra_link"].Value := cfg.extra_link
    tg := "," StrReplace(cfg.targets, " ") ","
    G["target_exe"].Value := InStr(tg, ",exe,") > 0, G["target_bin"].Value := InStr(tg, ",bin,") > 0
    G["script"].Value := cfg.script, G["output"].Value := cfg.output
    G["base_file"].Value := cfg.base_file
    G["clean_script"].Value := cfg.clean_script
    G["payload_compress"].Value := cfg.payload_compress, G["payload_encrypt"].Value := cfg.payload_encrypt
    G["iat_delayload"].Value := cfg.iat_delayload, G["iat_hooks"].Value := cfg.iat_hooks, G["scrub_strings"].Value := cfg.scrub_strings
    DdCompress.Value := Max(1, IndexOf(["none","xpress4k","xpress8k","xpress16k","lzx"], cfg.compress_exe))
    for vn in ["company","product","filedesc","fileversion","copyright","origfilename","internalname","trademarks",
               "icon_main","icon_suspend","icon_pause","icon_pausesuspend","icon_filetype",
               "override_git","override_msvc"]
        G[vn].Value := cfg.%vn%
    G["show_msbuild"].Value := cfg.show_msbuild
    ApplyRemovedToList(cfg.remove)
    LoadResList(cfg.resources)
    Loading := false
    RefreshRelevance(), UpdateTotal(), ShowLast()
}

IndexOf(arr, v) {
    for i, x in arr
        if (x = v)
            return i
    return 0
}

; Collect the whole form into a Map for saving.
CurMode() => RbEngine.Value ? "engine" : (RbPrebuilt.Value ? "prebuilt" : "build")

Collect() {
    d := Map()
    mode := CurMode()
    d["kind"] := (mode = "engine") ? "engine" : "script"
    d["base_mode"] := (mode = "prebuilt") ? "prebuilt" : "build"
    d["description"] := EdDesc.Value
    d["source_mode"] := G["src_local"].Value ? "local" : "git"
    d["source_repo"] := G["source_repo"].Value, d["source_branch"] := G["source_branch"].Value
    d["source_path"] := G["source_path"].Value
    plats := []
    (G["plat_x64"].Value && plats.Push("x64")), (G["plat_x86"].Value && plats.Push("x86"))
    d["arch"] := plats.Length ? JoinCsv(plats) : "x64"
    d["optimize"] := (DdOpt.Value = 2) ? "speed" : "size"
    d["crt"] := (DdCrt.Value = 2) ? "static" : (DdCrt.Value = 3) ? "dll" : "os"
    d["regex"] := (DdRegex.Value = 2) ? "windows" : "pcre"
    d["ltcg"] := G["ltcg"].Value, d["stringpool"] := G["stringpool"].Value
    d["version"] := G["version"].Value
    d["exec_level"] := ["asInvoker","requireAdministrator","highestAvailable"][DdExec.Value]
    d["min_win"] := ["", "6.1", "6.3", "10.0"][DdMinWin.Value]
    d["console"] := G["console"].Value
    tg := []
    (G["target_exe"].Value && tg.Push("exe")), (G["target_bin"].Value && tg.Push("bin"))
    d["targets"] := tg.Length ? JoinCsv(tg) : "exe"
    d["base_file"] := G["base_file"].Value
    d["remove"] := JoinCsv(RemovedFeatures())
    for vn in ["script","output","company","product","filedesc","fileversion","copyright",
               "origfilename","internalname","trademarks","extra_defines","extra_cl","extra_link",
               "icon_main","icon_suspend","icon_pause","icon_pausesuspend","icon_filetype",
               "override_git","override_msvc"]
        d[vn] := G[vn].Value
    for vn in ["clean_script","payload_compress","payload_encrypt","iat_delayload","iat_hooks","scrub_strings","show_msbuild"]
        d[vn] := G[vn].Value
    d["compress_exe"] := ["none","xpress4k","xpress8k","xpress16k","lzx"][DdCompress.Value]
    return d
}
JoinCsv(arr) {
    s := ""
    for x in arr
        s .= (A_Index > 1 ? "," : "") x
    return s
}

Touch() {
    if Loading || Cur = ""
        return
    Store.Save(Cur, Collect())
    Store.SaveResources(Cur, CollectRes())
    SetTimer(UpdateTotal, -1)
}

SetMode(mode) {
    if Loading
        return
    Touch()
    RefreshRelevance()
}

; Enable only the controls relevant to the chosen task, so irrelevant panes grey out.
RefreshRelevance() {
    mode := CurMode()                       ; engine | build | prebuilt
    isScript := (mode != "engine")
    needsBuild := (mode != "prebuilt")      ; engine + build compile from source; prebuilt does not
    BtnGo.Text := (mode = "engine") ? "Build engine" : "Compile executable"

    En(names, on) {
        for n in names
            try G[n].Enabled := on
    }
    ; Source + all compiler/feature/targeting options require a source build.
    isLocal := G["src_local"].Value
    En(["src_git","src_local","optimize_ui","crt_ui","regex_ui","ltcg","stringpool","version"
      , "exec_level_ui","min_win_ui","console","extra_defines","extra_cl","extra_link"
      , "plat_x64","plat_x86"], needsBuild)
    En(["source_repo","source_branch"], needsBuild && !isLocal)
    En(["source_path"], needsBuild && isLocal)
    FLV.Enabled := needsBuild               ; feature stripping
    ; Engine-only outputs.
    En(["target_exe","target_bin","lbl_targets"], mode = "engine")
    ; Script inputs.
    En(["script","output"], isScript)
    En(["base_file","lbl_base","base_hint"], mode = "prebuilt")
    ; Packaging: metadata/icons/resources + NTFS work in both compile modes; the
    ; source-build-only hardening (payload transform, IAT hooks, scrub) doesn't in prebuilt.
    En(["clean_script","compress_exe_ui"], isScript)
    En(["payload_compress","payload_encrypt","iat_delayload","iat_hooks","scrub_strings"], isScript && needsBuild)
    En(["company","product","filedesc","fileversion","copyright","origfilename","internalname","trademarks"], isScript)
    En(["icon_main","icon_suspend","icon_pause","icon_pausesuspend","icon_filetype"], isScript)
    En(["ResName","ResPath","ResEnc","ResCmp"], isScript)
    RLV.Enabled := isScript
}

; ---------------------------------------------------------------- features
BuildFeatureList() {
    FLV.Delete(), FeatureRows.Clear()
    for name in Eng.featureOrder {
        f := Eng.features[name]
        row := FLV.Add("Check", f["title"], (f["kb"] != "" ? f["kb"] " KB" : "?"), f["group"], f["desc"])
        FeatureRows[name] := row
    }
    FLV.ModifyCol(1, 210), FLV.ModifyCol(2, 60 " Right"), FLV.ModifyCol(3, 90), FLV.ModifyCol(4, 320)
}

ApplyRemovedToList(removeCsv) {
    rem := "," StrReplace(removeCsv, " ") ","
    for name, row in FeatureRows
        FLV.Modify(row, InStr(rem, "," name ",") ? "-Check" : "Check")
}

RemovedFeatures() {
    out := []
    for name, row in FeatureRows
        if !RowChecked(row)
            out.Push(name)
    return out
}
RowChecked(row) => (SendMessage(0x102C, row - 1, 0xF000, FLV) >> 12) = 2

RowToFeature(row) {
    for name, r in FeatureRows
        if (r = row)
            return name
    return ""
}
FeatureDescByRow(row) {
    n := RowToFeature(row)
    return n != "" ? Eng.features[n]["title"] ": " Eng.features[n]["desc"] : ""
}

OnFeatureCheck(ctrl, row, checked) {
    if Loading
        return
    Loading := true
    name := RowToFeature(row)
    ; keep implied features consistent (e.g. com implies gui-activex, regex implies regex-unicode)
    if !checked {
        for dep in Eng.SplitList(Eng.features[name]["implies"])
            if FeatureRows.Has(dep)
                FLV.Modify(FeatureRows[dep], "-Check")
    } else {
        for other, r in FeatureRows
            for dep in Eng.SplitList(Eng.features[other]["implies"])
                if (dep = name)
                    FLV.Modify(r, "Check")
    }
    Loading := false
    Touch()
}

UpdateTotal() {
    removed := RemovedFeatures()
    total := 0, unknown := 0
    for name in removed {
        kb := Eng.features[name]["kb"]
        (kb = "") ? unknown++ : total += Integer(kb)
    }
    extra := (DdRegex.Value = 2) ? "  +~130 KB from Windows RegEx backend" : ""
    FTotal.Value := removed.Length
        ? "Stripping " removed.Length " feature(s): about " total " KB" (unknown ? " (+" unknown " unmeasured)" : "") extra
        : "All features kept." extra
}

; ---------------------------------------------------------------- resources
AddRes(*) {
    if (G["ResName"].Value = "" || G["ResPath"].Value = "")
        return
    RLV.Add(, G["ResName"].Value, G["ResPath"].Value, G["ResEnc"].Value ? "Yes" : "No", G["ResCmp"].Value ? "Yes" : "No")
    Touch()
}
RemoveRes(*) {
    if (r := RLV.GetNext())
        RLV.Delete(r), Touch()
}
LoadResList(arr) {
    RLV.Delete()
    for r in arr
        RLV.Add(, r.Name, r.Path, r.Encrypt ? "Yes" : "No", r.Compress ? "Yes" : "No")
}
CollectRes() {
    arr := []
    Loop RLV.GetCount()
        arr.Push({ Name: RLV.GetText(A_Index, 1), Path: RLV.GetText(A_Index, 2)
            , Encrypt: RLV.GetText(A_Index, 3) = "Yes", Compress: RLV.GetText(A_Index, 4) = "Yes" })
    return arr
}

; ---------------------------------------------------------------- build run
StartBuild(*) {
    global BuildPid, LogPos
    if BuildPid
        return
    Touch()
    if (Cur = "")
        return
    cfg := Store.ToConfig(Cur)
    if (cfg.kind = "script" && (cfg.script = "" || !FileExist(cfg.script))) {
        MsgBox("Pick a valid script on the Script tab first.", "AHK2BC", "Icon!")
        return
    }
    DirCreate(AppDir "\build")
    try FileDelete(LogFile)
    LogBox.Value := "", LogPos := 0
    exe := A_AhkPath
    quoted := '"' exe '" "' AppDir '\cli.ahk" /build "' Cur '"'
    Run(A_ComSpec ' /c ' quoted ' > "' LogFile '" 2>&1', AppDir, "Hide", &pid)
    BuildPid := pid
    SetBusy(true)
    SetStatus((cfg.kind = "script" ? "Compiling " : "Building ") Cur " ...")
    SetTimer(PollLog, 250)
}

PollLog() {
    global BuildPid, LogPos
    try {
        f := FileOpen(LogFile, "r", "UTF-8")
        f.Pos := LogPos
        chunk := f.Read()
        LogPos := f.Pos
        f.Close()
        if (chunk != "") {
            chunk := StrReplace(StrReplace(chunk, "`r`n", "`n"), "`n", "`r`n")
            SendMessage(0xB1, -1, -1, LogBox)
            SendMessage(0xC2, 0, StrPtr(chunk), LogBox)
        }
    }
    if ProcessExist(BuildPid)
        return
    SetTimer(PollLog, 0)
    BuildPid := 0
    SetBusy(false)
    txt := ""
    try txt := FileRead(LogFile, "UTF-8")
    ok := InStr(txt, "[+] DONE")
    SetStatus(ok ? "Done." : "Finished with errors - see log.")
    ShowLast()
    if SelfTest
        SetTimer(() => ExitApp(), -1500)
}

CancelBuild(*) {
    global BuildPid
    if BuildPid
        RunWait(A_ComSpec " /c taskkill /PID " BuildPid " /T /F", , "Hide")
}

SetBusy(b) {
    for c in [BtnGo, LB]
        c.Enabled := !b
    BtnCancel.Enabled := b
}

OpenOutput(*) {
    cfg := Store.ToConfig(Cur)
    if (cfg.kind = "script") {
        p := cfg.output != "" ? cfg.output : cfg.script
        SplitPath(p, , &d)
        if DirExist(d)
            Run("explorer.exe `"" d "`"")
    } else {
        d := AppDir "\out\" RegExReplace(Cur, '[\\/:*?"<>|]', "_")
        Run("explorer.exe `"" (DirExist(d) ? d : AppDir) "`"")
    }
}

ShowLast() {
    cfg := Store.ToConfig(Cur)
    if (cfg.kind = "script") {
        p := cfg.output != "" ? cfg.output : ""
        LastInfo.Value := (p != "" && FileExist(p))
            ? "  " Round(FileGetSize(p)/1024) " KB`n  " p
            : "  (not compiled yet)"
        return
    }
    d := AppDir "\out\" RegExReplace(Cur, '[\\/:*?"<>|]', "_")
    s := ""
    Loop Files, d "\*.*" {
        if (A_LoopFileExt = "exe" || A_LoopFileExt = "bin")
            s .= "  " Round(A_LoopFileSize/1024) " KB  " A_LoopFileName "`n"
    }
    LastInfo.Value := s != "" ? s : "  (not built yet)"
}

; ---------------------------------------------------------------- misc
NewProfile(*) {
    r := InputBox("New profile name:", "New profile", "w320 h120")
    if (r.Result != "OK" || Trim(r.Value) = "")
        return
    name := Trim(r.Value)
    if Store.Has(name)
        return MsgBox("That profile already exists.", "AHK2BC", "Icon!")
    Store.Save(name, Map("kind", "engine", "description", "New profile"))
    RefreshProfiles(), SelectProfile(name)
}
CopyProfile(*) {
    if (Cur = "")
        return
    r := InputBox("Name for the copy of '" Cur "':", "Copy profile", "w320 h120")
    if (r.Result != "OK" || Trim(r.Value) = "" || Store.Has(Trim(r.Value)))
        return
    Store.Duplicate(Cur, Trim(r.Value))
    RefreshProfiles(), SelectProfile(Trim(r.Value))
}
DeleteProfile(*) {
    if (Cur = "" || Store.List().Length <= 1)
        return
    if MsgBox("Delete profile '" Cur "'?", "AHK2BC", "YesNo Icon?") = "Yes" {
        Store.Delete(Cur)
        RefreshProfiles(), SelectProfile(Store.List()[1])
    }
}

BrowseSource(*) {
    if G["src_local"].Value {
        if (d := DirSelect(, 3, "Select the AutoHotkey source folder"))
            G["source_path"].Value := d, Touch()
    }
}
BrowseFile(vn, filter) {
    if (f := FileSelect(, , "Select file", filter))
        G[vn].Value := f, Touch()
}
BrowseInto(vn) {
    if (f := FileSelect(, , "Select file"))
        G[vn].Value := f, Touch()
}
BrowseSaveFile(vn) {
    if (f := FileSelect("S", , "Output executable", "Executable (*.exe)"))
        G[vn].Value := f, Touch()
}

; Parse ;@Ahk2Exe-* directives from the selected script and fill blank fields.
; quiet=true skips the popup (used on auto-run after Browse).
ReadDirectives(quiet) {
    path := G["script"].Value
    if (path = "" || !FileExist(path)) {
        if !quiet
            MsgBox("Pick a script first.", "AHK2BC", "Icon!")
        return
    }
    SplitPath(path, &sName, &sDir, , &sNoExt)
    text := FileRead(path, "UTF-8")
    n := 0, addedRes := 0
    fill(vn, val) {
        if (val != "" && G[vn].Value = "")
            G[vn].Value := val
    }
    Loop Parse text, "`n", "`r" {
        line := Trim(A_LoopField, " `t")
        if !RegExMatch(line, "i)^;@Ahk2Exe-(\w+)\s*[, ]?\s*(.*)$", &m)
            continue
        dir := StrLower(m[1]), val := Trim(m[2], " `t")
        val := StrReplace(StrReplace(StrReplace(val, "%A_ScriptName%", sName), "%A_ScriptDir%", sDir), "%A_YYYY%", FormatTime(, "yyyy"))
        rel(p) => (p := Trim(p, " `t`"'"), (p != "" && !RegExMatch(p, "^[a-zA-Z]:\\|^\\\\")) ? sDir "\" p : p)
        n++
        switch dir {
            case "setname", "setproductname":            fill("product", val)
            case "setdescription", "setfiledescription": fill("filedesc", val)
            case "setcompanyname":                       fill("company", val)
            case "setcopyright", "setlegalcopyright":    fill("copyright", val)
            case "setversion", "setfileversion", "setproductversion": fill("fileversion", val)
            case "setmainicon":                          fill("icon_main", rel(val))
            case "exename":                              fill("output", rel(val))
            case "addresource":
                parts := StrSplit(val, ",", " `t")
                file := rel(parts[1]), rn := parts.Length >= 2 ? parts[2] : ""
                if (rn = "") {
                    SplitPath(parts[1], &fn)
                    rn := StrUpper(fn)
                }
                dup := false
                Loop RLV.GetCount()
                    if (RLV.GetText(A_Index, 1) = rn)
                        dup := true
                if (!dup && FileExist(file))
                    RLV.Add(, rn, file, "No", "No"), addedRes++
            default:
                n--
        }
    }
    Touch()
    if n {
        msg := "Applied " n " directive(s)"
        if addedRes
            msg .= ", added " addedRes " resource(s)"
    } else
        msg := "No Ahk2Exe directives found"
    G["DirStatus"].Value := msg
    SetStatus(msg)
    if (!quiet && n)
        MsgBox(msg ".`nCheck the Metadata / Icons / Resources tabs.", "AHK2BC", "Iconi")
}

SetStatus(t) => SB.SetText("  " t)

CheckEnv() {
    git := Eng.FindGit(G["override_git"].Value)
    GitStat.Text := git != "" ? "OK" : "not found - will download source zip instead of cloning"
    msb := Eng.FindMSBuild(G["override_msvc"].Value)
    MsvcStat.Text := (msb != "" && FileExist(msb)) ? "OK  (" msb ")" : "NOT FOUND - install VS Build Tools + C++ workload"
    icu := FileExist(A_WinDir "\System32\icu.dll")
    IcuStat.Text := icu ? "icu.dll present (Windows RegEx backend available)" : "icu.dll missing (needs Windows 10 1903+)"
}

OnResize(gui, mm, w, h) {
    if (mm = -1)
        return
    LogBox.Move(, , w - 24, h - 556 - 26)
    LogBox.GetPos(, &ly)
}

RunSelfTest() {
    G.Show("w987 h732")   ; visible so an external screenshot can capture it
    out := "profiles: " JoinCsv(Store.List()) "`n"
    for n in Store.List() {
        SelectProfile(n)
        out .= Format("{:-26} kind={} arch={} opt={} crt={} regex={} removed=[{}]`n"
            , n, CurMode(), (G["plat_x64"].Value ? "x64" : "") (G["plat_x86"].Value ? "+x86" : "")
            , (DdOpt.Value=2?"speed":"size"), ["os","static","dll"][DdCrt.Value>3?1:DdCrt.Value], (DdRegex.Value=2?"win":"pcre"), JoinCsv(RemovedFeatures()))
    }
    out .= "feature total line: " FTotal.Value "`n"
    SelectProfile("Compile: script")
    out .= "compile mode button: " BtnGo.Text "  target_exe_enabled=" G["target_exe"].Enabled "`n"
    SelectProfile("Engine: no COM/debug")
    Tabs.Value := 1   ; show Build tab for the screenshot
    out .= "final button: " BtnGo.Text " exec=" DdExec.Value " minwin=" DdMinWin.Value "`n"
    SelfOut(out)
    SetTimer(() => ExitApp(), -12000)
}

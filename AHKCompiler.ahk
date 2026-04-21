#Requires AutoHotkey v2.0
#SingleInstance Force

; -----------------------------------------------------------------------------
; AHKCompiler - Advanced Native AutoHotkey v2 Compiler
; -----------------------------------------------------------------------------

Global AppVersion := "0.92"
Global BuildDir := A_ScriptDir "\AHKCompiler_build"
Global AhkSrcDir := BuildDir "\AutoHotkey_L"
Global PresetFile := BuildDir "\AHKCompiler_presets.ini"
Global IsHeadless := false

Global SIMULATE_NO_GIT := false
Global SIMULATE_NO_MSVC := false

Global OVERRIDE_MSBUILD_PATH := "" ; e.g., "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
Global OVERRIDE_GIT_PATH := ""     ; e.g., "C:\Program Files\Git\cmd\git.exe"

Loop A_Args.Length {
    if (A_Args[A_Index] = "/build" && A_Index < A_Args.Length) {
        IsHeadless := true
        HeadlessBuild(A_Args[A_Index + 1])
        ExitApp(0)
    }
}

; Initialize GUI
MainGui := Gui("-Resize +MinSize700x630", "AHKCompiler v" AppVersion)
MainGui.SetFont("s9", "Segoe UI")
MainGui.BackColor := "White"

; Tabs
Tabs := MainGui.Add("Tab3", "x10 y10 w680 h310", ["Main Config", "Function Stripping", "Metadata", "Icons", "Resources", "Status"])

; --- Tab 1: Main Config ---
Tabs.UseTab(1)
MainGui.Add("Text", "x25 y45 w100", "Target Script:")
MainGui.Add("Edit", "x125 y40 w450 vTargetScript", "")
MainGui.Add("Button", "x585 y39 w80", "Browse").OnEvent("Click", SelectTargetScript)

MainGui.Add("Text", "x25 y85 w100", "Custom Output:")
MainGui.Add("Edit", "x125 y80 w450 vCustomOutput", "")
MainGui.Add("Button", "x585 y79 w80", "Browse").OnEvent("Click", SelectCustomOutput)

MainGui.Add("Text", "x25 y125 w100", "Repo URL:")
MainGui.Add("Edit", "x125 y120 w350 vRepoUrl", "https://github.com/Lexikos/AutoHotkey_L.git")

MainGui.Add("Text", "x510 y125 w60", "Branch:")
MainGui.Add("Edit", "x565 y120 w100 vBranch", "v2.0")

MainGui.Add("Text", "x25 y165 w100", "Architecture:")
MainGui.Add("DropDownList", "x125 y160 w100 vArch Choose1", ["x64", "x86"])

MainGui.Add("Text", "x25 y205 w100", "Compression:")
MainGui.Add("DropDownList", "x125 y200 w100 vCompress Choose5", ["none", "xpress4k", "xpress8k", "xpress16k", "lzx"])
MainGui.Add("Text", "x235 y205 cGray", "(NTFS Native Compression -- aka 'Disk on space')")

MainGui.Add("Text", "x25 y245 w100", "Optimization:")
MainGui.Add("DropDownList", "x125 y240 w130 vOptLevel Choose2", ["Minimize Size", "Maximize Speed"])
MainGui.Add("DropDownList", "x265 y240 w160 vOptRuntime Choose2", ["Dynamic CRT (Smaller)", "Static CRT (Standalone)"])
MainGui.Add("Checkbox", "x440 y245 vOptLTCG Checked", "LTCG")
MainGui.Add("Checkbox", "x510 y245 vOptStringPool Checked", "String Pooling")

MainGui.Add("Checkbox", "x25 y285 vShowMSBuild", "Show Live MSBuild Output")

; --- Tab 2: Metadata ---
Tabs.UseTab(3)
MainGui.Add("Text", "x25 y45 w100", "Company:")
MainGui.Add("Edit", "x125 y40 w200 vCompany", "My Custom Company")

MainGui.Add("Text", "x350 y45 w80", "Product:")
MainGui.Add("Edit", "x425 y40 w200 vProduct", "My Custom App")

MainGui.Add("Text", "x25 y85 w100", "Description:")
MainGui.Add("Edit", "x125 y80 w200 vFileDesc", "My Custom Application")

MainGui.Add("Text", "x350 y85 w80", "Version:")
MainGui.Add("Edit", "x425 y80 w200 vVersion", "1.0.0.0")

MainGui.Add("Text", "x25 y125 w100", "Copyright:")
MainGui.Add("Edit", "x125 y120 w200 vCopyright", "(c) 2026 My Custom Company")

; --- Tab 3: Obfuscation ---
Tabs.UseTab(2)
MainGui.Add("GroupBox", "x20 y40 w660 h65", "General Obfuscation")
MainGui.Add("Checkbox", "x30 y55 vDelayLoad Checked", "Delay Load OS Imports (Clean IAT)")
MainGui.Add("Checkbox", "x320 y55 vRemoveStrings Checked", "Scrub AHK Signature Strings")
MainGui.Add("Checkbox", "x30 y78 vEncryptPayload", "Encrypt Target Script Payload (RC4)")
MainGui.Add("Checkbox", "x320 y78 vCompressPayload", "Compress Target Script Payload (LZNT1)")
MainGui.Add("Checkbox", "x520 y55 vInjectHooks Checked", "Inject Win32 Hooks")

MainGui.Add("GroupBox", "x20 y110 w230 h190", "1. Strict AHK Strip")
MainGui.Add("Text", "x30 y130 w210 cGray", "Removes functions from scripts:")
MainGui.Add("Checkbox", "x30 y150 w190 vStripProcess", "Process (e.g. ProcessExist)")
MainGui.Add("Checkbox", "x30 y175 vStripRun", "Run (e.g. RunWait)")
MainGui.Add("Checkbox", "x30 y200 vStripDllCall", "DllCall (e.g. DllCall)")
MainGui.Add("Checkbox", "x30 y225 w190 vStripRegistry", "Registry (e.g. RegWrite)")
MainGui.Add("Checkbox", "x30 y250 vStripNetwork", "Network (e.g. Download)")
MainGui.Add("Checkbox", "x30 y275 vCleanScript Checked", "Auto-Clean (Remove Comments)")

MainGui.Add("GroupBox", "x260 y110 w420 h165", "2. Deep Win32 API Neuter (Legacy - Use Win32 Hooks)")
MainGui.Add("Checkbox", "x275 y130 w240 vStripDangerous", "Enable Win32 Neutering (Breaks scripts!)").OnEvent("Click", ToggleNeuterUI)
MainGui.Add("Checkbox", "x525 y130 w150 vDebugMode", "Inject Debug Alerts")

MainGui.Add("Text", "x275 y155 cGray", "Hijack specific process APIs with physical C++ macros:")
MainGui.Add("Edit", "x275 y170 w390 h50 vNeuterProcess Multi", "OpenProcess, VirtualAllocEx, VirtualProtectEx, WriteProcessMemory, ReadProcessMemory, CreateToolhelp32Snapshot, Process32FirstW, Process32NextW")

MainGui.Add("Text", "x275 y225 cGray", "Hijack specific execution APIs with physical C++ macros:")
MainGui.Add("Edit", "x275 y240 w390 h25 vNeuterRun Multi", "ShellExecuteExW")

; --- Tab 4: Icons ---
Tabs.UseTab(4)
CreateIconRow(45, "Main Icon:", "IconMain")
CreateIconRow(85, "Suspend Icon:", "IconSuspend")
CreateIconRow(125, "Pause Icon:", "IconPause")
CreateIconRow(165, "Pause/Suspend:", "IconPauseSuspend")
CreateIconRow(205, "Filetype Icon:", "IconFiletype")

CreateIconRow(y, label, varName) {
    MainGui.Add("Text", "x25 y" y + 5 " w90", label)
    MainGui.Add("Edit", "x120 y" y " w450 v" varName, "")
    MainGui.Add("Button", "x580 y" y - 1 " w80", "Browse").OnEvent("Click", (*) => SelectIcon(varName))
}

; --- Tab 5: Resources ---
Tabs.UseTab(5)
MainGui.Add("Text", "x25 y45 w100", "Resource Name:")
MainGui.Add("Edit", "x125 y40 w150 vResName", "CUSTOM_DATA")
MainGui.Add("Text", "x285 y45 w60", "File Path:")
MainGui.Add("Edit", "x345 y40 w220 vResPath", "")
MainGui.Add("Button", "x575 y39 w60", "Browse").OnEvent("Click", SelectResourceFile)
MainGui.Add("Button", "x640 y39 w40", "Add").OnEvent("Click", AddResource)

MainGui.Add("Checkbox", "x125 y70 vResEncrypt", "Encrypt")
MainGui.Add("Checkbox", "x200 y70 vResCompress", "Compress")

Global ResList := MainGui.Add("ListView", "x25 y90 w655 h170 +Grid", ["Resource Name", "File Path", "Encrypt", "Compress"])
ResList.ModifyCol(1, 120)
ResList.ModifyCol(2, 380)
ResList.ModifyCol(3, 60)
ResList.ModifyCol(4, 75)
MainGui.Add("Button", "x25 y265 w120", "Remove Selected").OnEvent("Click", RemoveResource)
MainGui.Add("Button", "x155 y265 w100", "Clear All").OnEvent("Click", ClearResources)

; --- Tab 6: Status / Debug ---
Tabs.UseTab(6)

MainGui.Add("Text", "x25 y45 w120", "Git Dependency:")
Global uiGitStatus := MainGui.Add("Text", "x150 y45 w400", "Checking...")

MainGui.Add("Text", "x25 y75 w120", "MSVC Build Tools:")
Global uiMsvcStatus := MainGui.Add("Text", "x150 y75 w400", "Checking...")

MainGui.Add("GroupBox", "x20 y105 w640 h75", "Environment Path Overrides (Optional)")
MainGui.Add("Text", "x30 y128 w120", "Override git.exe:")
MainGui.Add("Edit", "x140 y123 w440 vOverrideGit", "")
MainGui.Add("Button", "x590 y122 w60", "Browse").OnEvent("Click", SelectGitOverride)

MainGui.Add("Text", "x30 y153 w120", "Override MSBuild:")
MainGui.Add("Edit", "x140 y148 w440 vOverrideMsvc", "")
MainGui.Add("Button", "x590 y147 w60", "Browse").OnEvent("Click", SelectMsvcOverride)

MainGui.Add("GroupBox", "x20 y195 w420 h75", "Developer / Testing Options")
MainGui.Add("Checkbox", "x30 y215 vSimNoGit " (SIMULATE_NO_GIT ? "Checked" : ""), "Simulate Git Not Installed...")
MainGui.Add("Checkbox", "x30 y240 vSimNoMSVC " (SIMULATE_NO_MSVC ? "Checked" : ""), "Simulate MSVC Not Installed...")

MainGui.Add("Button", "x460 y210 w200 h40", "Refresh Environment Status").OnEvent("Click", (*) => CheckEnvironmentStatusUi())

; --- Footer ---
Tabs.UseTab()
MainGui.Add("Text", "x10 y335 w50", "Preset:")
MainGui.Add("ComboBox", "x60 y330 w150 vPresetName", GetPresets())
MainGui.Add("Button", "x220 y329 w60", "Load").OnEvent("Click", LoadPreset)
MainGui.Add("Button", "x290 y329 w60", "Save").OnEvent("Click", SavePreset)
MainGui.Add("Checkbox", "x365 y332 w320 vAutoSaveConfig Checked", "Auto-Save / Auto-Load script config alongside script")

CompileBtn := MainGui.Add("Button", "x10 y360 w680 h40 Default", "COMPILE EXECUTABLE")
CompileBtn.OnEvent("Click", StartCompilation)
MainGui.SetFont("s8", "Consolas")
LogOutput := MainGui.Add("Edit", "x10 y410 w680 h180 ReadOnly vLogOutput -Wrap", "")

CheckEnvironmentStatusUi()
ToggleNeuterUI()

try
    CheckEnv({ SimNoMSVC: SIMULATE_NO_MSVC })

MainGui.Show()

; -----------------------------------------------------------------------------
; ToolTip Helper Logic
; -----------------------------------------------------------------------------
Global ToolTipStrings := Map()

AddToolTip(CtrlName, text) {
    try ToolTipStrings[MainGui[CtrlName].Hwnd] := text
}

OnMessage(0x0200, WM_MOUSEMOVE)
WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    static PrevHwnd := 0
    if (hwnd != PrevHwnd) {
        PrevHwnd := hwnd
        if ToolTipStrings.Has(hwnd) {
            ToolTip(ToolTipStrings[hwnd])
            SetTimer(() => ToolTip(), -6000)
        } else {
            ToolTip()
        }
    }
}

AddToolTip("Compress", "Applies advanced NTFS compression flags onto the binary during the final build step.`nOperates seamlessly at the filesystem level. Achieves up to 60% compression WITHOUT triggering Antiviruses like UPX packers do.")

AddToolTip("OptLevel", "Minimize Size: Applies /O1 optimization to strip all padding and enforce a minimal byte footprint.`nMaximize Speed: Applies /O2 optimization enabling loop unrolling and inline behavior for maximum raw speed.")
AddToolTip("OptRuntime", "Dynamic CRT: Relies on Windows system DLLs (vcruntime140) to execute. Creates a heavily smaller EXE.`nStatic CRT: Bakes the Microsoft C++ runtime inside the EXE. Larger size, but guarantees standalone execution.")
AddToolTip("OptLTCG", "Link-Time Code Generation (LTCG). Analyzes the entire application at the final compilation stage.`nAggressively removes unused code resulting in massive size reductions.")
AddToolTip("OptStringPool", "String Pooling. Forces all identical string literals scattered across the AutoHotkey engine to fold`ninto a single shared memory block. Free size reduction.")

AddToolTip("DelayLoad", "Obfuscates the executable's Import Address Table (IAT) by deferring all Win32 API DLL imports until runtime.`nEliminates ~300 static imports. Defeats static analysis. Note: Adds ~30KB structural data size.")
AddToolTip("RemoveStrings", "Deep scrubs known AutoHotkey plaintext strings out of the C++ engine (e.g. error messages and URLs).`nDestroys basic string-matching AV detection rules.")
AddToolTip("EncryptPayload", "Super lightweight RC4 payload encryption. Defeats string dumpers by encrypting the embedded AHK script.`nDecrypted into RAM during runtime.")
AddToolTip("CompressPayload", "Lightweight NTFS payload compression wrapper (LZNT1 Non-UPX) that compresses the embedded script.`nDecompressed into RAM during runtime.")
AddToolTip("InjectHooks", "Injects dynamic wrappers for Windows APIs to reduce binary size and clean up IAT imports.")
AddToolTip("StripDangerous", "Activates BOTH AHK Feature Stripping (left) and C++ Win32 API Neutering (right).`nThis handles everything below this toggle simultaneously.")
AddToolTip("CleanScript", "Strips all AHK comments, empty lines, and indentation formatting before compiling.`nReduces script payload size without altering execution logic.")
AddToolTip("DebugMode", "When a native Win32 API specified in the right TextBoxes is intercepted by Neutering,`nit injects a MessageBox popup explicitly alerting you to which internal C++ call failed.")

AddToolTip("StripProcess", "AHK LEVEL: Unregisters Process commands (ProcessExist, ProcessWait,...).`nYour script will treat these as unknown functions. Extremely safe, never breaks native C++.")
AddToolTip("StripRun", "AHK LEVEL: Unregisters the 'Run' and 'RunWait' commands entirely.`nYour script can no longer call them directly.")
AddToolTip("StripDllCall", "AHK LEVEL: Unregisters the 'DllCall' language command altogether.")
AddToolTip("StripRegistry", "AHK LEVEL: Unregisters RegWrite, RegRead, RegDelete etc. from the language.")
AddToolTip("StripNetwork", "AHK LEVEL: Unregisters the built-in 'Download' command from AHK.")

AddToolTip("NeuterProcess", "C++ LEVEL: Intercepts these Win32 functions globally inside the AutoHotkey C++ engine.`nIf AHK tries to use OpenProcess internally (e.g. to fetch window info), it forcefully returns NULL.`nHighly effective for EVADING AV process injection flags, but CAN break standard script behaviors!")
AddToolTip("NeuterRun", "C++ LEVEL: Intercepts ShellExecuteExW globally inside the engine.`nGuarantees the application cannot launch sub-processes entirely safely.")

; -----------------------------------------------------------------------------
; GUI Events & Presets
; -----------------------------------------------------------------------------

SelectTargetScript(*) {
    selected := FileSelect(3, , "Select Target AutoHotkey Script", "Scripts (*.ahk)")
    if (selected != "") {
        MainGui["TargetScript"].Value := selected
        cfgPath := selected ".ahkcompiler.ini"
        if FileExist(cfgPath) {
            LoadPresetFromFile(cfgPath, "Config")
        }
    }
}

SelectCustomOutput(*) {
    selected := FileSelect("S16", , "Select Target Executable", "Executables (*.exe)")
    if (selected != "") {
        if (SubStr(selected, -4) != ".exe")
            selected .= ".exe"
        MainGui["CustomOutput"].Value := selected
    }
}

SelectIcon(varName) {
    selected := FileSelect(3, , "Select Custom Icon", "Icons (*.ico)")
    if (selected != "")
        MainGui[varName].Value := selected
}

SelectResourceFile(*) {
    selected := FileSelect(3, , "Select Resource File", "All Files (*.*)")
    if (selected != "")
        MainGui["ResPath"].Value := selected
}

AddResource(*) {
    rName := Trim(MainGui["ResName"].Value)
    rPath := Trim(MainGui["ResPath"].Value)
    rEnc := MainGui["ResEncrypt"].Value
    rCmp := MainGui["ResCompress"].Value
    if (rName = "" || rPath = "") {
        MsgBox("Both Resource Name and File Path are required.", "Error")
        return
    }
    ResList.Add("", rName, rPath, (rEnc) ? "Yes" : "No", (rCmp) ? "Yes" : "No")
    MainGui["ResName"].Value := "CUSTOM_DATA"
    MainGui["ResPath"].Value := ""
    MainGui["ResEncrypt"].Value := 0
    MainGui["ResCompress"].Value := 0
}

SelectGitOverride(*) {
    sel := FileSelect(3, "", "Select git.exe", "Executable (*.exe)")
    if sel
        MainGui["OverrideGit"].Value := sel
    CheckEnvironmentStatusUi()
}

SelectMsvcOverride(*) {
    sel := FileSelect(3, "", "Select MSBuild.exe", "Executable (*.exe)")
    if sel
        MainGui["OverrideMsvc"].Value := sel
    CheckEnvironmentStatusUi()
}

RemoveResource(*) {
    row := ResList.GetNext(0)
    if row
        ResList.Delete(row)
}

ClearResources(*) {
    ResList.Delete()
}

AppendLog(msg) {
    if (IsHeadless) {
        try FileAppend(msg "`n", "*")
        return
    }
    txtLen := SendMessage(0x000E, 0, 0, LogOutput.Hwnd) ; WM_GETTEXTLENGTH
    SendMessage(0x00B1, txtLen, txtLen, LogOutput.Hwnd) ; EM_SETSEL
    SendMessage(0x00C2, 0, StrPtr(msg), LogOutput.Hwnd) ; EM_REPLACESEL
    SendMessage(0x0115, 7, 0, LogOutput.Hwnd) ; WM_VSCROLL -> SB_BOTTOM
}

LogMsg(msg) {
    AppendLog(msg "`r`n")
}

LogMsgRaw(msg) {
    AppendLog(msg)
}

GetPresets() {
    if !FileExist(PresetFile)
        return []
    sects := IniRead(PresetFile)
    return StrSplit(sects, "`n")
}

LoadPreset(*) {
    saved := MainGui.Submit(false)
    pName := saved.PresetName
    if (pName = "" || !FileExist(PresetFile))
        return
    LoadPresetFromFile(PresetFile, pName)
}

LoadPresetFromFile(iniFile, pName) {
    try {
        if (iniFile = PresetFile)
            MainGui["TargetScript"].Value := IniRead(iniFile, pName, "TargetScript", "")
        MainGui["CustomOutput"].Value := IniRead(iniFile, pName, "CustomOutput", "")
        MainGui["RepoUrl"].Value := IniRead(iniFile, pName, "RepoUrl", "https://github.com/Lexikos/AutoHotkey_L.git")
        MainGui["Branch"].Value := IniRead(iniFile, pName, "Branch", "v2.0")
        MainGui["Arch"].Text := IniRead(iniFile, pName, "Arch", "x64")
        MainGui["Compress"].Text := IniRead(iniFile, pName, "Compress", "none")
        MainGui["OptLevel"].Text := IniRead(iniFile, pName, "OptLevel", "Minimize Size")
        MainGui["OptRuntime"].Text := IniRead(iniFile, pName, "OptRuntime", "Dynamic CRT (Smaller)")
        MainGui["OptLTCG"].Value := Integer(IniRead(iniFile, pName, "OptLTCG", 1))
        MainGui["OptStringPool"].Value := Integer(IniRead(iniFile, pName, "OptStringPool", 1))
        MainGui["ShowMSBuild"].Value := Integer(IniRead(iniFile, pName, "ShowMSBuild", 0))

        MainGui["Company"].Value := IniRead(iniFile, pName, "Company", "My Custom Company")
        MainGui["Product"].Value := IniRead(iniFile, pName, "Product", "My Custom App")
        MainGui["FileDesc"].Value := IniRead(iniFile, pName, "FileDesc", "My Custom Application")
        MainGui["Version"].Value := IniRead(iniFile, pName, "Version", "1.0.0.0")
        MainGui["Copyright"].Value := IniRead(iniFile, pName, "Copyright", "(c) 2026 My Custom Company")

        MainGui["DelayLoad"].Value := Integer(IniRead(iniFile, pName, "DelayLoad", 0))
        MainGui["RemoveStrings"].Value := Integer(IniRead(iniFile, pName, "RemoveStrings", 0))
        MainGui["EncryptPayload"].Value := Integer(IniRead(iniFile, pName, "EncryptPayload", 0))
        MainGui["CompressPayload"].Value := Integer(IniRead(iniFile, pName, "CompressPayload", 0))
        MainGui["InjectHooks"].Value := Integer(IniRead(iniFile, pName, "InjectHooks", 0))
        MainGui["StripDangerous"].Value := Integer(IniRead(iniFile, pName, "StripDangerous", 1))
        MainGui["DebugMode"].Value := Integer(IniRead(iniFile, pName, "DebugMode", 0))

        MainGui["StripProcess"].Value := Integer(IniRead(iniFile, pName, "StripProcess", 1))
        MainGui["StripRun"].Value := Integer(IniRead(iniFile, pName, "StripRun", 1))
        MainGui["StripDllCall"].Value := Integer(IniRead(iniFile, pName, "StripDllCall", 1))
        MainGui["StripRegistry"].Value := Integer(IniRead(iniFile, pName, "StripRegistry", 1))
        MainGui["StripNetwork"].Value := Integer(IniRead(iniFile, pName, "StripNetwork", 1))
        MainGui["CleanScript"].Value := Integer(IniRead(iniFile, pName, "CleanScript", 1))

        MainGui["NeuterProcess"].Value := IniRead(iniFile, pName, "NeuterProcess", "OpenProcess, VirtualAllocEx, VirtualProtectEx, WriteProcessMemory, ReadProcessMemory, CreateToolhelp32Snapshot, Process32FirstW, Process32NextW")
        MainGui["NeuterRun"].Value := IniRead(iniFile, pName, "NeuterRun", "ShellExecuteExW")

        MainGui["IconMain"].Value := IniRead(iniFile, pName, "IconMain", "")
        MainGui["IconSuspend"].Value := IniRead(iniFile, pName, "IconSuspend", "")
        MainGui["IconPause"].Value := IniRead(iniFile, pName, "IconPause", "")
        MainGui["IconPauseSuspend"].Value := IniRead(iniFile, pName, "IconPauseSuspend", "")
        MainGui["IconFiletype"].Value := IniRead(iniFile, pName, "IconFiletype", "")

        ResList.Delete()
        rcount := Integer(IniRead(iniFile, pName, "ResourceCount", 0))
        Loop rcount {
            rName := IniRead(iniFile, pName, "ResName" A_Index, "")
            rPath := IniRead(iniFile, pName, "ResPath" A_Index, "")
            rEnc := IniRead(iniFile, pName, "ResEncrypt" A_Index, "0")
            rCmp := IniRead(iniFile, pName, "ResCompress" A_Index, "0")
            if (rName != "" && rPath != "")
                ResList.Add("", rName, rPath, (rEnc) ? "Yes" : "No", (rCmp) ? "Yes" : "No")
        }

        MainGui["OverrideGit"].Value := IniRead(iniFile, pName, "OverrideGit", "")
        MainGui["OverrideMsvc"].Value := IniRead(iniFile, pName, "OverrideMsvc", "")

        LogMsg("[*] Loaded Configuration: " pName " (from " iniFile ")")
        ToggleNeuterUI()
        CheckEnvironmentStatusUi()
    } catch {
        LogMsg("[!] Failed to load configuration.")
    }
}

ToggleNeuterUI(*) {
    isEnabled := MainGui["StripDangerous"].Value
    MainGui["DebugMode"].Enabled := isEnabled
    MainGui["NeuterProcess"].Enabled := isEnabled
    MainGui["NeuterRun"].Enabled := isEnabled
}

SavePreset(*) {
    saved := MainGui.Submit(false)
    pName := saved.PresetName
    if (pName = "") {
        MsgBox("Please enter a preset name.", "Error", "Iconx")
        return
    }

    if !DirExist(BuildDir)
        DirCreate(BuildDir)

    SaveConfigToIni(PresetFile, pName, saved)

    MainGui["PresetName"].Delete()
    MainGui["PresetName"].Add(GetPresets())
    MainGui["PresetName"].Text := pName

    LogMsg("[*] Saved global preset: " pName)
}

SaveConfigToIni(iniPath, pName, saved) {
    IniDelete(iniPath, pName) ; Clear old keys

    if (iniPath = PresetFile)
        IniWrite(saved.TargetScript, iniPath, pName, "TargetScript")

    IniWrite(saved.CustomOutput, iniPath, pName, "CustomOutput")
    IniWrite(saved.RepoUrl, iniPath, pName, "RepoUrl")
    IniWrite(saved.Branch, iniPath, pName, "Branch")
    IniWrite(saved.Arch, iniPath, pName, "Arch")
    IniWrite(saved.Compress, iniPath, pName, "Compress")
    IniWrite(saved.OptLevel, iniPath, pName, "OptLevel")
    IniWrite(saved.OptRuntime, iniPath, pName, "OptRuntime")
    IniWrite(saved.OptLTCG, iniPath, pName, "OptLTCG")
    IniWrite(saved.OptStringPool, iniPath, pName, "OptStringPool")
    IniWrite(saved.ShowMSBuild, iniPath, pName, "ShowMSBuild")

    IniWrite(saved.Company, iniPath, pName, "Company")
    IniWrite(saved.Product, iniPath, pName, "Product")
    IniWrite(saved.FileDesc, iniPath, pName, "FileDesc")
    IniWrite(saved.Version, iniPath, pName, "Version")
    IniWrite(saved.Copyright, iniPath, pName, "Copyright")

    IniWrite(saved.DelayLoad, iniPath, pName, "DelayLoad")
    IniWrite(saved.RemoveStrings, iniPath, pName, "RemoveStrings")
    IniWrite(saved.EncryptPayload, iniPath, pName, "EncryptPayload")
    IniWrite(saved.CompressPayload, iniPath, pName, "CompressPayload")
    IniWrite(saved.InjectHooks, iniPath, pName, "InjectHooks")
    IniWrite(saved.StripDangerous, iniPath, pName, "StripDangerous")
    IniWrite(saved.DebugMode, iniPath, pName, "DebugMode")

    IniWrite(saved.StripProcess, iniPath, pName, "StripProcess")
    IniWrite(saved.StripRun, iniPath, pName, "StripRun")
    IniWrite(saved.StripDllCall, iniPath, pName, "StripDllCall")
    IniWrite(saved.StripRegistry, iniPath, pName, "StripRegistry")
    IniWrite(saved.StripNetwork, iniPath, pName, "StripNetwork")
    IniWrite(saved.CleanScript, iniPath, pName, "CleanScript")

    IniWrite(StrReplace(saved.NeuterProcess, "`n", ", "), iniPath, pName, "NeuterProcess")
    IniWrite(StrReplace(saved.NeuterRun, "`n", ", "), iniPath, pName, "NeuterRun")

    IniWrite(saved.IconMain, iniPath, pName, "IconMain")
    IniWrite(saved.IconSuspend, iniPath, pName, "IconSuspend")
    IniWrite(saved.IconPause, iniPath, pName, "IconPause")
    IniWrite(saved.IconPauseSuspend, iniPath, pName, "IconPauseSuspend")
    IniWrite(saved.IconFiletype, iniPath, pName, "IconFiletype")

    IniWrite(saved.OverrideGit, iniPath, pName, "OverrideGit")
    IniWrite(saved.OverrideMsvc, iniPath, pName, "OverrideMsvc")

    rcount := ResList.GetCount()
    IniWrite(rcount, iniPath, pName, "ResourceCount")
    Loop rcount {
        IniWrite(ResList.GetText(A_Index, 1), iniPath, pName, "ResName" A_Index)
        IniWrite(ResList.GetText(A_Index, 2), iniPath, pName, "ResPath" A_Index)
        IniWrite((ResList.GetText(A_Index, 3) = "Yes") ? 1 : 0, iniPath, pName, "ResEncrypt" A_Index)
        IniWrite((ResList.GetText(A_Index, 4) = "Yes") ? 1 : 0, iniPath, pName, "ResCompress" A_Index)
    }
}

StartCompilation(*) {
    saved := MainGui.Submit(false)
    if (saved.TargetScript = "" || !FileExist(saved.TargetScript)) {
        MsgBox("Please select a valid target script.", "Error", "Iconx")
        return
    }

    resArray := []
    Loop ResList.GetCount() {
        resArray.Push({
            Name: ResList.GetText(A_Index, 1),
            Path: ResList.GetText(A_Index, 2),
            Encrypt: (ResList.GetText(A_Index, 3) = "Yes") ? true : false,
            Compress: (ResList.GetText(A_Index, 4) = "Yes") ? true : false
        })
    }
    saved.Resources := resArray

    CompileBtn.Enabled := false
    LogOutput.Value := ""

    if (saved.AutoSaveConfig) {
        cfgPath := saved.TargetScript ".ahkcompiler.ini"
        SaveConfigToIni(cfgPath, "Config", saved)
        LogMsg("[*] Saved localized configuration alongside target script.")
    }

    ; Run compilation on a separate thread/timer to keep GUI responsive
    SetTimer(() => CompileProcess(saved), -1)
}

; -----------------------------------------------------------------------------
; Core Compiler Logic
; -----------------------------------------------------------------------------

CompileProcess(cfg) {
    try {
        LogMsg("[*] Starting Native AHKv2 Compilation for: " cfg.TargetScript)

        cfg.SimNoGit := IsSet(MainGui) ? MainGui["SimNoGit"].Value : 0
        cfg.SimNoMSVC := IsSet(MainGui) ? MainGui["SimNoMSVC"].Value : 0

        totalTimeStart := A_TickCount

        t := A_TickCount
        CheckEnv(cfg)
        tCheckEnv := A_TickCount - t

        t := A_TickCount
        CloneSource(cfg)
        tCloneSource := A_TickCount - t

        t := A_TickCount
        OptimizeCompilerFlags(cfg)
        tOptimize := A_TickCount - t

        t := A_TickCount
        EmbedScript(cfg)
        tEmbed := A_TickCount - t

        t := A_TickCount
        RunCompile(cfg)
        tCompile := A_TickCount - t

        t := A_TickCount
        CleanBuildArtifacts()
        tClean := A_TickCount - t

        totalTime := A_TickCount - totalTimeStart

        LogMsg("==================================================")
        LogMsg("[-] BUILD TIMING BREAKDOWN:")
        LogMsg("    Environment Check : " tCheckEnv " ms")
        LogMsg("    Clone Source      : " tCloneSource " ms")
        LogMsg("    Optimize Flags    : " tOptimize " ms")
        LogMsg("    Embed Script      : " tEmbed " ms")
        LogMsg("    Run MSVC Compile  : " tCompile " ms")
        LogMsg("    Clean Artifacts   : " tClean " ms")
        LogMsg("==================================================")
        LogMsg("[+] Compilation Completed Successfully in " totalTime " ms (" Round(totalTime / 1000, 2) " s)")

    } catch Error as e {
        LogMsg("[!] Fatal Error: " e.Message)
    }
    if !IsHeadless
        CompileBtn.Enabled := true
}

CheckEnv(cfg) {
    if !DirExist(BuildDir)
        DirCreate(BuildDir)

    ovrMsvc := cfg.HasOwnProp("OverrideMsvc") ? cfg.OverrideMsvc : ""
    hasMsvc := false
    if (ovrMsvc != "" && FileExist(ovrMsvc)) {
        hasMsvc := true
    } else {
        pathVsWhere := A_ProgramFiles "\Microsoft Visual Studio\Installer\vswhere.exe"
        pathVsWhere32 := A_ProgramFiles " (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
        if FileExist(pathVsWhere) || FileExist(pathVsWhere32) {
            vswhere := FileExist(pathVsWhere) ? pathVsWhere : pathVsWhere32
            outPath := A_Temp "\vswhere_chk2.txt"
            cmd := "`"" vswhere "`" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe"
            RunWait(A_ComSpec " /c `"" cmd " > `"" outPath "`"`"", , "Hide")
            if FileExist(outPath) {
                if InStr(FileRead(outPath), "MSBuild.exe")
                    hasMsvc := true
                FileDelete(outPath)
            }
        }
    }

    if (cfg.SimNoMSVC)
        hasMsvc := false

    if (!hasMsvc && !IsHeadless) {
        res := MsgBox("MSVC Build Tools were not found on this system.`nThey are required to compile the C++ engine.`n`n(The required package is 'Desktop development with C++')`n`nWould you like to open the download page?", "Build Tools Missing", 0x4)
        if (res == "Yes")
            Run("https://aka.ms/vs/17/release/vs_buildtools.exe")
        throw Error("Build Tools missing. Awaiting user installation.")
    } else if (!hasMsvc) {
        throw Error("MSVC Build Tools missing. Headless build failed.")
    }
}

CloneSource(cfg) {
    repoUrl := cfg.RepoUrl
    branch := cfg.Branch
    simNoGit := cfg.SimNoGit

    trackingFile := BuildDir "\.ahk_source_tracking"
    currentTracking := repoUrl "|" branch
    needsReclone := false
    pristineBackup := BuildDir "\Ahk_PristineBackup"

    ovrGit := cfg.HasOwnProp("OverrideGit") ? cfg.OverrideGit : ""
    gitExe := (ovrGit != "" && FileExist(ovrGit)) ? "`"" ovrGit "`"" : "git"
    hasGit := (RunWait(A_ComSpec " /c " gitExe " --version", , "Hide") == 0)

    if (simNoGit)
        hasGit := false

    if (!hasGit) {
        LogMsg("[*] Git is missing (or simulated). Using non-Git Zip Download fallback...")
        shouldDownload := false
        if !DirExist(pristineBackup) || (!FileExist(trackingFile) || FileRead(trackingFile) != currentTracking)
            shouldDownload := true

        if (DirExist(pristineBackup)) {
            isEmpty := true
            Loop Files, pristineBackup "\*", "DF" {
                isEmpty := false
                break
            }
            if (isEmpty)
                shouldDownload := true
        }

        if (shouldDownload) {
            cleanUrl := RegExReplace(repoUrl, "(?i)\.git/?$", "")
            zipUrl := cleanUrl "/archive/refs/heads/" branch ".zip"
            zipPath := BuildDir "\ahk_source.zip"

            LogMsg("[*] Preparing Native Download...")
            LogMsg("    -> Source: " zipUrl)
            LogMsg("    -> Target: " zipPath)

            try {
                Download(zipUrl, zipPath)
                LogMsg("[+] Download Completed Successfully! (" FileGetSize(zipPath) " bytes)")
            } catch as e {
                LogMsg("[!] Error: Native Download Failed! Check your internet or firewall. (" e.Message ")")
                throw Error("Failed to natively download ZIP source code.")
            }

            if FileExist(zipPath) {
                if DirExist(pristineBackup)
                    RunWait(A_ComSpec " /c rmdir /s /q `"" pristineBackup "`"", , "Hide")
                DirCreate(pristineBackup)

                LogMsg("[*] Unzipping to pristine cache...")
                psCmd := "Expand-Archive -Path '" zipPath "' -DestinationPath '" pristineBackup "' -Force"
                RunWait("powershell -Command `"" psCmd "`"", , "Hide")
                FileDelete(zipPath)

                Loop Files, pristineBackup "\*", "D" {
                    RunWait(A_ComSpec " /c xcopy /E /I /Y `"" A_LoopFilePath "`" `"" pristineBackup "_extract`"", , "Hide")
                    RunWait(A_ComSpec " /c rmdir /s /q `"" A_LoopFilePath "`"", , "Hide")
                }
                RunWait(A_ComSpec " /c xcopy /E /I /Y `"" pristineBackup "_extract`" `"" pristineBackup "`"", , "Hide")
                RunWait(A_ComSpec " /c rmdir /s /q `"" pristineBackup "_extract`"", , "Hide")

                FileAppend(currentTracking, trackingFile, "UTF-8")
            } else {
                throw Error("Failed to download ZIP source code.")
            }
        }

        LogMsg("[*] Restoring working directory from pristine source...")
        if DirExist(AhkSrcDir)
            RunWait(A_ComSpec " /c rmdir /s /q `"" AhkSrcDir "`"", , "Hide")

        RunWait(A_ComSpec " /c xcopy /E /I /Y `"" pristineBackup "`" `"" AhkSrcDir "`"", , "Hide")
        return
    }

    if DirExist(AhkSrcDir) {
        if !DirExist(AhkSrcDir "\.git") {
            LogMsg("[*] Found untracked source! Clearing for clean clone...")
            needsReclone := true
        } else if (!FileExist(trackingFile) || FileRead(trackingFile) != currentTracking) {
            LogMsg("[*] Source configuration changed. Clearing old build cache...")
            needsReclone := true
        }

        if (needsReclone) {
            RunWait(A_ComSpec " /c rmdir /s /q `"" AhkSrcDir "`"", , "Hide")
            Sleep(500)
        }
    }

    if !DirExist(AhkSrcDir) {
        LogMsg("[*] Cloning C++ Source Code from: " repoUrl " (Branch: " branch ")")
        exitCode := RunWait(A_ComSpec " /c " gitExe " clone --branch " branch " --depth 1 " repoUrl " `"" AhkSrcDir "`"", , "Hide")
        if (exitCode != 0)
            throw Error("Failed to clone repository.")

        if FileExist(trackingFile)
            FileDelete(trackingFile)
        FileAppend(currentTracking, trackingFile, "UTF-8")
    } else {
        LogMsg("[*] AHK v2 source already exists. Reverting to a clean pristine state...")
        RunWait(A_ComSpec " /c " gitExe " reset --hard HEAD", AhkSrcDir, "Hide")
        RunWait(A_ComSpec " /c " gitExe " clean -fdx source", AhkSrcDir, "Hide")
    }
}

ParseCsvList(str) {
    arr := []
    Loop Parse, str, "`,", " `t`r`n"
    {
        if (A_LoopField != "")
            arr.Push(A_LoopField)
    }
    return arr
}

OptimizeCompilerFlags(cfg) {
    LogMsg("[*] Applying user-selected Compiler Configurations...")

    Loop Files, AhkSrcDir "\*.vcxproj", "R" {
        filePath := A_LoopFilePath
        content := FileRead(filePath, "UTF-8")

        optTag := (cfg.OptLevel = "Minimize Size") ? "MinSpace" : "MaxSpeed"
        favorTag := (cfg.OptLevel = "Minimize Size") ? "Size" : "Speed"
        crtTag := InStr(cfg.OptRuntime, "Dynamic") ? "MultiThreadedDLL" : "MultiThreaded"

        content := RegExReplace(content, "<Optimization>.*?</Optimization>", "<Optimization>" optTag "</Optimization>")
        content := RegExReplace(content, "<FavorSizeOrSpeed>.*?</FavorSizeOrSpeed>", "<FavorSizeOrSpeed>" favorTag "</FavorSizeOrSpeed>")
        content := RegExReplace(content, "<RuntimeLibrary>.*?</RuntimeLibrary>", "<RuntimeLibrary>" crtTag "</RuntimeLibrary>")

        if (cfg.OptStringPool && !InStr(content, "<StringPooling>true</StringPooling>")) {
            content := StrReplace(content, "</ClCompile>", "  <StringPooling>true</StringPooling>`r`n      <FunctionLevelLinking>true</FunctionLevelLinking>`r`n    </ClCompile>")
        } else if (!cfg.OptStringPool) {
            content := RegExReplace(content, "\s*<StringPooling>.*?</StringPooling>", "")
            content := RegExReplace(content, "\s*<FunctionLevelLinking>.*?</FunctionLevelLinking>", "")
        }

        linkPayload := ""
        if (cfg.OptLevel = "Minimize Size" || cfg.OptLTCG) {
            linkPayload .= "  <OptimizeReferences>true</OptimizeReferences>`r`n      <EnableCOMDATFolding>true</EnableCOMDATFolding>`r`n"
        }

        if (cfg.DelayLoad) {
            delayDlls := "USER32.dll;GDI32.dll;COMCTL32.dll;ADVAPI32.dll;SHELL32.dll;OLEAUT32.dll;VERSION.dll;WININET.dll;WSOCK32.dll;WINMM.dll;PSAPI.DLL;UxTheme.dll;dwmapi.dll;ole32.dll;SHLWAPI.dll;%(DelayLoadDLLs)"
            linkPayload .= "      <DelayLoadDLLs>" delayDlls "</DelayLoadDLLs>`r`n"
        }
        linkPayload .= "    </Link>"

        content := RegExReplace(content, "\s*<OptimizeReferences>.*?</OptimizeReferences>", "")
        content := RegExReplace(content, "\s*<EnableCOMDATFolding>.*?</EnableCOMDATFolding>", "")
        content := RegExReplace(content, "\s*<DelayLoadDLLs>.*?</DelayLoadDLLs>", "")
        content := StrReplace(content, "</Link>", linkPayload)

        content := StrReplace(content, "<PrecompiledHeader Condition=`"!$(ConfigDebug)`">Use</PrecompiledHeader>", "<PrecompiledHeader>NotUsing</PrecompiledHeader>")
        content := StrReplace(content, "<PrecompiledHeader>Use</PrecompiledHeader>", "<PrecompiledHeader>NotUsing</PrecompiledHeader>")
        content := StrReplace(content, "<PrecompiledHeader>Create</PrecompiledHeader>", "<PrecompiledHeader>NotUsing</PrecompiledHeader>")

        SaveFile(filePath, content)
    }

    if (cfg.RemoveStrings) {
        LogMsg("[*] Scrubbing all raw AutoHotkey signature strings from C++ Source Code...")
        Loop Files, AhkSrcDir "\*.cpp", "R"
            ScrubFile(A_LoopFilePath)
        Loop Files, AhkSrcDir "\*.h", "R"
            ScrubFile(A_LoopFilePath)
    }

    if (cfg.HasOwnProp("InjectHooks") && cfg.InjectHooks) {
        LogMsg("[*] Injecting Win32 Hooks to clean imports...")
        hooks_h := AhkSrcDir "\source\Hooks.h"
        hooksPayload := "
        (
            #pragma once
            #include <windows.h>
            #include <winternl.h>
            #include <string>
            
            namespace Hooks {
                inline FARPROC _GetProcAddress(HMODULE hMod, const char* funcName) {
                    if (!hMod) return nullptr;
                    auto dosHeader = (PIMAGE_DOS_HEADER)hMod;
                    auto ntHeaders = (PIMAGE_NT_HEADERS)((BYTE*)hMod + dosHeader->e_lfanew);
                    auto exports = (PIMAGE_EXPORT_DIRECTORY)((BYTE*)hMod + ntHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
            
                    auto names = (PDWORD)((BYTE*)hMod + exports->AddressOfNames);
                    auto ordinals = (PWORD)((BYTE*)hMod + exports->AddressOfNameOrdinals);
                    auto functions = (PDWORD)((BYTE*)hMod + exports->AddressOfFunctions);
            
                    for (DWORD i = 0; i < exports->NumberOfNames; ++i) {
                        char* name = (char*)((BYTE*)hMod + names[i]);
                        if (strcmp(name, funcName) == 0) {
                            return (FARPROC)((BYTE*)hMod + functions[ordinals[i]]);
                        }
                    }
                    return nullptr;
                }
            
                inline HMODULE _GetModuleHandleA(const char* targetDll) {
            #ifdef _WIN64
                    auto peb = (PPEB)__readgsqword(0x60);
            #else
                    auto peb = (PPEB)__readfsdword(0x30);
            #endif
                    auto listEntry = peb->Ldr->InMemoryOrderModuleList.Flink;
                    auto endEntry = &peb->Ldr->InMemoryOrderModuleList;
            
                    std::string target = targetDll;
                    for (auto& c : target) c = tolower(c);
            
                    while (listEntry != endEntry) {
                        auto ldrEntry = CONTAINING_RECORD(listEntry, LDR_DATA_TABLE_ENTRY, InMemoryOrderLinks);
                        if (ldrEntry->FullDllName.Buffer) {
                            std::wstring dllNameW = ldrEntry->FullDllName.Buffer;
                            std::string dllName;
                            dllName.reserve(dllNameW.size());
                            for (auto wc : dllNameW) dllName += (char)wc;
                            for (auto& c : dllName) c = tolower(c);
            
                            if (dllName.find(target) != std::string::npos) {
                                return (HMODULE)ldrEntry->DllBase;
                            }
                        }
                        listEntry = listEntry->Flink;
                    }
                    return nullptr;
                }
            
                inline HMODULE _LoadLibraryA(const char* dllName) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pLoadLibraryA = (HMODULE(WINAPI*)(LPCSTR))Hooks::_GetProcAddress(hK32, "LoadLibraryA");
                    if (pLoadLibraryA) return pLoadLibraryA(dllName);
                    return nullptr;
                }
            
                inline LONG _RegOpenKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD ulOptions, REGSAM samDesired, PHKEY phkResult) {
                    HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
                    if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
                    auto pRegOpenKeyExA = (LONG(WINAPI*)(HKEY, LPCSTR, DWORD, REGSAM, PHKEY))Hooks::_GetProcAddress(hAdvapi32, "RegOpenKeyExA");
                    if (pRegOpenKeyExA) return pRegOpenKeyExA(hKey, lpSubKey, ulOptions, samDesired, phkResult);
                    return ERROR_FILE_NOT_FOUND;
                }
            
                inline LONG _RegQueryValueExA(HKEY hKey, LPCSTR lpValueName, LPDWORD lpReserved, LPDWORD lpType, LPBYTE lpData, LPDWORD lpcbData) {
                    HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
                    if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
                    auto pRegQueryValueExA = (LONG(WINAPI*)(HKEY, LPCSTR, LPDWORD, LPDWORD, LPBYTE, LPDWORD))Hooks::_GetProcAddress(hAdvapi32, "RegQueryValueExA");
                    if (pRegQueryValueExA) return pRegQueryValueExA(hKey, lpValueName, lpReserved, lpType, lpData, lpcbData);
                    return ERROR_FILE_NOT_FOUND;
                }
            
                inline LONG _RegCloseKey(HKEY hKey) {
                    HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
                    if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
                    auto pRegCloseKey = (LONG(WINAPI*)(HKEY))Hooks::_GetProcAddress(hAdvapi32, "RegCloseKey");
                    if (pRegCloseKey) return pRegCloseKey(hKey);
                    return ERROR_FILE_NOT_FOUND;
                }
            
                inline BOOL _CreateProcessA(LPCSTR lpApplicationName, LPSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCSTR lpCurrentDirectory, LPSTARTUPINFOA lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pCreateProcessA = (BOOL(WINAPI*)(LPCSTR, LPSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCSTR, LPSTARTUPINFOA, LPPROCESS_INFORMATION))Hooks::_GetProcAddress(hK32, "CreateProcessA");
                    if (pCreateProcessA) return pCreateProcessA(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
                    return FALSE;
                }
                inline BOOL _RegisterHotKey(HWND hWnd, int id, UINT fsModifiers, UINT vk) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return FALSE;
                    auto pRegisterHotKey = (BOOL(WINAPI*)(HWND, int, UINT, UINT))Hooks::_GetProcAddress(hUser32, "RegisterHotKey");
                    if (pRegisterHotKey) return pRegisterHotKey(hWnd, id, fsModifiers, vk);
                    return FALSE;
                }
            
                inline LRESULT _CallNextHookEx(HHOOK hhk, int nCode, WPARAM wParam, LPARAM lParam) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return 0;
                    auto pCallNextHookEx = (LRESULT(WINAPI*)(HHOOK, int, WPARAM, LPARAM))Hooks::_GetProcAddress(hUser32, "CallNextHookEx");
                    if (pCallNextHookEx) return pCallNextHookEx(hhk, nCode, wParam, lParam);
                    return 0;
                }
            
                inline HWND _GetForegroundWindow() {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return nullptr;
                    auto pGetForegroundWindow = (HWND(WINAPI*)())Hooks::_GetProcAddress(hUser32, "GetForegroundWindow");
                    if (pGetForegroundWindow) return pGetForegroundWindow();
                    return nullptr;
                }
            
                inline HANDLE _OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pOpenProcess = (HANDLE(WINAPI*)(DWORD, BOOL, DWORD))Hooks::_GetProcAddress(hK32, "OpenProcess");
                    if (pOpenProcess) return pOpenProcess(dwDesiredAccess, bInheritHandle, dwProcessId);
                    return nullptr;
                }
            
                inline HHOOK _SetWindowsHookExA(int idHook, HOOKPROC lpfn, HINSTANCE hmod, DWORD dwThreadId) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return NULL;
                    auto pSetWindowsHookExA = (HHOOK(WINAPI*)(int, HOOKPROC, HINSTANCE, DWORD))Hooks::_GetProcAddress(hUser32, "SetWindowsHookExA");
                    if (pSetWindowsHookExA) return pSetWindowsHookExA(idHook, lpfn, hmod, dwThreadId);
                    return NULL;
                }
            
                inline BOOL _UnhookWindowsHookEx(HHOOK hhk) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return FALSE;
                    auto pUnhookWindowsHookEx = (BOOL(WINAPI*)(HHOOK))Hooks::_GetProcAddress(hUser32, "UnhookWindowsHookEx");
                    if (pUnhookWindowsHookEx) return pUnhookWindowsHookEx(hhk);
                    return FALSE;
                }
            
                inline BOOL _OpenClipboard(HWND hWndNewOwner) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return FALSE;
                    auto pOpenClipboard = (BOOL(WINAPI*)(HWND))Hooks::_GetProcAddress(hUser32, "OpenClipboard");
                    if (pOpenClipboard) return pOpenClipboard(hWndNewOwner);
                    return FALSE;
                }
            
                inline HANDLE _SetClipboardData(UINT uFormat, HANDLE hMem) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return nullptr;
                    auto pSetClipboardData = (HANDLE(WINAPI*)(UINT, HANDLE))Hooks::_GetProcAddress(hUser32, "SetClipboardData");
                    if (pSetClipboardData) return pSetClipboardData(uFormat, hMem);
                    return nullptr;
                }
            
                inline BOOL _CloseClipboard(void) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return FALSE;
                    auto pCloseClipboard = (BOOL(WINAPI*)(void))Hooks::_GetProcAddress(hUser32, "CloseClipboard");
                    if (pCloseClipboard) return pCloseClipboard();
                    return FALSE;
                }
            
                inline HANDLE _CreateThread(LPSECURITY_ATTRIBUTES lpThreadAttributes, SIZE_T dwStackSize, LPTHREAD_START_ROUTINE lpStartAddress, LPVOID lpParameter, DWORD dwCreationFlags, LPDWORD lpThreadId) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pCreateThread = (HANDLE(WINAPI*)(LPSECURITY_ATTRIBUTES, SIZE_T, LPTHREAD_START_ROUTINE, LPVOID, DWORD, LPDWORD))Hooks::_GetProcAddress(hK32, "CreateThread");
                    if (pCreateThread) return pCreateThread(lpThreadAttributes, dwStackSize, lpStartAddress, lpParameter, dwCreationFlags, lpThreadId);
                    return nullptr;
                }
            
                inline HANDLE _GetClipboardData(UINT uFormat) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return nullptr;
                    auto pGetClipboardData = (HANDLE(WINAPI*)(UINT))Hooks::_GetProcAddress(hUser32, "GetClipboardData");
                    if (pGetClipboardData) return pGetClipboardData(uFormat);
                    return nullptr;
                }
            
                inline HWND _FindWindowA(LPCSTR lpClassName, LPCSTR lpWindowName) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return nullptr;
                    auto pFindWindowA = (HWND(WINAPI*)(LPCSTR, LPCSTR))Hooks::_GetProcAddress(hUser32, "FindWindowA");
                    if (pFindWindowA) return pFindWindowA(lpClassName, lpWindowName);
                    return nullptr;
                }
            
                inline LONG _GetWindowLongA(HWND hWnd, int nIndex) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return 0;
                    auto pGetWindowLongA = (LONG(WINAPI*)(HWND, int))Hooks::_GetProcAddress(hUser32, "GetWindowLongA");
                    if (pGetWindowLongA) return pGetWindowLongA(hWnd, nIndex);
                    return 0;
                }
            
                inline BOOL _OpenProcessToken(HANDLE ProcessHandle, DWORD DesiredAccess, PHANDLE TokenHandle) {
                    HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
                    if (!hAdvapi32) return FALSE;
                    auto pOpenProcessToken = (BOOL(WINAPI*)(HANDLE, DWORD, PHANDLE))Hooks::_GetProcAddress(hAdvapi32, "OpenProcessToken");
                    if (pOpenProcessToken) return pOpenProcessToken(ProcessHandle, DesiredAccess, TokenHandle);
                    return FALSE;
                }
            
                inline HDC _GetDC(HWND hWnd) {
                    HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
                    if (!hUser32) return nullptr;
                    auto pGetDC = (HDC(WINAPI*)(HWND))Hooks::_GetProcAddress(hUser32, "GetDC");
                    if (pGetDC) return pGetDC(hWnd);
                    return nullptr;
                }
            
                inline HDC _CreateCompatibleDC(HDC hdc) {
                    HMODULE hGdi32 = Hooks::_LoadLibraryA("gdi32.dll");
                    if (!hGdi32) return nullptr;
                    auto pCreateCompatibleDC = (HDC(WINAPI*)(HDC))Hooks::_GetProcAddress(hGdi32, "CreateCompatibleDC");
                    if (pCreateCompatibleDC) return pCreateCompatibleDC(hdc);
                    return nullptr;
                }
            
                inline BOOL _BitBlt(HDC hdc, int x, int y, int cx, int cy, HDC hdcSrc, int x1, int y1, DWORD rop) {
                    HMODULE hGdi32 = Hooks::_LoadLibraryA("gdi32.dll");
                    if (!hGdi32) return FALSE;
                    auto pBitBlt = (BOOL(WINAPI*)(HDC, int, int, int, int, HDC, int, int, DWORD))Hooks::_GetProcAddress(hGdi32, "BitBlt");
                    if (pBitBlt) return pBitBlt(hdc, x, y, cx, cy, hdcSrc, x1, y1, rop);
                    return FALSE;
                }
            
                inline HMODULE _LoadLibraryW(LPCWSTR lpLibFileName) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pLoadLibraryW = (HMODULE(WINAPI*)(LPCWSTR))Hooks::_GetProcAddress(hK32, "LoadLibraryW");
                    if (pLoadLibraryW) return pLoadLibraryW(lpLibFileName);
                    return nullptr;
                }
            
                inline HMODULE _LoadLibraryExW(LPCWSTR lpLibFileName, HANDLE hFile, DWORD dwFlags) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pLoadLibraryExW = (HMODULE(WINAPI*)(LPCWSTR, HANDLE, DWORD))Hooks::_GetProcAddress(hK32, "LoadLibraryExW");
                    if (pLoadLibraryExW) return pLoadLibraryExW(lpLibFileName, hFile, dwFlags);
                    return nullptr;
                }
            
                inline HMODULE _LoadLibraryExA(LPCSTR lpLibFileName, HANDLE hFile, DWORD dwFlags) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pLoadLibraryExA = (HMODULE(WINAPI*)(LPCSTR, HANDLE, DWORD))Hooks::_GetProcAddress(hK32, "LoadLibraryExA");
                    if (pLoadLibraryExA) return pLoadLibraryExA(lpLibFileName, hFile, dwFlags);
                    return nullptr;
                }
            
                inline HANDLE _CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return (HANDLE)-1;
                    auto pCreateToolhelp32Snapshot = (HANDLE(WINAPI*)(DWORD, DWORD))Hooks::_GetProcAddress(hK32, "CreateToolhelp32Snapshot");
                    if (pCreateToolhelp32Snapshot) return pCreateToolhelp32Snapshot(dwFlags, th32ProcessID);
                    return (HANDLE)-1;
                }
            
                inline BOOL _CreateProcessW(LPCWSTR lpApplicationName, LPWSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCWSTR lpCurrentDirectory, LPSTARTUPINFOW lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pCreateProcessW = (BOOL(WINAPI*)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCWSTR, LPSTARTUPINFOW, LPPROCESS_INFORMATION))Hooks::_GetProcAddress(hK32, "CreateProcessW");
                    if (pCreateProcessW) return pCreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
                    return FALSE;
                }
            
                inline HANDLE _CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return (HANDLE)-1;
                    auto pCreateFileW = (HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE))Hooks::_GetProcAddress(hK32, "CreateFileW");
                    if (pCreateFileW) return pCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
                    return (HANDLE)-1;
                }
            
                inline DWORD _GetTempPathW(DWORD nBufferLength, LPWSTR lpBuffer) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return 0;
                    auto pGetTempPathW = (DWORD(WINAPI*)(DWORD, LPWSTR))Hooks::_GetProcAddress(hK32, "GetTempPathW");
                    if (pGetTempPathW) return pGetTempPathW(nBufferLength, lpBuffer);
                    return 0;
                }
            
                inline BOOL _VirtualProtect(LPVOID lpAddress, SIZE_T dwSize, DWORD flNewProtect, PDWORD lpflOldProtect) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pVirtualProtect = (BOOL(WINAPI*)(LPVOID, SIZE_T, DWORD, PDWORD))Hooks::_GetProcAddress(hK32, "VirtualProtect");
                    if (pVirtualProtect) return pVirtualProtect(lpAddress, dwSize, flNewProtect, lpflOldProtect);
                    return FALSE;
                }
            
                inline LPVOID _VirtualAllocEx(HANDLE hProcess, LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return nullptr;
                    auto pVirtualAllocEx = (LPVOID(WINAPI*)(HANDLE, LPVOID, SIZE_T, DWORD, DWORD))Hooks::_GetProcAddress(hK32, "VirtualAllocEx");
                    if (pVirtualAllocEx) return pVirtualAllocEx(hProcess, lpAddress, dwSize, flAllocationType, flProtect);
                    return nullptr;
                }
            
                inline BOOL _GetVolumeInformationW(LPCWSTR lpRootPathName, LPWSTR lpVolumeNameBuffer, DWORD nVolumeNameSize, LPDWORD lpVolumeSerialNumber, LPDWORD lpMaximumComponentLength, LPDWORD lpFileSystemFlags, LPWSTR lpFileSystemNameBuffer, DWORD nFileSystemNameSize) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pGetVolumeInformationW = (BOOL(WINAPI*)(LPCWSTR, LPWSTR, DWORD, LPDWORD, LPDWORD, LPDWORD, LPWSTR, DWORD))Hooks::_GetProcAddress(hK32, "GetVolumeInformationW");
                    if (pGetVolumeInformationW) return pGetVolumeInformationW(lpRootPathName, lpVolumeNameBuffer, nVolumeNameSize, lpVolumeSerialNumber, lpMaximumComponentLength, lpFileSystemFlags, lpFileSystemNameBuffer, nFileSystemNameSize);
                    return FALSE;
                }
            
                inline UINT _GetDriveTypeW(LPCWSTR lpRootPathName) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return 1;
                    auto pGetDriveTypeW = (UINT(WINAPI*)(LPCWSTR))Hooks::_GetProcAddress(hK32, "GetDriveTypeW");
                    if (pGetDriveTypeW) return pGetDriveTypeW(lpRootPathName);
                    return 1;
                }
            
                inline BOOL _WriteProcessMemory(HANDLE hProcess, LPVOID lpBaseAddress, LPCVOID lpBuffer, SIZE_T nSize, SIZE_T *lpNumberOfBytesWritten) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pWriteProcessMemory = (BOOL(WINAPI*)(HANDLE, LPVOID, LPCVOID, SIZE_T, SIZE_T*))Hooks::_GetProcAddress(hK32, "WriteProcessMemory");
                    if (pWriteProcessMemory) return pWriteProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesWritten);
                    return FALSE;
                }
            
                inline BOOL _ReadProcessMemory(HANDLE hProcess, LPCVOID lpBaseAddress, LPVOID lpBuffer, SIZE_T nSize, SIZE_T *lpNumberOfBytesRead) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pReadProcessMemory = (BOOL(WINAPI*)(HANDLE, LPCVOID, LPVOID, SIZE_T, SIZE_T*))Hooks::_GetProcAddress(hK32, "ReadProcessMemory");
                    if (pReadProcessMemory) return pReadProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead);
                    return FALSE;
                }
            
                inline BOOL _Process32NextW(HANDLE hSnapshot, LPVOID lppe) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pProcess32NextW = (BOOL(WINAPI*)(HANDLE, LPVOID))Hooks::_GetProcAddress(hK32, "Process32NextW");
                    if (pProcess32NextW) return pProcess32NextW(hSnapshot, lppe);
                    return FALSE;
                }
            
                inline BOOL _Process32FirstW(HANDLE hSnapshot, LPVOID lppe) {
                    HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
                    if (!hK32) return FALSE;
                    auto pProcess32FirstW = (BOOL(WINAPI*)(HANDLE, LPVOID))Hooks::_GetProcAddress(hK32, "Process32FirstW");
                    if (pProcess32FirstW) return pProcess32FirstW(hSnapshot, lppe);
                    return FALSE;
                }
            }
            
            
            #undef GetProcAddress
            #undef LoadLibraryA
            #undef GetModuleHandleA
            #undef RegOpenKeyExA
            #undef RegQueryValueExA
            #undef RegCloseKey
            #undef CreateProcessA
            #undef RegisterHotKey
            #undef CallNextHookEx
            #undef GetForegroundWindow
            #undef OpenProcess
            #undef GetClipboardData
            #undef SetWindowsHookExA
            #undef SetWindowsHookEx
            #undef UnhookWindowsHookEx
            #undef OpenClipboard
            #undef SetClipboardData
            #undef CloseClipboard
            #undef CreateThread
            #undef FindWindowA
            #undef GetWindowLongA
            #undef OpenProcessToken
            #undef CreateCompatibleDC
            #undef BitBlt
            
            #undef LoadLibraryW
              #undef LoadLibraryExW
              #undef LoadLibraryExA
              #undef CreateToolhelp32Snapshot
              #undef CreateProcessW
              #undef CreateFileW
              #undef GetTempPathW
              #undef VirtualProtect
              #undef VirtualAllocEx
              #undef GetVolumeInformationW
              #undef GetDriveTypeW
              #undef WriteProcessMemory
              #undef ReadProcessMemory
              #undef Process32NextW
              #undef Process32FirstW
            
              #define GetProcAddress Hooks::_GetProcAddress
            #define LoadLibraryA Hooks::_LoadLibraryA
            #define GetModuleHandleA Hooks::_GetModuleHandleA
            #define RegOpenKeyExA Hooks::_RegOpenKeyExA
            #define RegQueryValueExA Hooks::_RegQueryValueExA
            #define RegCloseKey Hooks::_RegCloseKey
            #define CreateProcessA Hooks::_CreateProcessA
            #define RegisterHotKey Hooks::_RegisterHotKey
            #define CallNextHookEx Hooks::_CallNextHookEx
            #define GetForegroundWindow Hooks::_GetForegroundWindow
            #define OpenProcess Hooks::_OpenProcess
            #define GetClipboardData Hooks::_GetClipboardData
            #define SetWindowsHookExA Hooks::_SetWindowsHookExA
            #define SetWindowsHookEx Hooks::_SetWindowsHookExA
            #define UnhookWindowsHookEx Hooks::_UnhookWindowsHookEx
            #define OpenClipboard Hooks::_OpenClipboard
            #define SetClipboardData Hooks::_SetClipboardData
            #define CloseClipboard Hooks::_CloseClipboard
            #define CreateThread Hooks::_CreateThread
            #define FindWindowA Hooks::_FindWindowA
            #define GetWindowLongA Hooks::_GetWindowLongA
            #define OpenProcessToken Hooks::_OpenProcessToken
            #define CreateCompatibleDC Hooks::_CreateCompatibleDC
            #define BitBlt Hooks::_BitBlt
            #define LoadLibraryW Hooks::_LoadLibraryW
            #define LoadLibraryExW Hooks::_LoadLibraryExW
            #define LoadLibraryExA Hooks::_LoadLibraryExA
            #define CreateToolhelp32Snapshot Hooks::_CreateToolhelp32Snapshot
            #define CreateProcessW Hooks::_CreateProcessW
            #define CreateFileW Hooks::_CreateFileW
            #define GetTempPathW Hooks::_GetTempPathW
            #define VirtualProtect Hooks::_VirtualProtect
            #define VirtualAllocEx Hooks::_VirtualAllocEx
            #define GetVolumeInformationW Hooks::_GetVolumeInformationW
            #define GetDriveTypeW Hooks::_GetDriveTypeW
            #define WriteProcessMemory Hooks::_WriteProcessMemory
            #define ReadProcessMemory Hooks::_ReadProcessMemory
            #define Process32NextW Hooks::_Process32NextW
            #define Process32FirstW Hooks::_Process32FirstW
        )"
        SaveFile(hooks_h, hooksPayload)

        Loop Files, AhkSrcDir "\*.cpp", "R" {
            content := FileRead(A_LoopFilePath, "UTF-8")
            if !InStr(content, "#include `"Hooks.h`"") {
                lastInc := 0
                pos := 1
                while (pos := RegExMatch(content, 'm)^#include[ \t]+["<]', &m, pos)) {
                    lastInc := pos
                    pos += m.Len[0]
                }
                if (lastInc) {
                    eol := InStr(content, "`n", false, lastInc)
                    if (eol) {
                        content := SubStr(content, 1, eol) "#include `"Hooks.h`"`r`n" SubStr(content, eol + 1)
                        SaveFile(A_LoopFilePath, content)
                    }
                }
            }
        }
    }

    dangerous := []

    if (cfg.StripProcess)
        dangerous.Push("ProcessWait", "ProcessWaitClose", "ProcessClose", "ProcessExist", "ProcessSetPriority")
    if (cfg.StripRun)
        dangerous.Push("Run", "RunWait", "RunAs")
    if (cfg.StripDllCall)
        dangerous.Push("DllCall")
    if (cfg.StripRegistry)
        dangerous.Push("RegRead", "RegWrite", "RegDelete", "RegDeleteKey", "RegCreateKey")
    if (cfg.StripNetwork)
        dangerous.Push("Download")

    if (dangerous.Length > 0) {
        LogMsg("[*] Strip AHK Commands: Removing " dangerous.Length " targeted OS functions from AHK language...")
        funcs_h := AhkSrcDir "\source\lib\functions.h"
        if FileExist(funcs_h) {
            content := FileRead(funcs_h, "UTF-8")
            for funcName in dangerous {
                content := RegExReplace(content, "(?im)^(\s*md_func\(\s*" funcName "\s*,)", "// $1")
            }
            SaveFile(funcs_h, content)
        }
    }

    if (cfg.StripDangerous) {
        if (dangerous.Length > 0) {
            LogMsg("[*] Neuter Native C++: Hijacking targeted underlying Win32 APIs...")
            neuter_h := AhkSrcDir "\source\neuter.h"
            neuterPayload := "#pragma once`r`n"

            apiReturns := Map("OpenProcess", "((HANDLE)NULL)", "CreateFileW", "((HANDLE)-1)", "CreateToolhelp32Snapshot", "((HANDLE)-1)", "VirtualAllocEx", "NULL", "VirtualAlloc", "NULL", "GetProcAddress", "NULL", "LoadLibraryW", "NULL")

            GenerateMacro := ""
            if (cfg.HasOwnProp("DebugMode") && cfg.DebugMode) {
                GenerateMacro := (apiName) => (SubStr(apiName, 1, 7) = "#define" ? apiName "`r`n" : "#define " apiName "(...) (MessageBoxA(NULL, `"AHKCompiler Debug Mode:\n\nStripped API Called: " apiName "\n\nThe application attempted to call this neutered API. Uncheck it in the settings if needed.`", `"AHKCompiler Feature Stripped`", 0x30), " (apiReturns.Has(apiName) ? apiReturns[apiName] : "0") ")`r`n")
            } else {
                GenerateMacro := (apiName) => (SubStr(apiName, 1, 7) = "#define" ? apiName "`r`n" : "#define " apiName "(...) " (apiReturns.Has(apiName) ? apiReturns[apiName] : "0") "`r`n")
            }

            procApisList := ParseCsvList(cfg.NeuterProcess)
            if (cfg.StripProcess || cfg.StripRun) {
                for api in procApisList
                    neuterPayload .= GenerateMacro(api)
            }

            runApisList := ParseCsvList(cfg.NeuterRun)
            if (cfg.StripRun) {
                for api in runApisList
                    neuterPayload .= GenerateMacro(api)
            }

            SaveFile(neuter_h, neuterPayload)
            LogMsg("[*] Eradicating Process/Memory Injection APIs from IAT for VT Stealth...")

            Loop Files, AhkSrcDir "\*.cpp", "R" {
                content := FileRead(A_LoopFilePath, "UTF-8")
                lastInc := 0
                pos := 1
                while (pos := RegExMatch(content, 'm)^#include[ \t]+["<]', &m, pos)) {
                    lastInc := pos
                    pos += m.Len[0]
                }
                if (lastInc) {
                    eol := InStr(content, "`n", false, lastInc)
                    if (eol && !InStr(content, "#include `"neuter.h`"")) {
                        content := SubStr(content, 1, eol) "#include `"neuter.h`"`r`n" SubStr(content, eol + 1)
                        SaveFile(A_LoopFilePath, content)
                    }
                }
            }
        }
    }
}

ScrubFile(filePath) {
    content := FileRead(filePath, "UTF-8")
    oldContent := content
    content := StrReplace(content, "autohotkey.com", "example.com")
    content := StrReplace(content, "AutoHotkeyGUI", "CustomAppGUI")
    content := StrReplace(content, ".exe.bat.com.cmd.hta", ".exe,.bat,.com,.cmd,.hta")
    if (content != oldContent)
        SaveFile(filePath, content)
}

ResolveIncludes(filePath, visited := "") {
    if !visited
        visited := Map()

    SplitPath(filePath, &fName, &fDir)
    absPath := fDir "\" fName ; Rough normalization

    if visited.Has(absPath)
        return ""
    visited[absPath] := true

    try {
        content := FileRead(filePath, "UTF-8")
    } catch {
        return ""
    }

    outLines := ""
    Loop Parse content, "`n", "`r" {
        line := A_LoopField
        if RegExMatch(line, "i)^\s*#Include(?:Again)?\s+(.+)$", &m) {
            incTarget := Trim(m[1], " `'`"")
            targetPath := ""

            if RegExMatch(incTarget, "^<(.+)>$", &libM) {
                libName := libM[1]
                docsLib := EnvGet("USERPROFILE") "\Documents\AutoHotkey\Lib\" libName ".ahk"
                localLib := fDir "\Lib\" libName ".ahk"

                if FileExist(localLib)
                    targetPath := localLib
                else if FileExist(docsLib)
                    targetPath := docsLib
            } else {
                target := fDir "\" incTarget
                if FileExist(target)
                    targetPath := target
            }

            if (targetPath != "" && FileExist(targetPath)) {
                outLines .= "; --- Start #Include " incTarget " ---`r`n"
                outLines .= ResolveIncludes(targetPath, visited) "`r`n"
                outLines .= "; --- End #Include " incTarget " ---`r`n"
            } else {
                outLines .= line "`r`n"
            }
        } else {
            outLines .= line "`r`n"
        }
    }
    return outLines
}

EmbedScript(cfg) {
    LogMsg("[*] Resolving #Includes and injecting script at C++ Resource Level...")

    bundledCode := ResolveIncludes(cfg.TargetScript)

    if (cfg.HasOwnProp("CleanScript") && cfg.CleanScript) {
        LogMsg("[*] Auto-Cleaning Script... (Stripping Comments, #Requires, and Whitespace)")
        bundledCode := CleanAhkCode(bundledCode)
    }

    if (cfg.Resources.Length > 0) {
        masterKey := ""
        Loop 16
            masterKey := masterKey Chr(Random(65, 90))

        hasSpecialRes := false
        mapLines := ""
        for res in cfg.Resources {
            if (res.Encrypt || res.Compress) {
                hasSpecialRes := true
                mapLines .= "            if (resName == `"" res.Name "`") {`n"
                mapLines .= "                enc := " (res.Encrypt ? "true" : "false") "`n"
                mapLines .= "                cmp := " (res.Compress ? "true" : "false") "`n"
                mapLines .= "                return`n"
                mapLines .= "            }`n"
            }
        }

        if (hasSpecialRes) {
            injectedHelper := "
            (
                class AutoResourceLoader {
                    static Get(resName) {
                        enc := false
                        cmp := false
                        this._GetState(resName, &enc, &cmp)
                        
                        hModule := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
                        hResInfo := DllCall("FindResource", "Ptr", hModule, "Str", resName, "Ptr", 10, "Ptr")
                        if !hResInfo
                            throw Error("Resource not found: " resName)
                        resSize := DllCall("SizeofResource", "Ptr", hModule, "Ptr", hResInfo, "UInt")
                        hResData := DllCall("LoadResource", "Ptr", hModule, "Ptr", hResInfo, "Ptr")
                        pResData := DllCall("LockResource", "Ptr", hResData, "Ptr")
                
                        buf := Buffer(resSize)
                        DllCall("RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", pResData, "UPtr", resSize)
                        
                        if (cmp) {
                            uncompressedSize := NumGet(buf, 0, "UInt")
                            workspaceSize := 0
                            fragmentSize := 0
                            DllCall("ntdll\RtlGetCompressionWorkSpaceSize", "UShort", 2, "UInt*", &workspaceSize, "UInt*", &fragmentSize, "UInt")
                            workspace := Buffer(workspaceSize)
                            
                            newBuf := Buffer(uncompressedSize)
                            finalSize := 0
                            DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", newBuf.Ptr, "UInt", uncompressedSize, "Ptr", buf.Ptr + 4, "UInt", resSize - 4, "UInt*", &finalSize)
                            buf := newBuf
                        }
                        
                        if (enc) {
                            s := Buffer(256)
                            key := "`"" masterKey "`""
                            Loop 256
                                NumPut("UChar", A_Index - 1, s, A_Index - 1)
                            j := 0
                            keyLen := StrLen(key)
                            Loop 256 {
                                i := A_Index - 1
                                j := (j + NumGet(s, i, "UChar") + Ord(SubStr(key, Mod(i, keyLen) + 1, 1))) & 255
                                temp := NumGet(s, i, "UChar")
                                NumPut("UChar", NumGet(s, j, "UChar"), s, i)
                                NumPut("UChar", temp, s, j)
                            }
                            i := 0
                            j := 0
                            bufSize := buf.Size
                            Loop bufSize {
                                i := (i + 1) & 255
                                j := (j + NumGet(s, i, "UChar")) & 255
                                temp := NumGet(s, i, "UChar")
                                NumPut("UChar", NumGet(s, j, "UChar"), s, i)
                                NumPut("UChar", temp, s, j)
                                idx := (NumGet(s, i, "UChar") + NumGet(s, j, "UChar")) & 255
                                k := NumGet(s, idx, "UChar")
                                offset := A_Index - 1
                                NumPut("UChar", NumGet(buf, offset, "UChar") ^ k, buf, offset)
                            }
                        }
                        
                        return buf
                    }
                    
                    static _GetState(resName, &enc, &cmp) {
                " mapLines "
                    }
                }
            )"
            bundledCode := injectedHelper "`r`n`r`n" bundledCode
            cfg.MasterKey := masterKey
        }
    }

    rcTarget := AhkSrcDir "\source\resources\res_AutoHotkeySC.rc"
    if !FileExist(rcTarget)
        rcTarget := AhkSrcDir "\source\resources\AutoHotkey.rc"
    if !FileExist(rcTarget)
        rcTarget := AhkSrcDir "\source\AutoHotkey.rc"

    SplitPath(rcTarget, , &rcDir)
    destScript := rcDir "\nano_script.ahk"

    if (cfg.EncryptPayload || cfg.CompressPayload) {
        binaryBuf := Buffer(StrPut(bundledCode, "UTF-8") - 1)
        StrPut(bundledCode, binaryBuf, "UTF-8")

        LogMsg("[*] Processing Payload...")
        keyStr := ""
        if (cfg.EncryptPayload) {
            Loop 16
                keyStr .= Chr(Random(65, 90))
            EncryptRC4(binaryBuf, keyStr)
            LogMsg("    -> Encrypted via RC4 in-memory.")
        }

        if (cfg.CompressPayload) {
            compressedSize := 0
            CompressLZNT1(binaryBuf, &compressedBuf, &compressedSize)
            binaryBuf := compressedBuf
            LogMsg("    -> Compressed via LZNT1 in-memory.")
        }

        fileObj := FileOpen(destScript, "w-")
        fileObj.RawWrite(binaryBuf, binaryBuf.Size)
        fileObj.Close()

        LogMsg("[*] Injecting native decryption routines into C++ Engine...")
        scriptCpp := AhkSrcDir "\source\script.cpp"
        if FileExist(scriptCpp) {
            cppText := FileRead(scriptCpp, "UTF-8")

            cppInject := "`r`n    // --- START NATIVE PAYLOAD DECRYPT ---`r`n"
            if (cfg.CompressPayload) {
                cppInject .= "    typedef long (__stdcall *RtlDecompressBuffer_t)(unsigned short, unsigned char*, unsigned long, unsigned char*, unsigned long, unsigned long*);`r`n    HMODULE hNtdll = GetModuleHandle(TEXT(`"ntdll.dll`"));`r`n    RtlDecompressBuffer_t __RtlDecompressBuffer = (RtlDecompressBuffer_t)GetProcAddress(hNtdll, `"RtlDecompressBuffer`");`r`n`r`n    unsigned long uncompressedSize = *(unsigned long*)((LPBYTE)textbuf.mBuffer);`r`n    LPBYTE pCompressed = ((LPBYTE)textbuf.mBuffer) + 4;`r`n    unsigned long compressedSize = (unsigned long)textbuf.mLength - 4;`r`n`r`n    LPBYTE newBuf = (LPBYTE)malloc(uncompressedSize);`r`n    unsigned long finalSize = 0;`r`n    if (__RtlDecompressBuffer) __RtlDecompressBuffer(2 | 0x100, newBuf, uncompressedSize, pCompressed, compressedSize, &finalSize);`r`n    textbuf.mBuffer = newBuf;`r`n    textbuf.mLength = finalSize;`r`n"
            }
            if (cfg.EncryptPayload) {
                cppInject .= "    unsigned char S[256];`r`n    for (int i = 0; i < 256; i++) S[i] = i;`r`n    int j = 0;`r`n    const unsigned char key[] = `"" keyStr "`";`r`n    size_t keyLen = " StrLen(keyStr) ";`r`n    for (int i = 0; i < 256; i++) {`r`n        j = (j + S[i] + key[i `% keyLen]) `% 256;`r`n        unsigned char t = S[i]; S[i] = S[j]; S[j] = t;`r`n    }`r`n`r`n"
                if (!cfg.CompressPayload) {
                    cppInject .= "    LPBYTE newBufEnc = (LPBYTE)malloc(textbuf.mLength);`r`n    memcpy(newBufEnc, textbuf.mBuffer, textbuf.mLength);`r`n    textbuf.mBuffer = newBufEnc;`r`n"
                }
                cppInject .= "    int i = 0; j = 0;`r`n    LPBYTE data = (LPBYTE)textbuf.mBuffer;`r`n    size_t dataLen = textbuf.mLength;`r`n    for (size_t k = 0; k < dataLen; k++) {`r`n        i = (i + 1) `% 256;`r`n        j = (j + S[i]) `% 256;`r`n        unsigned char t = S[i]; S[i] = S[j]; S[j] = t;`r`n        data[k] ^= S[(S[i] + S[j]) `% 256];`r`n    }`r`n"
            }
            cppInject .= "    // --- END NATIVE PAYLOAD DECRYPT ---`r`n`r`n"

            cppText := StrReplace(cppText, "// NOTE: Ahk2Exe strips off the UTF-8 BOM.", cppInject "    // NOTE: Ahk2Exe strips off the UTF-8 BOM.")
            SaveFile(scriptCpp, cppText)
        }
    } else {
        SaveFile(destScript, bundledCode)
    }

    content := FileRead(rcTarget, "UTF-8")
    content := StrReplace(content, "`r`n`">AUTOHOTKEY SCRIPT<`" RCDATA `"nano_script.ahk`"`r`n", "")
    content := StrReplace(content, "`r`nMY_SCRIPT RCDATA `"nano_script.ahk`"`r`n", "")
    content := StrReplace(content, "`r`n1 RCDATA `"nano_script.ahk`"`r`n", "")

    ; Strip out any previous custom resources just in case git clean failed
    content := RegExReplace(content, "s)`r`n; --- CUSTOM RESOURCES ---.*", "")

    injection := "`r`n; --- CUSTOM RESOURCES ---`r`n1 RCDATA `"nano_script.ahk`"`r`n"
    for res in cfg.Resources {
        resPath := StrReplace(res.Path, "\", "\\")

        if (res.Encrypt || res.Compress) {
            LogMsg("    -> Ext-Resource '" res.Name "' encoding pass...")
            rObj := FileOpen(res.Path, "r-d")
            rBuf := Buffer(rObj.Length)
            rObj.RawRead(rBuf, rBuf.Size)
            rObj.Close()

            if (res.Encrypt) {
                EncryptRC4(rBuf, cfg.MasterKey)
            }
            if (res.Compress) {
                compressedSize := 0
                CompressLZNT1(rBuf, &cBuf, &compressedSize)
                rBuf := cBuf
            }

            binPath := rcDir "\temp_res_" A_Index ".bin"
            wObj := FileOpen(binPath, "w-")
            wObj.RawWrite(rBuf, rBuf.Size)
            wObj.Close()
            resPath := StrReplace(binPath, "\", "\\")
        }

        injection .= res.Name " RCDATA `"" resPath "`"`r`n"
    }
    content .= injection

    content := RegExReplace(content, "(VALUE `"FileDescription`",\s*).*", "$1`"" cfg.FileDesc "`"")
    content := RegExReplace(content, "(VALUE `"CompanyName`",\s*).*", "$1`"" cfg.Company "`"")
    content := RegExReplace(content, "(VALUE `"ProductName`",\s*).*", "$1`"" cfg.Product "`"")

    if !InStr(content, "VALUE `"LegalCopyright`"") {
        content := StrReplace(content, "VALUE `"ProductName`",", "VALUE `"LegalCopyright`", `"" cfg.Copyright "`"`r`n            VALUE `"ProductName`",")
    } else {
        content := RegExReplace(content, "(VALUE `"LegalCopyright`",\s*).*", "$1`"" cfg.Copyright "`"")
    }

    verCommas := StrReplace(cfg.Version, ".", ",")
    content := RegExReplace(content, "(VALUE `"FileVersion`",\s*).*", "$1`"" cfg.Version "`"")
    content := RegExReplace(content, "(VALUE `"ProductVersion`",\s*).*", "$1`"" cfg.Version "`"")
    content := RegExReplace(content, "(?m)^(\s*FILEVERSION\s+).*", "$1" verCommas)
    content := RegExReplace(content, "(?m)^(\s*PRODUCTVERSION\s+).*", "$1" verCommas)

    SaveFile(rcTarget, content)

    defines_h := AhkSrcDir "\source\defines.h"
    if FileExist(defines_h) {
        dhContent := FileRead(defines_h, "UTF-8")
        dhContent := StrReplace(dhContent, "_T(`">AUTOHOTKEY SCRIPT<`")", "MAKEINTRESOURCE(1)")
        dhContent := StrReplace(dhContent, "_T(`"MY_SCRIPT`")", "MAKEINTRESOURCE(1)")
        SaveFile(defines_h, dhContent)
    }

    resDir := AhkSrcDir "\source\resources"
    CopyIcon(cfg.IconMain, resDir "\icon_main.ico")
    CopyIcon(cfg.IconSuspend, resDir "\icon_suspend.ico")
    CopyIcon(cfg.IconPause, resDir "\icon_pause.ico")
    CopyIcon(cfg.IconPauseSuspend, resDir "\icon_pause_suspend.ico")
    CopyIcon(cfg.IconFiletype, resDir "\icon_filetype.ico")
    CopyIcon(cfg.IconFiletype, resDir "\icon_filetype_small.ico")
}

CopyIcon(srcPath, destPath) {
    if (srcPath != "" && FileExist(srcPath))
        FileCopy(srcPath, destPath, 1)
}

RunCompile(cfg) {
    LogMsg("[*] Compiling custom executable via MSVC (This takes about a minute)...")

    ovrMsvc := cfg.HasOwnProp("OverrideMsvc") ? cfg.OverrideMsvc : ""
    msbuildPath := ""
    if (ovrMsvc != "" && FileExist(ovrMsvc)) {
        msbuildPath := ovrMsvc
    } else {
        pf86 := EnvGet("ProgramFiles(x86)")
        if (pf86 = "")
            pf86 := "C:\Program Files (x86)"

        vswhere := pf86 "\Microsoft Visual Studio\Installer\vswhere.exe"
        if !FileExist(vswhere)
            throw Error("Could not find vswhere.exe. Please install Visual Studio Build Tools with C++.")

        cmd := "`"" vswhere "`" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe"
        tmpOut := A_Temp "\AHKCompiler_vswhere.txt"

        RunWait(A_ComSpec " /c `"" cmd " > `"" tmpOut "`"`"", , "Hide")

        if !FileExist(tmpOut)
            throw Error("Failed to write vswhere output to temporary file.")

        msbuildPath := Trim(FileRead(tmpOut), " `t`r`n")
        FileDelete(tmpOut)
    }

    if (msbuildPath = "" || !FileExist(msbuildPath))
        throw Error("MSBuild not found. Verify C++ Build Tools installation.")

    slnPath := AhkSrcDir "\AutoHotkeyx.sln"
    platform := (cfg.Arch = "x86") ? "Win32" : "x64"

    tmpBuildOut := A_Temp "\AHKCompiler_build_out.txt"
    tmpExitCode := A_Temp "\AHKCompiler_exit_code.txt"
    if FileExist(tmpBuildOut)
        FileDelete(tmpBuildOut)
    if FileExist(tmpExitCode)
        FileDelete(tmpExitCode)

    ltcgFlag := cfg.OptLTCG ? "true" : "false"
    buildCmdFull := "`"" msbuildPath "`" `"" slnPath "`" /p:Configuration=Self-contained /p:Platform=" platform " /p:WholeProgramOptimization=" ltcgFlag " /t:Rebuild"

    PID := 0
    Run(A_ComSpec " /c `"" buildCmdFull " > `"" tmpBuildOut "`" 2>&1 & echo %errorlevel% > `"" tmpExitCode "`"`"", , "Hide", &PID)

    lastLen := 0
    while ProcessExist(PID) {
        if (cfg.ShowMSBuild && FileExist(tmpBuildOut)) {
            try {
                allText := FileRead(tmpBuildOut, "UTF-8")
                if (StrLen(allText) > lastLen) {
                    LogMsgRaw(SubStr(allText, lastLen + 1))
                    lastLen := StrLen(allText)
                }
            }
        }
        Sleep(250)
    }

    ; Final read buffer check
    if (cfg.ShowMSBuild && FileExist(tmpBuildOut)) {
        try {
            allText := FileRead(tmpBuildOut, "UTF-8")
            if (StrLen(allText) > lastLen) {
                LogMsgRaw(SubStr(allText, lastLen + 1))
            }
        }
    }

    exitCode := 0
    if FileExist(tmpExitCode) {
        exitCodeStr := Trim(FileRead(tmpExitCode, "UTF-8"), " `t`r`n")
        if IsInteger(exitCodeStr)
            exitCode := Integer(exitCodeStr)
        FileDelete(tmpExitCode)
    }
    if FileExist(tmpBuildOut)
        FileDelete(tmpBuildOut)

    if (exitCode != 0)
        LogMsg("[!] Warning: MSBuild returned non-zero exit code (" exitCode "). Validating output...")

    archStr := (cfg.Arch = "x86") ? "32-bit" : "64-bit"
    outputExe := AhkSrcDir "\bin\Unicode " archStr ".bin"
    if !FileExist(outputExe) {
        fallbackArch := (cfg.Arch = "x86") ? "Win32" : "x64"
        outputExe := AhkSrcDir "\bin\" fallbackArch "\Self-contained\AutoHotkeySC.bin"
    }

    if FileExist(outputExe) {
        if (cfg.HasOwnProp("CustomOutput") && Trim(cfg.CustomOutput) != "") {
            finalPath := Trim(cfg.CustomOutput)
        } else {
            SplitPath(cfg.TargetScript, &fName, &fDir, &fExt, &fNameNoExt)
            finalPath := fDir "\" fNameNoExt ".exe"
        }
        FileCopy(outputExe, finalPath, 1)

        if (cfg.Compress != "none") {
            LogMsg("[*] Applying Native Windows OS Executable Compression (" cfg.Compress ")...")
            RunWait(A_ComSpec " /c compact /c /exe:" cfg.Compress " `"" finalPath "`"", , "Hide")
            LogMsg("[+] OS Compressed via FileSystem!")
        } else {
            LogMsg("[+] Zero UPX. Zero Packing. 100% AV-Safe Factory Native C++ Build.")
        }
        LogMsg("[+] Compiled to: " finalPath)
    } else {
        throw Error("Compilation failed. Output EXE not found.")
    }
}

CleanBuildArtifacts() {
    LogMsg("[*] Cleaning up build artifacts...")
    folders := [AhkSrcDir "\temp", AhkSrcDir "\bin", AhkSrcDir "\source\autogenerated"]
    for d in folders {
        if DirExist(d) {
            RunWait(A_ComSpec " /c rmdir /s /q `"" d "`"", , "Hide")
        }
    }
}

SaveFile(filePath, content) {
    if FileExist(filePath)
        FileDelete(filePath)
    FileAppend(content, filePath, "UTF-8")
}

CheckEnvironmentStatusUi() {
    ovrGit := MainGui["OverrideGit"].Value
    gitExe := (ovrGit != "" && FileExist(ovrGit)) ? "`"" ovrGit "`"" : "git"
    gitTest := RunWait(A_ComSpec " /c " gitExe " --version", , "Hide")
    try uiGitStatus.Text := (gitTest == 0) ? "VERIFIED (Git is accessible)" : "NOT DETECTED (Will fallback to automatic ZIP Direct Download)"

    ovrMsvc := MainGui["OverrideMsvc"].Value
    hasMsvc := false
    if (ovrMsvc != "" && FileExist(ovrMsvc)) {
        hasMsvc := true
    } else {
        pathVsWhere := A_ProgramFiles "\Microsoft Visual Studio\Installer\vswhere.exe"
        pathVsWhere32 := A_ProgramFiles " (x86)\Microsoft Visual Studio\Installer\vswhere.exe"

        if FileExist(pathVsWhere) || FileExist(pathVsWhere32) {
            vswhere := FileExist(pathVsWhere) ? pathVsWhere : pathVsWhere32
            outPath := A_Temp "\vswhere_chk.txt"
            cmd := "`"" vswhere "`" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe"
            RunWait(A_ComSpec " /c `"" cmd " > `"" outPath "`"`"", , "Hide")
            if FileExist(outPath) {
                if InStr(FileRead(outPath), "MSBuild.exe")
                    hasMsvc := true
                FileDelete(outPath)
            }
        }
    }

    try uiMsvcStatus.Text := hasMsvc ? "VERIFIED (MSBuild / C++ Workloads Found)" : "MISSING (C++ Build Tools not found. Compilation will fail)"
}

HeadlessBuild(pName) {
    cfgFile := PresetFile
    cfgSect := pName

    isLocalConfig := false
    inferredTarget := ""

    if FileExist(pName) && SubStr(pName, -4) = ".ini" {
        cfgFile := pName
        cfgSect := "Config"
        isLocalConfig := true
        ; Extrapolate the target script from the .ahkcompiler.ini filename
        if (SubStr(pName, -16) = ".ahkcompiler.ini")
            inferredTarget := SubStr(pName, 1, StrLen(pName) - 16)
    }

    if !FileExist(cfgFile) {
        try FileAppend("[!] Configuration file not found.`n", "*")
        return
    }

    try {
        cfg := {}
        if (isLocalConfig && inferredTarget != "")
            cfg.TargetScript := inferredTarget
        else
            cfg.TargetScript := IniRead(cfgFile, cfgSect, "TargetScript", "")
        cfg.CustomOutput := IniRead(cfgFile, cfgSect, "CustomOutput", "")
        cfg.RepoUrl := IniRead(cfgFile, cfgSect, "RepoUrl", "https://github.com/Lexikos/AutoHotkey_L.git")
        cfg.Branch := IniRead(cfgFile, cfgSect, "Branch", "v2.0")
        cfg.Arch := IniRead(cfgFile, cfgSect, "Arch", "x64")
        cfg.Compress := IniRead(cfgFile, cfgSect, "Compress", "none")
        cfg.OptLevel := IniRead(cfgFile, cfgSect, "OptLevel", "Minimize Size")
        cfg.OptRuntime := IniRead(cfgFile, cfgSect, "OptRuntime", "Dynamic CRT (Smaller)")
        cfg.OptLTCG := Integer(IniRead(cfgFile, cfgSect, "OptLTCG", 1))
        cfg.OptStringPool := Integer(IniRead(cfgFile, cfgSect, "OptStringPool", 1))
        cfg.ShowMSBuild := Integer(IniRead(cfgFile, cfgSect, "ShowMSBuild", 0))

        cfg.Company := IniRead(cfgFile, cfgSect, "Company", "My Custom Company")
        cfg.Product := IniRead(cfgFile, cfgSect, "Product", "My Custom App")
        cfg.FileDesc := IniRead(cfgFile, cfgSect, "FileDesc", "My Custom Application")
        cfg.Version := IniRead(cfgFile, cfgSect, "Version", "1.0.0.0")
        cfg.Copyright := IniRead(cfgFile, cfgSect, "Copyright", "(c) 2026 My Custom Company")

        cfg.DelayLoad := Integer(IniRead(cfgFile, cfgSect, "DelayLoad", 0))
        cfg.RemoveStrings := Integer(IniRead(cfgFile, cfgSect, "RemoveStrings", 0))
        cfg.EncryptPayload := Integer(IniRead(cfgFile, cfgSect, "EncryptPayload", 0))
        cfg.CompressPayload := Integer(IniRead(cfgFile, cfgSect, "CompressPayload", 0))
        cfg.InjectHooks := Integer(IniRead(cfgFile, cfgSect, "InjectHooks", 0))
        cfg.StripDangerous := Integer(IniRead(cfgFile, cfgSect, "StripDangerous", 1))
        cfg.DebugMode := Integer(IniRead(cfgFile, cfgSect, "DebugMode", 0))

        cfg.StripProcess := Integer(IniRead(cfgFile, cfgSect, "StripProcess", 1))
        cfg.StripRun := Integer(IniRead(cfgFile, cfgSect, "StripRun", 1))
        cfg.StripDllCall := Integer(IniRead(cfgFile, cfgSect, "StripDllCall", 1))
        cfg.StripRegistry := Integer(IniRead(cfgFile, cfgSect, "StripRegistry", 1))
        cfg.StripNetwork := Integer(IniRead(cfgFile, cfgSect, "StripNetwork", 1))
        cfg.CleanScript := Integer(IniRead(cfgFile, cfgSect, "CleanScript", 1))

        cfg.NeuterProcess := IniRead(cfgFile, cfgSect, "NeuterProcess", "OpenProcess, VirtualAllocEx, VirtualProtectEx, WriteProcessMemory, ReadProcessMemory, CreateToolhelp32Snapshot, Process32FirstW, Process32NextW")
        cfg.NeuterRun := IniRead(cfgFile, cfgSect, "NeuterRun", "ShellExecuteExW")

        cfg.IconMain := IniRead(cfgFile, cfgSect, "IconMain", "")
        cfg.IconSuspend := IniRead(cfgFile, cfgSect, "IconSuspend", "")
        cfg.IconPause := IniRead(cfgFile, cfgSect, "IconPause", "")
        cfg.IconPauseSuspend := IniRead(cfgFile, cfgSect, "IconPauseSuspend", "")
        cfg.IconFiletype := IniRead(cfgFile, cfgSect, "IconFiletype", "")

        cfg.OverrideGit := IniRead(cfgFile, cfgSect, "OverrideGit", "")
        cfg.OverrideMsvc := IniRead(cfgFile, cfgSect, "OverrideMsvc", "")

        cfg.Resources := []
        rcount := Integer(IniRead(cfgFile, cfgSect, "ResourceCount", 0))
        Loop rcount {
            rName := IniRead(cfgFile, cfgSect, "ResName" A_Index, "")
            rPath := IniRead(cfgFile, cfgSect, "ResPath" A_Index, "")
            rEnc := IniRead(cfgFile, cfgSect, "ResEncrypt" A_Index, "0")
            rCmp := IniRead(cfgFile, cfgSect, "ResCompress" A_Index, "0")
            if (rName != "" && rPath != "")
                cfg.Resources.Push({ Name: rName, Path: rPath, Encrypt: (rEnc ? true : false), Compress: (rCmp ? true : false) })
        }

        if (cfg.TargetScript = "" || !FileExist(cfg.TargetScript)) {
            try FileAppend("[!] Preset '" pName "' has invalid TargetScript.`n", "*")
            return
        }

        CompileProcess(cfg)
    } catch Error as err {
        try FileAppend("[!] Failed to decode preset '" pName "'. Error: " err.Message "`n", "*")
    }
}

/*
lol
*/

EncryptRC4(buf, key) {
    s := Buffer(256)
    Loop 256
        NumPut("UChar", A_Index - 1, s, A_Index - 1)

    j := 0
    keyLen := StrLen(key)
    Loop 256 {
        i := A_Index - 1
        j := (j + NumGet(s, i, "UChar") + Ord(SubStr(key, Mod(i, keyLen) + 1, 1))) & 255
        temp := NumGet(s, i, "UChar")
        NumPut("UChar", NumGet(s, j, "UChar"), s, i)
        NumPut("UChar", temp, s, j)
    }

    i := 0
    j := 0
    bufSize := buf.Size
    Loop bufSize {
        i := (i + 1) & 255
        j := (j + NumGet(s, i, "UChar")) & 255
        temp := NumGet(s, i, "UChar")
        NumPut("UChar", NumGet(s, j, "UChar"), s, i)
        NumPut("UChar", temp, s, j)

        idx := (NumGet(s, i, "UChar") + NumGet(s, j, "UChar")) & 255
        k := NumGet(s, idx, "UChar")

        offset := A_Index - 1
        NumPut("UChar", NumGet(buf, offset, "UChar") ^ k, buf, offset)
    }
}

CompressLZNT1(uncompressedBuf, &outBuf, &compressedSizeOutput) {
    uncompressedSize := uncompressedBuf.Size
    workspaceSize := 0
    fragmentSize := 0
    DllCall("ntdll\RtlGetCompressionWorkSpaceSize", "UShort", 2, "UInt*", &workspaceSize, "UInt*", &fragmentSize, "UInt")

    workspace := Buffer(workspaceSize)
    compressedSizeTemp := uncompressedSize + 4096
    compressedTemp := Buffer(compressedSizeTemp)
    finalSize := 0

    DllCall("ntdll\RtlCompressBuffer", "UShort", 0x102, "Ptr", uncompressedBuf, "UInt", uncompressedSize, "Ptr", compressedTemp, "UInt", compressedSizeTemp, "UInt", 4096, "UInt*", &finalSize, "Ptr", workspace, "UInt")

    compressedSizeOutput := finalSize + 4
    outBuf := Buffer(compressedSizeOutput)
    NumPut("UInt", uncompressedSize, outBuf, 0)
    DllCall("RtlMoveMemory", "Ptr", outBuf.Ptr + 4, "Ptr", compressedTemp.Ptr, "UPtr", finalSize)
}

CleanAhkCode(code) {
    code := RegExReplace(code, "s)/\*.*?\*/", "")

    outLines := []
    lines := StrSplit(code, "`n", "`r")
    for line in lines {
        line := Trim(line, " `t")
        if (line = "")
            continue

        if (RegExMatch(line, "i)^#Requires"))
            continue

        inQuote := ""
        commentPos := 0
        escape := false

        lineLen := StrLen(line)
        loop lineLen {
            c := SubStr(line, A_Index, 1)

            if escape {
                escape := false
                continue
            }
            if c == "``" {
                escape := true
                continue
            }

            if (inQuote == "") {
                if (c == "`"" || c == "'") {
                    inQuote := c
                } else if (c == ";") {
                    if (A_Index == 1 || SubStr(line, A_Index - 1, 1) ~= "[ `t]") {
                        commentPos := A_Index
                        break
                    }
                }
            } else {
                if c == inQuote {
                    inQuote := ""
                }
            }
        }

        if (commentPos > 0)
            line := Trim(SubStr(line, 1, commentPos - 1), " `t")

        if (line != "")
            outLines.Push(line)
    }

    finalCode := ""
    for L in outLines
        finalCode .= L "`r`n"

    return finalCode
}
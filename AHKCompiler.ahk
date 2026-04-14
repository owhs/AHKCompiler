#Requires AutoHotkey v2.0
#SingleInstance Force

; -----------------------------------------------------------------------------
; AHKCompiler - Advanced Native AutoHotkey v2 Compiler
; -----------------------------------------------------------------------------

Global AppVersion := "0.9"
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
MainGui.Add("GroupBox", "x20 y40 w660 h60", "General Obfuscation")
MainGui.Add("Checkbox", "x30 y60 vDelayLoad Checked", "Delay Load OS Imports (Clean IAT)")
MainGui.Add("Checkbox", "x320 y60 vRemoveStrings Checked", "Scrub AHK Signature Strings")

MainGui.Add("GroupBox", "x20 y110 w230 h165", "1. Strict AHK Strip")
MainGui.Add("Text", "x30 y130 w210 cGray", "Removes functions from scripts:")
MainGui.Add("Checkbox", "x30 y150 w190 vStripProcess Checked", "Process (e.g. ProcessExist)")
MainGui.Add("Checkbox", "x30 y175 vStripRun Checked", "Run (e.g. RunWait)")
MainGui.Add("Checkbox", "x30 y200 vStripDllCall Checked", "DllCall (e.g. DllCall)")
MainGui.Add("Checkbox", "x30 y225 w190 vStripRegistry Checked", "Registry (e.g. RegWrite)")
MainGui.Add("Checkbox", "x30 y250 vStripNetwork Checked", "Network (e.g. Download)")

MainGui.Add("GroupBox", "x260 y110 w420 h165", "2. Deep Win32 API Neuter (C++ Level)")
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

Global ResList := MainGui.Add("ListView", "x25 y80 w655 h180 +Grid", ["Resource Name", "File Path"])
ResList.ModifyCol(1, 150)
ResList.ModifyCol(2, 480)
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
AddToolTip("StripDangerous", "Activates BOTH AHK Feature Stripping (left) and C++ Win32 API Neutering (right).`nThis handles everything below this toggle simultaneously.")
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
    if (rName = "" || rPath = "") {
        MsgBox("Both Resource Name and File Path are required.", "Error")
        return
    }
    ResList.Add("", rName, rPath)
    MainGui["ResName"].Value := "CUSTOM_DATA"
    MainGui["ResPath"].Value := ""
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
        MainGui["StripDangerous"].Value := Integer(IniRead(iniFile, pName, "StripDangerous", 1))
        MainGui["DebugMode"].Value := Integer(IniRead(iniFile, pName, "DebugMode", 0))

        MainGui["StripProcess"].Value := Integer(IniRead(iniFile, pName, "StripProcess", 1))
        MainGui["StripRun"].Value := Integer(IniRead(iniFile, pName, "StripRun", 1))
        MainGui["StripDllCall"].Value := Integer(IniRead(iniFile, pName, "StripDllCall", 1))
        MainGui["StripRegistry"].Value := Integer(IniRead(iniFile, pName, "StripRegistry", 1))
        MainGui["StripNetwork"].Value := Integer(IniRead(iniFile, pName, "StripNetwork", 1))

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
            if (rName != "" && rPath != "")
                ResList.Add("", rName, rPath)
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
    IniWrite(saved.StripDangerous, iniPath, pName, "StripDangerous")
    IniWrite(saved.DebugMode, iniPath, pName, "DebugMode")

    IniWrite(saved.StripProcess, iniPath, pName, "StripProcess")
    IniWrite(saved.StripRun, iniPath, pName, "StripRun")
    IniWrite(saved.StripDllCall, iniPath, pName, "StripDllCall")
    IniWrite(saved.StripRegistry, iniPath, pName, "StripRegistry")
    IniWrite(saved.StripNetwork, iniPath, pName, "StripNetwork")

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
        resArray.Push({ Name: ResList.GetText(A_Index, 1), Path: ResList.GetText(A_Index, 2) })
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
                lastInc := InStr(content, "#include ", false, -1)
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

    rcTarget := AhkSrcDir "\source\resources\res_AutoHotkeySC.rc"
    if !FileExist(rcTarget)
        rcTarget := AhkSrcDir "\source\resources\AutoHotkey.rc"
    if !FileExist(rcTarget)
        rcTarget := AhkSrcDir "\source\AutoHotkey.rc"

    SplitPath(rcTarget, , &rcDir)
    destScript := rcDir "\nano_script.ahk"
    SaveFile(destScript, bundledCode)

    content := FileRead(rcTarget, "UTF-8")
    content := StrReplace(content, "`r`n`">AUTOHOTKEY SCRIPT<`" RCDATA `"nano_script.ahk`"`r`n", "")
    content := StrReplace(content, "`r`nMY_SCRIPT RCDATA `"nano_script.ahk`"`r`n", "")
    content := StrReplace(content, "`r`n1 RCDATA `"nano_script.ahk`"`r`n", "")

    ; Strip out any previous custom resources just in case git clean failed
    content := RegExReplace(content, "s)`r`n; --- CUSTOM RESOURCES ---.*", "")

    injection := "`r`n; --- CUSTOM RESOURCES ---`r`n1 RCDATA `"nano_script.ahk`"`r`n"
    for res in cfg.Resources {
        resPath := StrReplace(res.Path, "\", "\\")
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
        cfg.StripDangerous := Integer(IniRead(cfgFile, cfgSect, "StripDangerous", 1))
        cfg.DebugMode := Integer(IniRead(cfgFile, cfgSect, "DebugMode", 0))

        cfg.StripProcess := Integer(IniRead(cfgFile, cfgSect, "StripProcess", 1))
        cfg.StripRun := Integer(IniRead(cfgFile, cfgSect, "StripRun", 1))
        cfg.StripDllCall := Integer(IniRead(cfgFile, cfgSect, "StripDllCall", 1))
        cfg.StripRegistry := Integer(IniRead(cfgFile, cfgSect, "StripRegistry", 1))
        cfg.StripNetwork := Integer(IniRead(cfgFile, cfgSect, "StripNetwork", 1))

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
            if (rName != "" && rPath != "")
                cfg.Resources.Push({ Name: rName, Path: rPath })
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
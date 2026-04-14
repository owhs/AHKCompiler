#Requires AutoHotkey v2.0
#SingleInstance Force

; -----------------------------------------------------------------------------
; AHKCompiler Headless Build Automation Script
; -----------------------------------------------------------------------------
; The recommended workflow is to configure your app using the AHKCompiler GUI first.
; Check "Auto-Save config alongside script" and run a manual build once.
; This natively generates an .ahkcompiler.ini config file right next to your script!
; You can then seamlessly automate headless builds by pointing the compiler directly to that config!

; --- Configuration ---
CompilerAhk := A_ScriptDir "\AHKCompiler.ahk"
CompilerExe := A_ScriptDir "\AHKCompiler.exe"
AhkInterpreter := A_AhkPath

; Toggle this to switch between compiling via the uncompiled .ahk engine vs the compiled .exe engine
UseCompiledEngine := false

ScriptName := "test" ;; <<-- change this line! :)
TargetScript := A_ScriptDir "\" ScriptName ".ahk"
ConfigFile := TargetScript ".ahkcompiler.ini"

OutputName := ScriptName ".exe"
OutputPath := A_ScriptDir
OutputExe := OutputPath "\" OutputName

AutoRun := true
; -----------------------------------------------------------------------------

if (UseCompiledEngine && !FileExist(CompilerExe)) {
    MsgBox("Please compile AHKCompiler.ahk into 'AHKCompiler.exe' first to test this script.", "Missing Compiler", "Iconx")
    ExitApp()
} else if (!UseCompiledEngine && !FileExist(CompilerAhk)) {
    MsgBox("Please ensure AHKCompiler.ahk exists.", "Missing Compiler", "IconX")
    ExitApp()
}

if !FileExist(TargetScript) {
    MsgBox("Please ensure " ScriptName " exists.", "Error", "IconX")
    ExitApp()
}

if FileExist(OutputExe)
    FileDelete(OutputExe)

CmdBase := UseCompiledEngine ? ('"' CompilerExe '"') : ('"' AhkInterpreter '" "' CompilerAhk '"')

if !FileExist(ConfigFile) {
    res := MsgBox("No auto-saved config found for " ScriptName "!`n`nThe recommended workflow is:`n1. Open AHKCompiler GUI`n2. Load " ScriptName "`n3. Ensure Auto-Save Checkbox is checked`n4. Compile once to generate the .ini hook.`n`nContinue with un-configured defaults?", "Missing Local Config", 0x4)
    if (res = "No")
        ExitApp()
    RunWait(CmdBase ' /build "Default"', OutputPath, "Hide")
} else {
    MsgBox("Starting automated headless compilation using " (UseCompiledEngine ? "compiled EXE" : "native AHK engine") " and config:`n" ConfigFile)
    RunWait(CmdBase ' /build "' ConfigFile '"', OutputPath, "Hide")
}

if (FileExist(OutputExe)) {
    if (AutoRun) {
        MsgBox("Compiled Compiler Build Successful! Launching test executable...", "Success")
        Run('"' OutputExe '"', OutputPath)
    } else {
        MsgBox("Compiled Compiler Build Successful!", "Success")
    }
} else {
    MsgBox("Compiled Headless build failed. Ensure the config specifies Custom Output as '" OutputName "'", "Error", "IconX")
}
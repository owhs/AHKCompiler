#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Configuration ---
; To benchmark your own script instead of the generated one, set this to the absolute path of your AHK script.
; E.g., CustomBenchmarkScript := "C:\Your\Path\To\Script.ahk"
; If you leave it blank, the tool will generate and use its built-in heavy math/string loop benchmark.
CustomBenchmarkScript := ""
; ---------------------

CompilerAhk := A_ScriptDir "\AHKCompiler.ahk"
AhkInterpreter := A_AhkPath

if !FileExist(CompilerAhk) {
    MsgBox("Could not find AHKCompiler.ahk in the current directory.")
    ExitApp()
}

TargetScript := A_ScriptDir "\benchmark_subject.ahk"
TargetExeSize := A_ScriptDir "\benchmark_size.exe"
TargetExeSpeed := A_ScriptDir "\benchmark_speed.exe"
UsingCustom := false

if (CustomBenchmarkScript != "" && FileExist(CustomBenchmarkScript)) {
    TargetScript := CustomBenchmarkScript
    UsingCustom := true
} else {
    ; 1. Create a complex benchmark script
    scriptContent := "
    (
    #Requires AutoHotkey v2.0
    #SingleInstance Force

    startLoad := A_TickCount

    ; Complex mathematical and loop task
    res := 0.0
    Loop 1000000 {
        res += Sqrt(A_Index) * Sin(A_Index * 0.01)
    }

    ; Some string operations
    str := `"`"
    Loop 10000 {
        str .= `"test`" A_Index
    }
    str := StrReplace(str, `"test`", `"bench`")

    endLoad := A_TickCount
    totalTime := endLoad - startLoad

    if A_Args.Length > 0 {
        FileAppend(totalTime, A_Args[1], `"UTF-8`")
        ExitApp(0)
    } else {
        MsgBox(`"Benchmark Complete: `" totalTime `" ms`")
    }
    )"

    if FileExist(TargetScript)
        FileDelete(TargetScript)
    FileAppend(scriptContent, TargetScript)
}

; Define common config template
BaseConfig := "
(
TargetScript={}
CustomOutput={}
RepoUrl=https://github.com/Lexikos/AutoHotkey_L.git
Branch=v2.0
Arch=x64
Compress=none
OptLevel={}
OptRuntime=Dynamic CRT (Smaller)
OptLTCG=1
OptStringPool=1
ShowMSBuild=0
Company=Benchmark
Product=Benchmark
FileDesc=Benchmark
Version=1.0.0.0
Copyright=(c) 2026
DelayLoad=0
RemoveStrings=0
StripDangerous=1
DebugMode=0
StripProcess=0
StripRun=0
StripDllCall=0
StripRegistry=0
StripNetwork=0
NeuterProcess=
NeuterRun=
IconMain=
IconSuspend=
IconPause=
IconPauseSuspend=
IconFiletype=
OverrideGit=
OverrideMsvc=
ResourceCount=0
)"

RunBenchmark(label, exeOut, optLevelStr, targetAhk, &outBuildTime, &outFileSize, &outInternalTime, &outTotalTime) {
    global CompilerAhk, AhkInterpreter, BaseConfig
    
    iniPath := A_ScriptDir "\temp_bench_" optLevelStr ".ini"
    cfgStr := StrReplace(BaseConfig, "{}", targetAhk, , , 1)
    cfgStr := StrReplace(cfgStr, "{}", exeOut, , , 1)
    cfgStr := StrReplace(cfgStr, "{}", optLevelStr, , , 1)
    
    if FileExist(iniPath)
        FileDelete(iniPath)
    FileAppend("[Config]`n" cfgStr, iniPath)
    
    if FileExist(exeOut)
        FileDelete(exeOut)
        
    ; Compile Headless and measure build time
    startTick := A_TickCount
    RunWait('"' AhkInterpreter '" "' CompilerAhk '" /build "' iniPath '"', A_ScriptDir, "Hide")
    outBuildTime := A_TickCount - startTick
    
    if !FileExist(exeOut) {
        MsgBox("Failed to compile " label " benchmark.")
        ExitApp()
    }
    
    outFileSize := FileGetSize(exeOut)
    
    ; Run the executable and capture runtime
    outFile := A_ScriptDir "\temp_out_" optLevelStr ".txt"
    if FileExist(outFile)
        FileDelete(outFile)
    
    startRun := A_TickCount
    ; Only pass the outfile if not using a custom user script (or user script can optionally handle it)
    RunWait('"' exeOut '" "' outFile '"', A_ScriptDir, "Hide")
    outTotalTime := A_TickCount - startRun
    
    if FileExist(outFile) {
        outInternalTime := FileRead(outFile)
        FileDelete(outFile)
    } else {
        outInternalTime := "N/A"
    }
    
    FileDelete(iniPath)
}

benchMsg := UsingCustom ? "Compiling CUSTOM benchmark: '" TargetScript "'" : "Compiling DEFAULT high-load benchmark (benchmark_subject.ahk)."
MsgBox("Starting AHKCompiler Benchmark Tool.`n`n" benchMsg "`n`nThis compiles TWICE (Minimize Size vs Maximize Speed), measuring build time, final file size, internal execution time, and total boot+run time.`n`nThis process will take a few minutes. Please wait.")

GuiBench := Gui("+AlwaysOnTop", "Compiler Benchmark Tool")
GuiBench.Add("Text", "w400 vStatusTxt", "Compiling Minimize Size. Please wait...")
GuiBench.Show("NoActivate")

buildSize := 0
fileSizeSize := 0
internalSize := 0
totalSize := 0
RunBenchmark("Minimize Size", TargetExeSize, "Minimize Size", TargetScript, &buildSize, &fileSizeSize, &internalSize, &totalSize)

GuiBench["StatusTxt"].Value := "Compiling Maximize Speed. Please wait..."

buildSpeed := 0
fileSizeSpeed := 0
internalSpeed := 0
totalSpeed := 0
RunBenchmark("Maximize Speed", TargetExeSpeed, "Maximize Speed", TargetScript, &buildSpeed, &fileSizeSpeed, &internalSpeed, &totalSpeed)

GuiBench.Destroy()

; Clean up temp script if we generated it
if (!UsingCustom && FileExist(TargetScript))
    FileDelete(TargetScript)

kbSize := Round(fileSizeSize / 1024)
kbSpeed := Round(fileSizeSpeed / 1024)

report := "==============================================`n"
report .= "      AHKCompiler Optimization Benchmark      `n"
report .= "==============================================`n"
if UsingCustom
    report .= "Target: " TargetScript "`n==============================================`n"
report .= "`n"

report .= "--- MINIMIZE SIZE ---`n"
report .= "Build Time:          `t" Round(buildSize/1000, 1) " seconds`n"
report .= "File Size:           `t" kbSize " KB`n"
if (internalSize != "N/A")
    report .= "Internal Processing: `t" internalSize " ms`n"
report .= "Total Boot + Run:    `t" totalSize " ms`n`n"

report .= "--- MAXIMIZE SPEED ---`n"
report .= "Build Time:          `t" Round(buildSpeed/1000, 1) " seconds`n"
report .= "File Size:           `t" kbSpeed " KB`n"
if (internalSpeed != "N/A")
    report .= "Internal Processing: `t" internalSpeed " ms`n"
report .= "Total Boot + Run:    `t" totalSpeed " ms`n`n"

report .= "==============================================`n"
if (kbSize < kbSpeed) {
    report .= "Minimize Size was " Abs(kbSpeed - kbSize) " KB smaller.`n"
} else if (kbSpeed < kbSize) {
    report .= "Maximize Speed was " Abs(kbSpeed - kbSize) " KB smaller?!`n"
} else {
    report .= "Both produced the exact same file size (" kbSize " KB).`n"
}

if (totalSpeed < totalSize) {
    report .= "Maximize Speed was " Abs(totalSize - totalSpeed) " ms faster overall!`n"
} else if (totalSize < totalSpeed) {
    report .= "Minimize Size was actually " Abs(totalSpeed - totalSize) " ms faster overall?!`n"
} else {
    report .= "Both took the exact same total time (" totalSize " ms).`n"
}

if (!UsingCustom && internalSize != "N/A" && internalSpeed != "N/A" && IsNumber(internalSize) && IsNumber(internalSpeed)) {
    if (internalSpeed < internalSize) {
        report .= "Maximize Speed processed computationally " Abs(internalSize - internalSpeed) " ms faster.`n"
    } else if (internalSize < internalSpeed) {
        report .= "Minimize Size processed computationally " Abs(internalSpeed - internalSize) " ms faster?!`n"
    }
}

MsgBox(report, "Benchmark Results")
FileAppend(report "`n", A_ScriptDir "\benchmark_results.txt")

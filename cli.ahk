; Headless entry: AutoHotkey64.exe cli.ahk <command> <profile>
;   /list                      list profiles
;   /build  <profile>          build/compile a profile
;   /features                  list strippable features
; Reused by AHK2BC.ahk for its own /build handoff.
#Requires AutoHotkey v2.0
#include core.ahk
#include profiles.ahk

Main()
Main() {
    store := ProfileStore(A_ScriptDir "\data\profiles.ini")
    eng := Engine(A_ScriptDir, (m) => FileAppend(m "`n", "*"))
    args := A_Args
    cmd := args.Length >= 1 ? args[1] : "/list"

    if (cmd = "/features") {
        for name in eng.featureOrder {
            f := eng.features[name]
            FileAppend(Format("{:-16} ~{:4} KB  {}`n", name, f["kb"], f["title"]), "*")
        }
        return
    }
    if (cmd = "/list") {
        for n in store.List() {
            c := store.ToConfig(n)
            FileAppend(Format("{:-28} [{}] {}`n", n, c.kind, c.description), "*")
        }
        return
    }
    if (cmd = "/build" && args.Length >= 2) {
        name := args[2]
        if !store.Has(name) {
            FileAppend("Unknown profile: " name "`n", "*")
            ExitApp(2)
        }
        cfg := store.ToConfig(name)
        ; optional overrides:  key=value ...
        Loop args.Length - 2 {
            if RegExMatch(args[A_Index + 2], "^(\w+)=(.*)$", &m)
                cfg.%m[1]% := (m[2] = "1" || m[2] = "0") && ProfileStore.NumKeys.Has(m[1]) ? (m[2] = "1") : m[2]
        }
        try {
            t0 := A_TickCount
            res := eng.BuildProfile(cfg)
            ok := true
            for r in res
                ok := ok && r.ok
            FileAppend("`n" (ok ? "[+] DONE" : "[!] FAILED") " in " Round((A_TickCount - t0)/1000, 1) "s`n", "*")
            for r in res
                FileAppend(Format("    {:-10} {}  {} KB`n", r.label, r.ok ? "ok" : "FAIL", Round(r.bytes/1024)), "*")
            ExitApp(ok ? 0 : 1)
        } catch Error as e {
            FileAppend("[!] " e.Message "  | what=" e.What " file=" e.File ":" e.Line "`n" (e.Extra ? "    extra=" e.Extra "`n" : "") (e.Stack ? e.Stack "`n" : ""), "*")
            ExitApp(3)
        }
    }
    FileAppend("Usage: cli.ahk /list | /features | /build <profile> [key=value ...]`n", "*")
}

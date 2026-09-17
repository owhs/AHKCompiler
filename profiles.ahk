; ============================================================================
;  Profile storage - one INI, one section per profile, shared by GUI + CLI.
;  A profile fully describes a build or a compile.  kind=engine builds a reusable
;  AutoHotkey; kind=script bakes a given .ahk into that engine.
; ============================================================================
#Requires AutoHotkey v2.0

class ProfileStore {
    static Keys := [
        "kind", "description",
        "source_mode", "source_repo", "source_branch", "source_path",
        "arch", "optimize", "crt", "ltcg", "stringpool", "regex", "remove", "version",
        "exec_level", "console", "min_win",          ; targeting
        "extra_defines", "extra_cl", "extra_link",   ; escape hatches
        "targets",                                   ; engine
        "base_mode", "base_file",                     ; fast/prebuilt compile
        "script", "output", "clean_script",          ; script
        "company", "product", "filedesc", "fileversion", "copyright",
        "origfilename", "internalname", "trademarks",
        "icon_main", "icon_suspend", "icon_pause", "icon_pausesuspend", "icon_filetype",
        "payload_encrypt", "payload_compress", "iat_delayload", "iat_hooks", "scrub_strings",
        "compress_exe", "show_msbuild",
        "override_git", "override_msvc"
    ]
    static Defaults := Map(
        "kind", "engine", "description", "",
        "source_mode", "git",
        "source_repo", "https://github.com/AutoHotkey/AutoHotkey.git",
        "source_branch", "v2.0.19", "source_path", "",   ; the version 0001 patch was built against
        "arch", "x64", "optimize", "size", "crt", "os", "ltcg", "1", "stringpool", "1",
        "regex", "pcre", "remove", "", "version", "",
        "exec_level", "asInvoker", "console", "0", "min_win", "",
        "extra_defines", "", "extra_cl", "", "extra_link", "",
        "targets", "exe",
        "base_mode", "build", "base_file", "",
        "script", "", "output", "", "clean_script", "1",
        "company", "", "product", "", "filedesc", "", "fileversion", "", "copyright", "",
        "origfilename", "", "internalname", "", "trademarks", "",
        "icon_main", "", "icon_suspend", "", "icon_pause", "", "icon_pausesuspend", "", "icon_filetype", "",
        "payload_encrypt", "0", "payload_compress", "0", "iat_delayload", "0", "iat_hooks", "0", "scrub_strings", "0",
        "compress_exe", "none", "show_msbuild", "1",
        "override_git", "", "override_msvc", ""
    )
    static NumKeys := Map("ltcg",1,"stringpool",1,"console",1,"clean_script",1,"payload_encrypt",1,
        "payload_compress",1,"iat_delayload",1,"iat_hooks",1,"scrub_strings",1,"show_msbuild",1)

    __New(path) {
        this.path := path
        if !FileExist(path)
            this.SeedDefaults()
    }

    List() {
        names := []
        for s in StrSplit(IniRead(this.path), "`n")
            if (s := Trim(s)) != ""
                names.Push(s)
        return names
    }
    Has(name) {
        for n in this.List()
            if (n = name)
                return true
        return false
    }

    ; Returns a plain object with every key resolved against defaults.
    ToConfig(name) {
        cfg := { name: name }
        for key in ProfileStore.Keys {
            v := IniRead(this.path, name, key, "`f")
            if (v = "`f")
                v := ProfileStore.Defaults.Has(key) ? ProfileStore.Defaults[key] : ""
            if ProfileStore.NumKeys.Has(key)
                cfg.%key% := (v != "0" && v != "")
            else
                cfg.%key% := v
        }
        cfg.resources := this.LoadResources(name)
        return cfg
    }

    Save(name, data) {                 ; data: Map of key->value
        for key in ProfileStore.Keys
            if data.Has(key)
                IniWrite(data[key], this.path, name, key)
    }
    SaveConfig(name, cfg) {
        for key in ProfileStore.Keys {
            v := cfg.HasOwnProp(key) ? cfg.%key% : ""
            if (v = true)
                v := "1"
            else if (v = false)
                v := "0"
            IniWrite(v, this.path, name, key)
        }
    }
    Delete(name) => IniDelete(this.path, name)
    Duplicate(src, dest) {
        cfg := this.ToConfig(src)
        this.SaveConfig(dest, cfg)
        this.SaveResources(dest, cfg.resources)
    }

    LoadResources(name) {
        arr := [], n := Integer(IniRead(this.path, name, "resource_count", "0"))
        Loop n {
            r := "res" A_Index "_"
            arr.Push({
                Name:    IniRead(this.path, name, r "name", ""),
                Path:    IniRead(this.path, name, r "path", ""),
                Encrypt: IniRead(this.path, name, r "encrypt", "0") != "0",
                Compress:IniRead(this.path, name, r "compress", "0") != "0"
            })
        }
        return arr
    }
    SaveResources(name, arr) {
        Loop 64 {                       ; clear old
            r := "res" A_Index "_"
            try IniDelete(this.path, name, r "name")
        }
        IniWrite(arr.Length, this.path, name, "resource_count")
        for i, res in arr {
            r := "res" i "_"
            IniWrite(res.Name, this.path, name, r "name")
            IniWrite(res.Path, this.path, name, r "path")
            IniWrite(res.Encrypt ? 1 : 0, this.path, name, r "encrypt")
            IniWrite(res.Compress ? 1 : 0, this.path, name, r "compress")
        }
    }

    SeedDefaults() {
        seed := Map()
        seed["Engine: lean"]     := Map("kind","engine","description","All features, size-optimised, Windows 10/11 runtime.","optimize","size","crt","os")
        seed["Engine: lean (Win regex)"] := Map("kind","engine","description","Lean, with RegEx run by Windows ICU (drops bundled PCRE).","optimize","size","crt","os","regex","windows")
        seed["Engine: no COM/debug"] := Map("kind","engine","description","GUI kept; COM + debugger removed. Also builds the .bin base.","optimize","size","crt","os","remove","com,debugger","targets","exe,bin","version","2.0+lite")
        seed["Engine: tiny"]     := Map("kind","engine","description","Hotkeys/Send/files/strings/objects only.","arch","x64,x86","optimize","size","crt","os","remove","gui,com,debugger,regex,dllcall,registry,drive,sound,image,network","version","2.0+tiny")
        seed["Compile: script"]  := Map("kind","script","description","Compile a script into a custom-built engine (features, hardening).","optimize","size","crt","os","clean_script","1","iat_delayload","1","compress_exe","lzx")
        seed["Compile: fast (prebuilt)"] := Map("kind","script","description","Bake a script into the installed AutoHotkey - instant, no compiler (Ahk2Exe replacement).","base_mode","prebuilt","clean_script","1","compress_exe","lzx")
        for name, data in seed
            this.Save(name, data)
    }
}

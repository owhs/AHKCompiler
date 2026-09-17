# AHK2 Builder & Compiler

One app that both **builds a custom AutoHotkey v2 engine** and **compiles a script into a
standalone exe** — because they're the same job. Compiling is just building a self‑contained
engine with your script baked in, so both share one pipeline, one profile format, one window.

```
Acquire source ─▶ Apply profile (features + flags + regex backend) ─▶ [embed script]
             ─▶ MSBuild ─▶ post‑process (NTFS compress) ─▶ place output
```

## Requirements

- **Visual Studio Build Tools** with the *Desktop development with C++* workload (MSBuild + MSVC).
- **Git for Windows** (used to fetch source and to apply the feature patch). Without git the
  source is downloaded as a zip, but the feature patch still needs git.
- **AutoHotkey v2** to run the app itself.
- The **Windows RegEx backend** needs Windows 10 1903+ / Windows 11 (ships `icu.dll`).

## Run it

- Double‑click **`AHK2BC.cmd`** (or `AHK2BC.ahk`) for the GUI.
- Headless: `AHK2BC.cmd /build "Engine: lean"` · `AHK2BC.cmd /list` · `cli.ahk /features`.

Pick a profile on the left, flip **Build engine ⇄ Compile script** at the top, set options,
hit the big button. Everything auto‑saves to `data\profiles.ini`.

## Getting the source (auto-download)

For **Build from source** profiles, the AutoHotkey C++ source is fetched automatically — no
manual checkout. Set Source to **Git** (default: `AutoHotkey/AutoHotkey`, tag `v2.0.19`, which the
feature patch matches) and it clones on first build (LF checkout so the patch applies), caching it
under `build\`. If git isn't installed it falls back to downloading the branch zip. Or set Source
to **Local folder** to point at a checkout you already have (must be LF and the version the patch
targets). Only the build tools (VS Build Tools, git) aren't auto-installed — the Environment tab
detects them and tells you what's missing.

## Compile fast, or compile custom (two ways to compile)

A **Compile** profile has an **Engine base** choice on the Script tab:

- **Build from source (all features)** — compiles a custom engine with your stripped features,
  RegEx backend, hardening, metadata and icons, then bakes the script in. ~20-50 s, needs MSVC.
- **Prebuilt base — fast, no compiler** — bakes the script (and FileInstall/AddResource files)
  into an existing base exe with `UpdateResource`, exactly like Ahk2Exe. **~0.2 s, no compiler,
  no source.** If no base is set it uses your installed AutoHotkey (`v2\AutoHotkey64.exe`), so it
  works out of the box; point it at a custom `.bin` you built earlier to get stripped features
  *and* fast per-script compiles. This is the Ahk2Exe-replacement mode. **Version/assembly info,
  the main icon, extra resources and FileInstall all work here** (written into the exe the same way
  Ahk2Exe does). Still needs *Build from source*: feature stripping, the Windows RegEx backend,
  import-table hardening and scrub-strings; embedded-script encrypt/compress is skipped too (needs
  a matching compiled-in decoder).

## Intro wizard & focused UI

On launch (and via **New**) a short wizard asks what you want to do:

1. **Create a custom AHK binary** (engine)
2. **Create a custom binary + compile a script** (build from source)
3. **Compile a script (prebuilt base)** (fast, no compiler)

The choice sets the task and the window **greys out whatever doesn't apply** — the prebuilt task,
for instance, disables Source, compiler flags, Features and hardening, leaving script, base,
metadata, icons and resources. The **Task** buttons at the top switch mode any time.

## Two modes, one profile

| | Build engine | Compile script |
|---|---|---|
| Produces | `AutoHotkey64.exe` and/or the Ahk2Exe `.bin` base | a standalone `.exe` with your script inside |
| Output | `out\<profile>\` | next to the script (or a path you choose) |
| Extra tabs | — | Script, Metadata, Icons, Resources |

Both share: **Source, Features, Optimization, RegEx backend, Environment.**

## What you can strip (Features tab)

Measured on an x64 size‑optimised build. Removing a function makes scripts that call it fail
at load with a clear message — never a silent misbehaviour.

| Feature | Saves | Note |
|---|---:|---|
| Regular expressions | 151 KB | or keep them and switch the **backend to Windows** instead (below) |
| GUI (whole frame) | 90 KB | MsgBox/InputBox/ToolTip/Menu/tray stay |
| RegEx Unicode tables | 74 KB | keeps RegEx, drops `\p{…}` etc. (ignored when backend = Windows) |
| Script debugger (DBGp) | 43 KB | the `/Debug` hook |
| COM | 20 KB | removing it also removes ActiveX |
| GUI: ListView/TreeView/StatusBar | 11 KB | the *components*, frame kept |
| DllCall / CallbackCreate | 8 KB | |
| Registry · Image · Sound · Drive · Network · Process · Run | 2–6 KB each | Run = launch external programs; handy for locked‑down builds |
| **GUI: ActiveX only** | 1 KB | keep GUI *and* COM, drop just ActiveX |

Component granularity note: AutoHotkey's GUI weight lives in the shared window framework, not
the individual controls, so per‑control stripping saves little (~11 KB for all three advanced
controls). The big levers are RegEx, GUI, and the C runtime.

## Offloading to Windows instead of bundling

Two big chunks of a normal AutoHotkey build are third‑party/runtime code that Windows already
ships — so you can drop them from the exe and let the OS do the work:

- **RegEx → Windows ICU** (Optimization tab, *RegEx: Windows*). Drops the bundled PCRE (~130 KB)
  and runs `RegExMatch`/`RegExReplace`/`~=` on the OS ICU engine. The AHK API, match objects,
  named groups and the common option letters all keep working. Not supported by ICU: callouts
  `(?C)`, recursion `(?R)`/subroutines, the `(?U)` letter, and DFA mode — those raise a normal
  (catchable) compile error, exactly as ICU already rejects them.
- **C runtime → `ucrt.dll`** (Optimization tab, *C runtime: Windows 10/11*). Saves ~180 KB by
  using the OS Universal CRT instead of linking it statically.

Those are the only two large offloadable pieces — everything else in the binary is either
already calling OS APIs (GDI+ for images, `RtlDecompress` for the packed payload, etc.) or is
core interpreter/framework code that only *stripping* reduces.

## Ahk2Exe compatibility (FileInstall + directives)

The compiler injects the script and files into the built exe with `UpdateResource` —
the same way Ahk2Exe does — so existing scripts work unchanged:

- **`FileInstall "file", dest`** — the source is detected automatically, embedded, and
  extracted at runtime by AutoHotkey's normal mechanism. No configuration needed.
- **`;@Ahk2Exe-*` directives** are read from the script (and its includes) and applied:

  | Directive | Effect |
  |---|---|
  | `SetName` / `SetProductName` | Product name |
  | `SetDescription` / `SetFileDescription` | File description |
  | `SetCompanyName` | Company |
  | `SetCopyright` / `SetLegalCopyright` | Copyright |
  | `SetVersion` / `SetFileVersion` / `SetProductVersion` | Version info |
  | `SetOrigFilename` / `SetInternalName` / `SetLegalTrademarks` | Version‑info fields |
  | `SetMainIcon icon.ico` | Main icon |
  | `AddResource file [, NAME]` | Embed an extra resource |
  | `ExeName name` | Output file name |
  | `ConsoleApp` | Build as a console app |
  | `SetLanguage` / `UseResourceLang` | Recognised (resources stay language‑neutral) |

  `%A_ScriptName%`, `%A_ScriptDir%`, `%A_YYYY/MM/DD%` are expanded. Directives fill any
  field you left blank in the GUI (so an explicit GUI value wins). On the **Script** tab,
  *Auto‑fill from Ahk2Exe directives* (also run when you Browse for a script) pulls them
  into the Metadata / Icons / Resources tabs so you can see and tweak them before building.
  Unsupported directives (e.g. `Bin`, `Base`, `PostExec`, `Obey`) are ignored — the base is
  built here rather than selected.

## Targeting & hardening

On the **Build** tab (apply to both modes):

- **UAC level** — `asInvoker` / `requireAdministrator` / `highestAvailable` (stamped into the manifest).
- **Console app** — build as a console‑subsystem exe so `FileAppend "*"` prints to the parent
  console directly (the entry point is preserved, so the script still runs normally).
- **Min Windows** — stamp the subsystem version (Win7 6.1 / 8.1 6.3 / 10‑11 10.0). Pairs with
  *C runtime: Windows 10/11* for a clean modern‑only build.
- **Extra /D defines** — free‑form preprocessor symbols.

On the **Environment** tab: **Extra CL flags** and **Extra LINK flags** — raw escape hatches
appended to the compiler/linker command for anything not surfaced elsewhere.

Import‑table cleaning (Script tab), lowers naive AV false‑positives:

- **Delay‑load OS imports** — DLLs load on first use; most of the IAT disappears from static view.
- **Route OS imports via runtime resolution** — resolves selected APIs (`CreateFileW`,
  `LoadLibraryW`, `VirtualAllocEx`, `WriteProcessMemory`, `CreateToolhelp32Snapshot`, …) through
  `GetProcAddress` at run time, so they don't appear in the import table at all. Verified: those
  names are absent from the built exe's imports while the exe still runs normally.
- **Scrub signature strings** — white‑labels AutoHotkey markers in the binary.

## Compile‑only options

- **Packaging** (Script tab): strip comments, compress (LZNT1) and/or encrypt (RC4) the embedded
  script, delay‑load OS imports (cleaner import table, fewer AV false‑positives), NTFS‑compress
  the exe (`compact`, no packer). `FileInstall` sources are detected and embedded automatically.
- **Metadata / Icons / Resources**: version‑info fields, the five tray/file icons, and arbitrary
  extra RCDATA resources (optionally encrypted/compressed, read back at runtime).

## Files

- `AHK2BC.ahk` — the GUI. `cli.ahk` — headless entry. `core.ahk` — the engine (shared pipeline).
- `profiles.ahk` — profile storage. `data\features.ini`, `data\profiles.ini` — editable config.
- `patches\0001-feature-switches.patch` — the `#ifdef` switches added to the C++ source. With no
  features removed and the PCRE backend, a build is byte‑for‑byte identical to stock.
- `src-extra\regex_win.cpp` — the ICU RegEx backend, added to the build only when selected.
- `build\` — source cache + work tree (git‑ignored). `out\` — engine outputs (git‑ignored).

## New AutoHotkey versions (e.g. 2.1‑alpha)

The default source is pinned to **v2.0.19**, which the `0001` patch matches. To target another
line: set the profile's Source to that branch/tag (or a local folder). The app applies every
`patches\*.patch` in order, so support for a new line is additive — drop in a `0002‑v2.1a.patch`
next to `0001` and it's picked up automatically. If a patch can't apply, the app names the patch
and shows git's output so you can fix just the drifted hunks; the diff is small, self‑contained
`#ifdef` blocks. The RegEx backend and all build‑flag/metadata/packaging steps are version‑agnostic.

# AHKCompiler

A native AutoHotkey v2 compiler that automates the generation of standalone executables by interfacing directly with Git and MSBuild.

AHKCompiler clones the AutoHotkey C++ source tree, alters build configurations, embeds the target `.ahk` script into the Win32 resource table (`res_AutoHotkeySC.rc`), and builds a self-contained executable using MSVC.

## Features

* **Compiler Optimization Control**: UI-driven modification of MSVC architecture and build flags (`/O1` vs `/O2`). Supports toggling Link-Time Code Generation (LTCG), string pooling, and managing static versus dynamic C runtime (CRT) linking conventions.
* **Filesystem Compression**: Compresses output binaries utilizing native OS NTFS executable compression (`compact /exe:lzx`) rather than UPX. This minimizes file size while avoiding heuristic triggers common with executable packers.
* **Obfuscation and Execution Stripping**:
  * Utilizes OS-level delay-loaded DLLs (`/DELAYLOAD`) to manipulate the static Import Address Table (IAT).
  * Scrubs default AutoHotkey signature strings and standard error output to impede basic static analysis.
  * Conditionally injects null-returning C++ macros (`neuter.h`) to override explicit Win32 APIs (e.g., `OpenProcess`, `VirtualAllocEx`) to constrain script capability boundaries natively.
  * Evaluates and strips target AHK script comments, whitespace, and directives automatically before assembling, drastically minimizing `.rdata` payloads footprints.
  * Encrypts (RC4) and/or compresses (LZNT1) the standalone script payload and explicitly-targeted `.rsrc` custom assets natively into the MSVC build loops out of disk visibility.
  * Specifically injects an `AutoResourceLoader` layer directly at runtime creation, enabling target scripts to seamlessly and invisibly ingest encrypted assets into fast RAM structs without complex boilerplate wrappers.
* **Headless Integration**: Serializes configuration profiles to local `.ahkcompiler.ini` config files. Enables execution via CLI (`/build`) for implementation within CI/CD pipelines.

## Prerequisites

* **Git**: Required for fetching upstream AutoHotkey source branches.
* **MSVC Build Tools**: Requires `MSBuild.exe` alongside standard C++ MSVC workloads.

Custom absolute paths to both Git and MSBuild can be provided in the UI for environments that restrict or do not mutate global PATH variables.

## Structure

* `AHKCompiler.ahk`: Primary GUI frontend and build process automation.
* `benchmark_tool.ahk`: Optimization reference tool. Invokes headless compilation profiles against a target payload to verify MSVC build times, binary file size deltas, and process start-up/execution latency differences between optimization parameters.
* `Auto_Build.ahk`: Example script demonstrating the CLI parameters for headless remote invocation.

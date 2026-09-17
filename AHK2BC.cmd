@echo off
rem  AHK2 Builder & Compiler
rem    (no args)              open the GUI
rem    /list                  list profiles
rem    /build "<profile>"     build/compile headless
setlocal
set "AHK="
for %%p in (
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe"
  "%ProgramFiles%\AutoHotkey\AutoHotkey.exe"
) do if not defined AHK if exist "%%~p" set "AHK=%%~p"
if not defined AHK (
  echo Could not find AutoHotkey v2. Install it from https://autohotkey.com
  exit /b 1
)
if "%~1"=="" (
  start "" "%AHK%" "%~dp0AHK2BC.ahk"
) else (
  "%AHK%" "%~dp0cli.ahk" %*
)

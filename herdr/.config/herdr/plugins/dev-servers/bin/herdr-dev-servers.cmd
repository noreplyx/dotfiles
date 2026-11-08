@echo off
setlocal
set "SUBCOMMAND=%~1"
set "NORMALIZED_FLAG="

if "%SUBCOMMAND%"=="" set "NORMALIZED_FLAG=--open"
if /I "%SUBCOMMAND%"=="daemon" set "NORMALIZED_FLAG=--daemon"
if /I "%SUBCOMMAND%"=="--daemon" set "NORMALIZED_FLAG=--daemon"
if /I "%SUBCOMMAND%"=="open" set "NORMALIZED_FLAG=--open"
if /I "%SUBCOMMAND%"=="--open" set "NORMALIZED_FLAG=--open"
if /I "%SUBCOMMAND%"=="stop" set "NORMALIZED_FLAG=--stop"
if /I "%SUBCOMMAND%"=="--stop" set "NORMALIZED_FLAG=--stop"
if /I "%SUBCOMMAND%"=="pane" set "NORMALIZED_FLAG=--pane"
if /I "%SUBCOMMAND%"=="--pane" set "NORMALIZED_FLAG=--pane"
if /I "%SUBCOMMAND%"=="scan" set "NORMALIZED_FLAG=--scan"
if /I "%SUBCOMMAND%"=="--scan" set "NORMALIZED_FLAG=--scan"
if /I "%SUBCOMMAND%"=="badge" set "NORMALIZED_FLAG=--badge"
if /I "%SUBCOMMAND%"=="--badge" set "NORMALIZED_FLAG=--badge"
if /I "%SUBCOMMAND%"=="help" set "NORMALIZED_FLAG=--help"
if /I "%SUBCOMMAND%"=="-h" set "NORMALIZED_FLAG=--help"
if /I "%SUBCOMMAND%"=="--help" set "NORMALIZED_FLAG=--help"

if "%NORMALIZED_FLAG%"=="" (
  echo herdr-dev-servers: unknown subcommand: %SUBCOMMAND% >&2
  echo usage: herdr-dev-servers [daemon^|open^|stop^|pane^|scan^|badge^|--help] >&2
  exit /b 1
)

if /I "%NORMALIZED_FLAG%"=="--pane" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\dev-servers.ps1" "%NORMALIZED_FLAG%" "%~2"
  exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\dev-servers.ps1" "%NORMALIZED_FLAG%" "%~2"
exit /b %ERRORLEVEL%

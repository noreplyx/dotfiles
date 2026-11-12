@echo off
setlocal
set "RAW_TARGET=%~1"
set "WORKSPACE_ID=%~2"
if "%RAW_TARGET%"=="" goto :no_repo
if "%RAW_TARGET%"=="-" goto :no_repo
if "%WORKSPACE_ID%"=="-" goto :no_repo

set "TARGET=%RAW_TARGET%"
if "%TARGET%"=="~" set "TARGET=%USERPROFILE%"
if "%TARGET:~0,2%"=="~/" set "TARGET=%USERPROFILE%\%TARGET:~2%"
if "%TARGET:~0,2%"=="~\" set "TARGET=%USERPROFILE%\%TARGET:~2%"

if not exist "%TARGET%" (
    echo Directory not found: %RAW_TARGET%
    exit /b 0
)
git -C "%TARGET%" rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
    echo Not a git repository: %RAW_TARGET%
    exit /b 0
)
git -C "%TARGET%" log -1 --format="Commit: %%h | Date: %%cd (%%cr) | Author: %%an" 2>nul
echo.
git -C "%TARGET%" status -s --ignore-submodules=all 2>nul
echo.
git -C "%TARGET%" log -n 6 --graph --format="%%C(auto)%%h%%d %%s %%C(cyan)(%%cr)%%C(reset)" --color=always 2>nul
exit /b 0

:no_repo
echo No active git repositories found in Herdr workspaces.
echo Open a project with a Git repository in Herdr or create a worktree.
exit /b 0

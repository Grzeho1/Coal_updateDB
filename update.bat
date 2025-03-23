@echo off
setlocal enabledelayedexpansion

:: Načtení proměnných z .env souboru
if not exist "%~dp0config.env" (
    echo [error] Soubor config.env nebyl nalezen!
    pause
    exit /b 1
)

for /f "usebackq tokens=1,2 delims==" %%A in ("%~dp0config.env") do (
    set "%%A=%%B"
)

:: Aktuální složka
set "repoPath=%~dp0"
set "repoPath=!repoPath:~0,-1!"
set "sqlPath=%repoPath%\sql"
set "tempClonePath=%repoPath%\__temp_git"

echo [info] Cloning repo...
git clone https://%GIT_USER%:%GIT_TOKEN%@github.com/%GIT_USER%/%GIT_REPO%.git "%tempClonePath%"

echo [info] Copying sql files...
robocopy "%tempClonePath%\sql" "%sqlPath%" /E /NFL /NDL /NJH /NJS /nc /ns /np

echo [info] Cleaning up temp...
rmdir /s /q "%tempClonePath%"

echo [info] Running update script...
powershell.exe -ExecutionPolicy Bypass -File "%repoPath%\run_update.ps1"
pause

@echo off
setlocal enabledelayedexpansion

:: Načtení proměnných z .env
if not exist "%~dp0config.env" (
    echo [error] Soubor config.env nebyl nalezen!
    pause
    exit /b 1
)

for /f "usebackq tokens=1,2 delims==" %%A in ("%~dp0config.env") do (
    set "%%A=%%B"
)


set "repoPath=%~dp0"
set "repoPath=!repoPath:~0,-1!"
set "sqlPath=%repoPath%\sql"
set "tempClonePath=%repoPath%\__temp_git"

echo.
echo ========================================
echo   Vyberte SQL slozku:
echo ========================================
echo 1) Shoptet_SQL
echo 2) Univerzal_SQL
echo ========================================
set /p choice="Zadejte 1 nebo 2: "

if "%choice%"=="1" (
    set "sqlFolder=Shoptet_SQL"
    echo [info] Vybrano: Shoptet_SQL
) else if "%choice%"=="2" (
    set "sqlFolder=Univerzal_SQL"
    echo [info] Vybrano: Univerzal_SQL
) else (
    echo [error] Neplatna volba!
    pause
    exit /b 1
)

echo [info] Cloning repo...
git clone https://%GIT_USER%:%GIT_TOKEN%@github.com/%GIT_USER%/%GIT_REPO%.git "%tempClonePath%"

echo [info] Copying sql files from !sqlFolder!...
robocopy "%tempClonePath%\!sqlFolder!" "%sqlPath%" /E /NFL /NDL /NJH /NJS /nc /ns /np

echo [info] Cleaning up temp...
rmdir /s /q "%tempClonePath%"

echo [info] Running update script...
powershell.exe -ExecutionPolicy Bypass -File "%repoPath%\run_update.ps1"
pause

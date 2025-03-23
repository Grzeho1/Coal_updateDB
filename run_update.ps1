# ===============================================
# Script: run_update.ps1
# Description: Executes sorted SQL scripts using config from .env
# ===============================================

# Načtení proměnných z .env souboru
$envFile = "$PSScriptRoot\config.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: config.env not found!" -ForegroundColor Red
    exit 1
}

# Parsování .env souboru
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.+)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Item -Path "env:$name" -Value $value
    }
}

# Cesta ke složce se skripty
$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlFolder = "$repoPath\sql"

# Připojovací údaje
$server = $env:DB_SERVER
$database = $env:DB_NAME
$dbUser = $env:DB_USER
$dbPassword = $env:DB_PASSWORD

# Výpis základních info
Write-Host "========================================"
Write-Host "         Starting SQL update            "
Write-Host "========================================"
$start = Get-Date

# Kontrola složky sql
if (-not (Test-Path $sqlFolder)) {
    Write-Host "ERROR: Folder 'sql' does not exist. Run update.bat first." -ForegroundColor Red
    exit 1
}

# Načtení a seřazení skriptů podle prefixu
$sqlFiles = Get-ChildItem -Path $sqlFolder -Filter *.sql |
    Where-Object { $_.Name -match "^\d+" } |
    Sort-Object { [int]($_.Name -replace "^(\d+).*", '$1') }

$executedCount = 0
$executedScripts = @()

# Sestavení přihlašovacího řetězce
if ($dbUser -and $dbPassword) {
    $auth = "-U `"$dbUser`" -P `"$dbPassword`""
} else {
    $auth = "-E"  # Windows autentizace
}

foreach ($file in $sqlFiles) {
    $fileName = $file.Name
    Write-Host "`nSpouštím: $fileName" -ForegroundColor Cyan
    $command = "sqlcmd -S `"$server`" -d `"$database`" $auth -i `"$($file.FullName)`""
    Invoke-Expression $command

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Hotovo: $fileName" -ForegroundColor Green
        $executedScripts += $fileName
        $executedCount++
    } else {
        Write-Host ""
        Write-Host "CHYBA: Nepodařilo se spustit skript: $fileName" -ForegroundColor Red
        Write-Host "----------------------------------------" -ForegroundColor DarkRed
        Write-Host "Náhled skriptu (prvních 10 řádků):" -ForegroundColor DarkGray
        Get-Content $file.FullName -TotalCount 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Write-Host "----------------------------------------" -ForegroundColor DarkRed
        break
    }
}

$end = Get-Date
$duration = $end - $start

# Závěrečný výstup
Write-Host "`n========================================"
Write-Host "              Dokončeno                 "
Write-Host "========================================"
Write-Host "Spuštěno skriptů celkem: $executedCount" -ForegroundColor Yellow

if ($executedCount -gt 0) {
    Write-Host "Seznam spuštěných skriptů:" -ForegroundColor Yellow
    foreach ($script in $executedScripts) {
        Write-Host " - $script" -ForegroundColor DarkCyan
    }
} else {
    Write-Host "Nebyly spuštěny žádné nové skripty." -ForegroundColor DarkYellow
}

Write-Host "Celkový čas běhu: $($duration.TotalSeconds) sekund."

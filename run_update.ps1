# Path to the folder where this script is located
$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlFolder = "$repoPath\sql"
$server = "DESKTOP-FUQ15OI\SQLEXPRESS"
$database = "testovaci"

Write-Host "========================================"
Write-Host "         Starting SQL update            "
Write-Host "========================================"
$start = Get-Date

# Check if the 'sql' folder exists
if (-not (Test-Path $sqlFolder)) {
    Write-Host "ERROR: Folder 'sql' does not exist. Please run update.bat first." -ForegroundColor Red
    exit
}

# Get and sort SQL files based on numeric prefix
$sqlFiles = Get-ChildItem -Path $sqlFolder -Filter *.sql |
    Where-Object { $_.Name -match "^\d+" } |
    Sort-Object { [int]($_.Name -replace "^(\d+).*", '$1') }

$executedCount = 0
$executedScripts = @()

foreach ($file in $sqlFiles) {
    $fileName = $file.Name
    Write-Host "`nRunning: $fileName" -ForegroundColor Cyan
    $command = "sqlcmd -S `"$server`" -d `"$database`" -i `"$($file.FullName)`""
    Invoke-Expression $command

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Completed: $fileName" -ForegroundColor Green
        $executedScripts += $fileName
        $executedCount++
    } else {
        Write-Host ""
        Write-Host "ERROR: Execution failed for script: $fileName" -ForegroundColor Red
        Write-Host "----------------------------------------" -ForegroundColor DarkRed
        Write-Host "Script preview (first 10 lines):" -ForegroundColor DarkGray
        Get-Content $file.FullName -TotalCount 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Write-Host "----------------------------------------" -ForegroundColor DarkRed
        break
    }
}

$end = Get-Date
$duration = $end - $start

Write-Host "`n========================================"
Write-Host "               Finished                  "
Write-Host "========================================"
Write-Host "Executed scripts count: $executedCount" -ForegroundColor Yellow

if ($executedCount -gt 0) {
    Write-Host "List of executed scripts:" -ForegroundColor Yellow
    foreach ($script in $executedScripts) {
        Write-Host " - $script" -ForegroundColor DarkCyan
    }
} else {
    Write-Host "No new scripts were executed." -ForegroundColor DarkYellow
}

Write-Host "Total execution time: $($duration.TotalSeconds) seconds."

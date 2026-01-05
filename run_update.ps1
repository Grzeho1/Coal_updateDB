# ===============================================
# Script: run_update.ps1
# ===============================================

function Ensure-ODBCDriver17 {
    $driverInstalled = Get-OdbcDriver | Where-Object { $_.Name -eq "ODBC Driver 17 for SQL Server" }
    if ($driverInstalled) {
        Write-Host "ODBC Driver 17 for SQL Server je jiz nainstalovan."
        return
    }

    Write-Host "ODBC Driver 17 nenalezen, stahuji a instaluji..."
    $downloadPath = "$env:TEMP\ODBC_Driver_17.msi"
    $url = "https://go.microsoft.com/fwlink/?linkid=2249005"

    try {
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -ErrorAction Stop
        if (Test-Path $downloadPath) {
            Write-Host "Stazeni dokonceno, instaluji..."
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$downloadPath`" /quiet /norestart" -Wait -NoNewWindow
            Write-Host "Instalace ODBC Driver 17 dokoncena."
        }
    } catch {
        Write-Host "Chyba pri stahovani nebo instalaci ovladace: $_" -ForegroundColor Red
        exit 1
    }
}

$envFile = "$PSScriptRoot\config.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: config.env not found!" -ForegroundColor Red
    exit 1
}

Write-Host "=== Nacitam config.env ==="
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*)$") {
        $name = $matches[1].Trim()
        $value = $matches[2]
        Set-Item -Path "env:$name" -Value $value
        Write-Host "$name = $value"
    }
}

$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlFolder = "$repoPath\sql"

$server = $env:DB_SERVER
$database = $env:DB_NAME
$dbUser = $env:DB_USER
$dbPassword = $env:DB_PASSWORD

Ensure-ODBCDriver17

Write-Host "`n" ("=" * 60) -ForegroundColor Cyan
Write-Host "               SQL DATABASE UPDATE TOOL" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host " Server  : " -NoNewline; Write-Host $server -ForegroundColor Yellow
Write-Host " Database: " -NoNewline; Write-Host $database -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
$start = Get-Date

if (-not (Test-Path $sqlFolder)) {
    Write-Host "`n[X] CHYBA: Slozka 'sql' neexistuje. Spustte nejdrive update.bat" -ForegroundColor Red
    exit 1
}

$sqlFiles = Get-ChildItem -Path $sqlFolder -Filter *.sql |
    Where-Object { $_.Name -match "^\d+" } |
    Sort-Object { [int]($_.Name -replace "^(\d+).*", '$1') }

$totalFiles = $sqlFiles.Count
Write-Host "`n[i] Nalezeno " -NoNewline
Write-Host "$totalFiles" -ForegroundColor Cyan -NoNewline
Write-Host " SQL skriptu k provedeni`n"

$executedCount = 0
$executedScripts = @()
$alreadyExistsCount = 0
$importedCount = 0
$otherErrorsCount = 0
$otherErrorsDetails = @()

if ($dbUser -and $dbPassword) {
    $auth = "-U `"$dbUser`" -P `"$dbPassword`""
} else {
    $auth = "-E"
}

$currentNum = 0
foreach ($file in $sqlFiles) {
    $currentNum++
    $fileName = $file.Name
    
    Write-Host ("[{0}/{1}] " -f $currentNum, $totalFiles) -NoNewline -ForegroundColor Gray
    Write-Host $fileName -NoNewline -ForegroundColor White
    Write-Host " ... " -NoNewline

    $command = "sqlcmd -S `"$server`" -d `"$database`" $auth -i `"$($file.FullName)`""
    $output = & cmd.exe /c $command 2>&1
    $exitCode = $LASTEXITCODE

    $errorDetected = $output | Where-Object { $_ -match "Msg \d+, Level \d+, State \d+" }
    $errorMessage = ($output -join "`n")

    if ($exitCode -eq 0 -and -not $errorDetected) {
        Write-Host "[OK]" -ForegroundColor Green
        $importedCount++
        $executedScripts += $fileName
        $executedCount++
    } else {
        $alreadyExists = $errorMessage -match "Msg 2714"
        if ($alreadyExists) {
            Write-Host "[EXISTUJE]" -ForegroundColor DarkYellow
            $alreadyExistsCount++
        } else {
            Write-Host "[CHYBA]" -ForegroundColor Red
            Write-Host "      |_ Error: " -NoNewline -ForegroundColor DarkRed
            $firstError = ($errorMessage -split "`n" | Where-Object { $_ -match "Msg \d+" } | Select-Object -First 1)
            Write-Host $firstError -ForegroundColor DarkRed

            $otherErrorsDetails += [PSCustomObject]@{
                FileName = $fileName
                ErrorMessage = $errorMessage
            }
            $otherErrorsCount++
        }
        $executedScripts += $fileName
        $executedCount++
    }
}

$end = Get-Date
$duration = $end - $start

$logFolder = Join-Path $repoPath "Logs"
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder | Out-Null
}

$logPath = Join-Path $logFolder "errors.log"
"Chyby :- $(Get-Date)" | Out-File -FilePath $logPath -Encoding UTF8

Write-Host "`n" ("=" * 60) -ForegroundColor Cyan
Write-Host "                  VYSLEDKY PROVEDENI" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Progress bar
$successRate = if ($totalFiles -gt 0) { [math]::Round(($importedCount / $totalFiles) * 100) } else { 0 }
$barLength = 40
$filledLength = [math]::Round(($successRate / 100) * $barLength)
$bar = ("#" * $filledLength) + ("-" * ($barLength - $filledLength))
Write-Host " Progress: [" -NoNewline
Write-Host $bar -NoNewline -ForegroundColor Green
Write-Host "] $successRate%"

Write-Host "`n Celkem skriptu    : " -NoNewline; Write-Host $totalFiles -ForegroundColor White
Write-Host " Uspesne provedeno : " -NoNewline; Write-Host $importedCount -ForegroundColor Green
Write-Host " Jiz existuji      : " -NoNewline; Write-Host $alreadyExistsCount -ForegroundColor Yellow
Write-Host " Chyby             : " -NoNewline; Write-Host $otherErrorsCount -ForegroundColor Red

if ($otherErrorsCount -gt 0) {
    Write-Host "`n" ("=" * 60) -ForegroundColor DarkRed
    Write-Host "   !!! SKRIPTY K RESENI - NALEZENY CHYBY !!!" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor DarkRed
    Write-Host ""
    
    $errNum = 1
    foreach ($err in $otherErrorsDetails) {
        Write-Host " [$errNum] " -NoNewline -ForegroundColor Red
        Write-Host $err.FileName -ForegroundColor Yellow
        
        # Extrahování prvního error message
        $errorLines = $err.ErrorMessage -split "`n"
        $msgLine = $errorLines | Where-Object { $_ -match "Msg \d+" } | Select-Object -First 1
        $descLine = $errorLines | Where-Object { $_ -match "Invalid|Cannot|The|Error" -and $_ -notmatch "Msg \d+" } | Select-Object -First 1
        
        if ($msgLine) {
            Write-Host "     Chyba   : " -NoNewline -ForegroundColor Gray
            Write-Host $msgLine.Trim() -ForegroundColor DarkYellow
        }
        if ($descLine) {
            Write-Host "     Popis   : " -NoNewline -ForegroundColor Gray
            Write-Host $descLine.Trim() -ForegroundColor White
        }
        Write-Host "     Cesta   : " -NoNewline -ForegroundColor Gray
        Write-Host "$sqlFolder\$($err.FileName)" -ForegroundColor Cyan
        Write-Host ""
        
        $errNum++
        
        # Zápis do log souboru
        Add-Content -Path $logPath -Value "Skript: $($err.FileName)"
        Add-Content -Path $logPath -Value "Chyba: $($err.ErrorMessage)"
        Add-Content -Path $logPath -Value "----------------------------------------`n"
    }
    
    Write-Host ("-" * 60) -ForegroundColor DarkRed
    Write-Host " [!] AKCE: Prosim zkontrolujte tyto " -NoNewline -ForegroundColor Yellow
    Write-Host "$otherErrorsCount" -NoNewline -ForegroundColor Red
    Write-Host " skript(u)" -ForegroundColor Yellow
    Write-Host " [i] Detailni log: " -NoNewline -ForegroundColor Gray
    Write-Host $logPath -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor DarkRed
}

Write-Host "`n" ("-" * 60) -ForegroundColor Gray
Write-Host " Cas behu: " -NoNewline
Write-Host ("{0:N2} sekund" -f $duration.TotalSeconds) -ForegroundColor Magenta
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

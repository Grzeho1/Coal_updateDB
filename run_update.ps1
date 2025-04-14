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
        Write-Host "Chyba pri stahovani nebo instalaci ovladace: $_"
        exit 1
    }
}

$envFile = "$PSScriptRoot\config.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: config.env not found!"
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

Write-Host "========================================"
Write-Host "         Starting SQL update            "
Write-Host "========================================"
$start = Get-Date

if (-not (Test-Path $sqlFolder)) {
    Write-Host "ERROR: Folder 'sql' does not exist. Run update.bat first."
    exit 1
}

$sqlFiles = Get-ChildItem -Path $sqlFolder -Filter *.sql |
    Where-Object { $_.Name -match "^\d+" } |
    Sort-Object { [int]($_.Name -replace "^(\d+).*", '$1') }

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

foreach ($file in $sqlFiles) {
    $fileName = $file.Name
    Write-Host "\n[INFO] Running script: $fileName"

    $command = "sqlcmd -S `"$server`" -d `"$database`" $auth -i `"$($file.FullName)`""
    $output = & cmd.exe /c $command 2>&1
    $exitCode = $LASTEXITCODE

    $errorDetected = $output | Where-Object { $_ -match "Msg \d+, Level \d+, State \d+" }
    $errorMessage = ($output -join "`n")

    if ($exitCode -eq 0 -and -not $errorDetected) {
        Write-Host "[SUCCESS] Script executed successfully."
        $importedCount++
    } else {
        $alreadyExists = $errorMessage -match "Msg 2714"
        if ($alreadyExists) {
            Write-Host "[WARNING] Script already exists: $fileName"
            $alreadyExistsCount++
        } else {
            Write-Host "[ERROR] Failed to run script: $fileName"
            Write-Host "        Error message:"
            Write-Host "$errorMessage"

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
"Chyby ze spusteni skriptu - $(Get-Date)" | Out-File -FilePath $logPath -Encoding UTF8

Write-Host "\n========================================"
Write-Host "              Dokonceno                 "
Write-Host "========================================"
Write-Host "Spusteno skriptu celkem: $executedCount"

if ($executedCount -gt 0) {
    Write-Host "Seznam spustenych skriptu:"
    foreach ($script in $executedScripts) {
        Write-Host " - $script"
    }
} else {
    Write-Host "Nebyly spusteny zadne nove skripty."
}

Write-Host "\n=== Souhrn vysledku ==="
Write-Host "Uspech: $importedCount"
Write-Host "Jiz existuje: $alreadyExistsCount"
Write-Host "Jine chyby: $otherErrorsCount"

if ($otherErrorsCount -gt 0) {
    Write-Host "\n=== Detaily chyb ==="
 foreach ($err in $otherErrorsDetails) {
      
        # Zápis do log souboru
        Add-Content -Path $logPath -Value "Skript: $($err.FileName)"
        Add-Content -Path $logPath -Value "Chyba: $($err.ErrorMessage)"
        Add-Content -Path $logPath -Value "----------------------------------------`n"
    }
       Write-Host "\nDetailni log chyb byl ulozen do: $logPath"
}

Write-Host "Cas behu: $($duration.TotalSeconds) sekund."

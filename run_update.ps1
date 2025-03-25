# ===============================================
# Script: run_update.ps1
# Description: Executes sorted SQL scripts using config from .env
# ===============================================

# Funkce pro kontrolu a stažení ODBC Driver 17
function Ensure-ODBCDriver17 {
    $driverInstalled = Get-OdbcDriver | Where-Object { $_.Name -eq "ODBC Driver 17 for SQL Server" }
    if ($driverInstalled) {
        Write-Host "ODBC Driver 17 for SQL Server je již nainstalován." -ForegroundColor Green
        return
    }

    Write-Host "ODBC Driver 17 nenalezen, stahuji a instaluji..." -ForegroundColor Yellow
    $downloadPath = "$env:TEMP\ODBC_Driver_17.msi"
    $url = "https://go.microsoft.com/fwlink/?linkid=2249005"  # x64 verze

    try {
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -ErrorAction Stop
        if (Test-Path $downloadPath) {
            Write-Host "Stažení dokončeno, instaluji..." -ForegroundColor Cyan
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $downloadPath /quiet /norestart" -Wait -NoNewWindow
            Write-Host "Instalace ODBC Driver 17 dokončena." -ForegroundColor Green
        }
    } catch {
        Write-Host "Chyba při stahování nebo instalaci ovladače: $_" -ForegroundColor Red
        exit 1
    }
}

# Načtení.env
$envFile = "$PSScriptRoot\config.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: config.env not found!" -ForegroundColor Red
    exit 1
}


Write-Host "=== Načítám config.env ===" -ForegroundColor Magenta
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.*)$") {
        $name = $matches[1].Trim()
        $value = $matches[2]
        Set-Item -Path "env:$name" -Value $value
        Write-Host "$name = $value" -ForegroundColor Magenta
    }
}

# skripty sql
$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlFolder = "$repoPath\sql"

# Připojovací údaje
$server = $env:DB_SERVER
$database = $env:DB_NAME
$dbUser = $env:DB_USER
$dbPassword = $env:DB_PASSWORD

# Kontrola oDBC Driver 17
Ensure-ODBCDriver17

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
$alreadyExistsCount = 0
$importedCount = 0
$otherErrorsCount = 0
$otherErrorsDetails = @() 

# přihlašovací řetězec
if ($dbUser -and $dbPassword) {
    $auth = "-U `"$dbUser`" -P `"$dbPassword`""
} else {
    $auth = "-E"  # Windows autentizace
}

foreach ($file in $sqlFiles) {
    $fileName = $file.Name
    Write-Host "`nSpouštím: $fileName" -ForegroundColor Cyan
    
    # Spuštění sqlcmd přes CMD a zachycení výstupu
    $command = "sqlcmd -S `"$server`" -d `"$database`" $auth -i `"$($file.FullName)`""
    Write-Host "Příkaz: $command" -ForegroundColor Yellow
    
    $output = & cmd.exe /c $command 2>&1  # stdout i stderr
    $exitCode = $LASTEXITCODE

    # Kontrola výstupu na chybové zprávy
   $errorDetected = $output | Where-Object { $_ -match "Msg \d+, Level \d+, State \d+" }
$errorMessage = ($errorDetected -join "`n")

if ($exitCode -eq 0 -and -not $errorDetected) {
    # OK
} else {
    $alreadyExists = $errorMessage -match "Msg 2714"
    if ($alreadyExists) {
        Write-Host "Již existuje: $fileName" -ForegroundColor Yellow
        $alreadyExistsCount++
    } else {
        Write-Host "CHYBA: Nepodařilo se spustit skript: $fileName" -ForegroundColor Red
        Write-Host "Exit Code: $exitCode" -ForegroundColor Red
        if ($errorDetected) {
            Write-Host "`nSQL chyba detekována:" -ForegroundColor Red
            Write-Host "$errorMessage" -ForegroundColor Red

            if ($errorMessage -match "Msg 208") {
                Write-Host "Poznámka: Objekt, na který skript odkazuje, pravděpodobně neexistuje." -ForegroundColor DarkYellow
            }

            if ($errorMessage -match "Msg 262") {
                Write-Host "Poznámka: Uživateli chybí oprávnění k objektu nebo akci." -ForegroundColor DarkYellow
            }

            if ($errorMessage -match "Msg 515") {
                Write-Host "Poznámka: Pravděpodobně NULL hodnota do povinného sloupce." -ForegroundColor DarkYellow
            }

            # Uložení detailů chyby
            $otherErrorsDetails += [PSCustomObject]@{
                FileName = $fileName
                ErrorMessage = $errorMessage
            }
        }
        $otherErrorsCount++
    }

    $executedScripts += $fileName
    $executedCount++
}

}

$end = Get-Date
$duration = $end - $start

# Vytvoření složky Logs, pokud neexistuje
$logFolder = Join-Path $repoPath "Logs"
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder | Out-Null
}

# Cesta k log souboru
$logPath = Join-Path $logFolder "errors.log"
"Chyby ze spuštění skriptů - $(Get-Date)" | Out-File -FilePath $logPath -Encoding UTF8

# Výstup souhrnu do konzole
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

# Souhrn výsledků
Write-Host "`n=== Souhrn výsledků ===" -ForegroundColor Cyan
Write-Host "Úspěšně importováno: $importedCount" -ForegroundColor Green
Write-Host "Již existuje v databázi: $alreadyExistsCount" -ForegroundColor Yellow
Write-Host "Skripty s jinými chybami: $otherErrorsCount" -ForegroundColor Red


if ($otherErrorsCount -gt 0) {
    Write-Host "`n=== Detaily skriptů s chybami ===" -ForegroundColor Red
    foreach ($err in $otherErrorsDetails) {
        Write-Host "Skript: $($err.FileName)" -ForegroundColor Red
        Write-Host "Chyba: $($err.ErrorMessage)" -ForegroundColor Red
        Write-Host "----------------------------------------" -ForegroundColor DarkRed

        # Zápis do log souboru
        Add-Content -Path $logPath -Value "Skript: $($err.FileName)"
        Add-Content -Path $logPath -Value "Chyba: $($err.ErrorMessage)"
        Add-Content -Path $logPath -Value "----------------------------------------`n"
    }

    Write-Host "`nDetailní log chyb byl uložen do: $logPath" -ForegroundColor Cyan
}

Write-Host "Celkový čas běhu: $($duration.TotalSeconds) sekund." -ForegroundColor Cyan

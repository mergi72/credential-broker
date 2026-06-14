param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker"
)

$ErrorActionPreference = "Stop"

$installRoot = if (Test-Path $InstallRoot) { (Resolve-Path $InstallRoot).Path } else { $InstallRoot }
$machineConfigDir = Join-Path $installRoot "config"
$logDir = Join-Path $installRoot "logs"
$userConfigDir = Join-Path $env:APPDATA "Credential Broker\config"
$installLogPath = Join-Path $logDir "installer.log"

function Write-InstallLog {
    param(
        [ValidateSet("INFO", "STEP", "OK", "ERROR")]
        [string]$Level,
        [string]$Message
    )

    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $installLogPath -Value $line -Encoding UTF8
}

function Write-Step {
    param([string]$Message)
    Write-InstallLog -Level "STEP" -Message $Message
}

function Write-Info {
    param([string]$Message)
    Write-InstallLog -Level "INFO" -Message $Message
}

function Write-Ok {
    param([string]$Message)
    Write-InstallLog -Level "OK" -Message $Message
}

function Write-ErrorLog {
    param([string]$Message)
    Write-InstallLog -Level "ERROR" -Message $Message
}

trap {
    Write-ErrorLog $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-ErrorLog $_.ScriptStackTrace
    }
    throw
}

Write-Step "Preparing Credential Broker directory structure..."

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
New-Item -ItemType Directory -Path $machineConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null

Write-Info "Install root: $installRoot"
Write-Info "Machine config: $machineConfigDir"
Write-Info "User config: $userConfigDir"
Write-Info "Log directory: $logDir"
Write-Info "Installer log: $installLogPath"

$requiredFiles = @(
    (Join-Path $installRoot "credential-broker.exe"),
    (Join-Path $installRoot "config\broker.json")
)

foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path $requiredFile)) {
        throw "Required installed file not found: $requiredFile"
    }
    Write-Ok "Installed file found: $requiredFile"
}

Write-Ok "Credential Broker directory structure prepared."

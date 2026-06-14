param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker",
    [string]$HealthUrl = "http://127.0.0.1:8776/health",
    [int]$HealthTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Write-InstallLog {
    param(
        [ValidateSet("INFO", "STEP", "OK")]
        [string]$Level,
        [string]$Message
    )

    Write-Host ("[{0,-5}] {1}" -f $Level, $Message)
}

function Write-Info {
    param([string]$Message)
    Write-InstallLog -Level "INFO" -Message $Message
}

function Write-Step {
    param([string]$Message)
    Write-InstallLog -Level "STEP" -Message $Message
}

function Write-Ok {
    param([string]$Message)
    Write-InstallLog -Level "OK" -Message $Message
}

function Wait-BrokerHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    Write-Step "Waiting for Credential Broker health..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 5
            if ($response.ok -eq $true -or $response.status -eq "ok" -or $response.service) {
                Write-Ok "GET $Url"
                return
            }
        }
        catch {
            # Broker can still be starting.
        }

        Start-Sleep -Seconds 1
    }

    throw "Credential Broker health check did not pass within $TimeoutSeconds s: $Url"
}

$installRoot = (Resolve-Path $InstallRoot).Path
$machineConfigDir = Join-Path $installRoot "config"
$userConfigDir = Join-Path $env:APPDATA "Credential Broker\config"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Credential Broker.lnk"
$startScript = Join-Path $installRoot "start-credential-broker.ps1"
$exePath = Join-Path $installRoot "credential-broker.exe"

Write-Step "Preparing Credential Broker local install..."

if (-not (Test-Path $exePath)) {
    throw "Credential Broker executable not found: $exePath"
}

if (-not (Test-Path $startScript)) {
    throw "Credential Broker start script not found: $startScript"
}

New-Item -ItemType Directory -Path $machineConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installRoot "logs") -Force | Out-Null

Write-Step "Setting user environment..."
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $machineConfigDir, "User")
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $userConfigDir, "User")
$env:CREDENTIAL_BROKER_MACHINE_CONFIG_DIR = $machineConfigDir
$env:CREDENTIAL_BROKER_USER_CONFIG_DIR = $userConfigDir
Write-Ok "Credential Broker config environment updated."

Write-Step "Creating user Startup shortcut..."
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`""
$shortcut.WorkingDirectory = $installRoot
$shortcut.Save()
Write-Ok $shortcutPath

Write-Step "Starting Credential Broker..."
$existing = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -ieq $exePath }

if ($existing) {
    Write-Ok "Credential Broker already running."
}
else {
    Start-Process -FilePath $exePath -ArgumentList @("serve") -WorkingDirectory $installRoot -WindowStyle Hidden | Out-Null
    Write-Ok "Credential Broker start requested."
}

Wait-BrokerHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds

Write-Info "Install root: $installRoot"
Write-Info "Machine config: $machineConfigDir"
Write-Info "User config: $userConfigDir"

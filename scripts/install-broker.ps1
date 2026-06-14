param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker",
    [string]$HealthUrl = "http://127.0.0.1:8776/health",
    [int]$HealthTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Write-InstallLog {
    param(
        [ValidateSet("INFO", "STEP", "OK", "WARN", "ERROR")]
        [string]$Level,
        [string]$Message
    )

    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line

    if (-not [string]::IsNullOrWhiteSpace($script:InstallLogPath)) {
        $logParent = Split-Path -Parent $script:InstallLogPath
        if (-not (Test-Path $logParent)) {
            New-Item -ItemType Directory -Path $logParent -Force | Out-Null
        }
        Add-Content -Path $script:InstallLogPath -Value $line -Encoding UTF8
    }
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

function Write-Warn {
    param([string]$Message)
    Write-InstallLog -Level "WARN" -Message $Message
}

function Write-ErrorLog {
    param([string]$Message)
    Write-InstallLog -Level "ERROR" -Message $Message
}

function Wait-BrokerHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    Write-Step "Waiting for Credential Broker health..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 5
            if ($response.ok -eq $true -or $response.status -eq "ok" -or $response.service) {
                Write-Ok "GET $Url"
                return
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }

        Start-Sleep -Seconds 1
    }

    if ($lastError) {
        Write-Warn "Last health error: $lastError"
    }
    throw "Credential Broker health check did not pass within $TimeoutSeconds s: $Url"
}

function Invoke-Schtasks {
    param([string[]]$Arguments)

    Write-Info ("schtasks.exe " + ($Arguments -join " "))
    $output = & schtasks.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Info $_ }
    }
    return @{
        ExitCode = $exitCode
        Output = $output
    }
}

$installRoot = (Resolve-Path $InstallRoot).Path
$machineConfigDir = Join-Path $installRoot "config"
$userConfigDir = Join-Path $env:APPDATA "Credential Broker\config"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Credential Broker.lnk"
$exePath = Join-Path $installRoot "credential-broker.exe"
$taskName = "\CredentialBroker"
$logDir = Join-Path $installRoot "logs"
$script:InstallLogPath = Join-Path $logDir "installer.log"

trap {
    Write-ErrorLog $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-ErrorLog $_.ScriptStackTrace
    }
    throw
}

Write-Step "Preparing Credential Broker local install..."

if (-not (Test-Path $exePath)) {
    throw "Credential Broker executable not found: $exePath"
}

New-Item -ItemType Directory -Path $machineConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Write-Info "Installer log: $script:InstallLogPath"

Write-Step "Setting user environment..."
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $machineConfigDir, "User")
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $userConfigDir, "User")
$env:CREDENTIAL_BROKER_MACHINE_CONFIG_DIR = $machineConfigDir
$env:CREDENTIAL_BROKER_USER_CONFIG_DIR = $userConfigDir
Write-Ok "Credential Broker config environment updated."

Write-Step "Stopping old Credential Broker processes..."
$oldProcesses = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue
if ($oldProcesses) {
    $oldProcesses | ForEach-Object {
        Write-Info ("Stopping PID {0}: {1}" -f $_.ProcessId, $_.ExecutablePath)
        [void]$_.Terminate()
    }
}
else {
    Write-Ok "No old Credential Broker process found."
}

Write-Step "Stopping old Credential Broker development processes..."
$oldDevProcesses = Get-CimInstance Win32_Process -Filter "name = 'python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "credential_broker\.cli\s+serve" }
if ($oldDevProcesses) {
    $oldDevProcesses | ForEach-Object {
        Write-Info ("Stopping PID {0}: {1}" -f $_.ProcessId, $_.CommandLine)
        [void]$_.Terminate()
    }
}
else {
    Write-Ok "No old Credential Broker development process found."
}

Write-Step "Removing old Credential Broker scheduled task..."
$deleteResult = Invoke-Schtasks -Arguments @("/Delete", "/TN", $taskName, "/F")
if ($deleteResult.ExitCode -eq 0) {
    Write-Ok "Old scheduled task removed."
}
else {
    Write-Info "Old scheduled task was not present."
}

if (Test-Path $shortcutPath) {
    Write-Step "Removing old Startup shortcut..."
    Remove-Item -Path $shortcutPath -Force
    Write-Ok $shortcutPath
}

Write-Step "Creating Credential Broker scheduled task..."
$taskCommand = "`"$exePath`" serve"
$createResult = Invoke-Schtasks -Arguments @(
    "/Create",
    "/TN", $taskName,
    "/TR", $taskCommand,
    "/SC", "ONLOGON",
    "/RL", "LIMITED",
    "/F"
)
if ($createResult.ExitCode -ne 0) {
    throw "Credential Broker scheduled task registration failed: $taskName"
}
Write-Ok "Scheduled task registered: $taskName"

Write-Step "Starting Credential Broker once..."
Start-Process -FilePath $exePath -ArgumentList @("serve") -WorkingDirectory $installRoot -WindowStyle Hidden | Out-Null
Write-Ok "Credential Broker start requested."

Wait-BrokerHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds
$allBrokerProcesses = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue
if ($allBrokerProcesses) {
    $allBrokerProcesses | ForEach-Object {
        Write-Info ("Running broker process PID {0}: {1}" -f $_.ProcessId, $_.ExecutablePath)
    }
}
else {
    Write-Warn "No credential-broker.exe process is running after health wait."
}
$runningInstalledBroker = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -ieq $exePath }
if (-not $runningInstalledBroker) {
    throw "Credential Broker health is available, but installed broker process is not running: $exePath"
}

Write-Info "Install root: $installRoot"
Write-Info "Machine config: $machineConfigDir"
Write-Info "User config: $userConfigDir"

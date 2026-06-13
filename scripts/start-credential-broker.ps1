$ErrorActionPreference = "Stop"

$installRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $installRoot "credential-broker.exe"
$machineConfigDir = Join-Path $installRoot "config"
$userConfigDir = Join-Path $env:APPDATA "Credential Broker\config"
$logDir = Join-Path $installRoot "logs"

if (-not (Test-Path $exePath)) {
    throw "Credential Broker executable not found: $exePath"
}

New-Item -ItemType Directory -Path $machineConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $machineConfigDir, "User")
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $userConfigDir, "User")
$env:CREDENTIAL_BROKER_MACHINE_CONFIG_DIR = $machineConfigDir
$env:CREDENTIAL_BROKER_USER_CONFIG_DIR = $userConfigDir

$existing = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -ieq $exePath }

if ($existing) {
    return
}

Start-Process -FilePath $exePath -ArgumentList @("serve") -WorkingDirectory $installRoot -WindowStyle Hidden | Out-Null

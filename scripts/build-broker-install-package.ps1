param(
    [string]$Version = "v0.2.11",
    [string]$BrokerExePath = "dist\credential-broker.exe"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not [System.IO.Path]::IsPathRooted($BrokerExePath)) {
    $BrokerExePath = Join-Path $repoRoot $BrokerExePath
}

if (-not (Test-Path $BrokerExePath)) {
    throw "Broker executable not found: $BrokerExePath. Build it with PyInstaller first."
}

$artifactsRoot = Join-Path $repoRoot "artifacts"
$packageRoot = Join-Path $artifactsRoot "broker-install-package"
$staging = Join-Path $packageRoot "CredentialBroker-$Version"
$configDir = Join-Path $staging "config"
$zipPath = Join-Path $artifactsRoot "CredentialBroker-$Version.zip"

if (Test-Path $staging) {
    Remove-Item -Path $staging -Recurse -Force
}
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null

Copy-Item -Path $BrokerExePath -Destination (Join-Path $staging "credential-broker.exe") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\install-broker.ps1") -Destination (Join-Path $staging "install-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\uninstall-broker.ps1") -Destination (Join-Path $staging "uninstall-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "config\broker.json") -Destination (Join-Path $configDir "broker.json") -Force

Push-Location $staging
try {
    Compress-Archive -Path @("credential-broker.exe", "install-broker.ps1", "uninstall-broker.ps1", "config") -DestinationPath $zipPath -Force
}
finally {
    Pop-Location
}

Write-Host "Credential Broker install ZIP created: $zipPath"

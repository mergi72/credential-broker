param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker"
)

$ErrorActionPreference = "SilentlyContinue"

$installRoot = if (Test-Path $InstallRoot) { (Resolve-Path $InstallRoot).Path } else { $InstallRoot }
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Credential Broker.lnk"
$stopScript = Join-Path $installRoot "stop-credential-broker.ps1"

if (Test-Path $stopScript) {
    & $stopScript
}

if (Test-Path $shortcutPath) {
    Remove-Item -Path $shortcutPath -Force
}

[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $null, "User")
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $null, "User")

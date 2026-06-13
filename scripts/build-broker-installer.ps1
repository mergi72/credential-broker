param(
    [string]$Version = "v0.2.10",
    [string]$BrokerExePath = "dist\credential-broker.exe",
    [string]$InnoCompilerPath,
    [switch]$SkipCompile
)

$ErrorActionPreference = "Stop"

function Resolve-IsccPath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path $ExplicitPath)) {
        return (Resolve-Path $ExplicitPath).Path
    }

    $candidates = @(
        "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not [System.IO.Path]::IsPathRooted($BrokerExePath)) {
    $BrokerExePath = Join-Path $repoRoot $BrokerExePath
}

if (-not (Test-Path $BrokerExePath)) {
    throw "Broker executable not found: $BrokerExePath. Build it with PyInstaller first."
}

$payloadDir = Join-Path $repoRoot "artifacts\broker-installer-payload"
$configPayloadDir = Join-Path $payloadDir "config"
if (Test-Path $payloadDir) {
    Remove-Item -Path $payloadDir -Recurse -Force
}

New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $configPayloadDir -Force | Out-Null

Copy-Item -Path $BrokerExePath -Destination (Join-Path $payloadDir "credential-broker.exe") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\install-broker.ps1") -Destination (Join-Path $payloadDir "install-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\uninstall-broker.ps1") -Destination (Join-Path $payloadDir "uninstall-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "config\broker.json") -Destination (Join-Path $configPayloadDir "broker.json") -Force

Write-Host "Installer payload prepared: $payloadDir"

if ($SkipCompile) {
    Write-Host "SkipCompile enabled, not invoking ISCC.exe."
    return
}

$iscc = Resolve-IsccPath -ExplicitPath $InnoCompilerPath
if ([string]::IsNullOrWhiteSpace($iscc)) {
    throw "Inno Setup compiler (ISCC.exe) not found. Install Inno Setup 6 or provide -InnoCompilerPath."
}

$issPath = Join-Path $repoRoot "broker-installer.iss"
if (-not (Test-Path $issPath)) {
    throw "Installer script not found: $issPath"
}

Push-Location $repoRoot
try {
    & $iscc $issPath
    if ($LASTEXITCODE -ne 0) {
        throw "ISCC build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host "Credential Broker setup installer build completed."
Write-Host "Output directory: $(Join-Path $repoRoot 'artifacts\installer')"

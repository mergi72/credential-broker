param(
    [string]$InnoCompilerPath,
    [string]$ExePath,
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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
$payloadDir = Join-Path $repoRoot "artifacts\broker-installer-payload"
$payloadConfigDir = Join-Path $payloadDir "config"

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $repoRoot "dist\credential-broker.exe"
}

if (-not (Test-Path $ExePath)) {
    throw "Broker executable not found: $ExePath"
}

New-Item -ItemType Directory -Path $payloadConfigDir -Force | Out-Null

Copy-Item -Path $ExePath -Destination (Join-Path $payloadDir "credential-broker.exe") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\start-credential-broker.ps1") -Destination (Join-Path $payloadDir "start-credential-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "scripts\stop-credential-broker.ps1") -Destination (Join-Path $payloadDir "stop-credential-broker.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "config\broker.json") -Destination (Join-Path $payloadConfigDir "broker.json") -Force

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

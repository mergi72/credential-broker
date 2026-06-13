param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker",
    [string]$TaskName = "CredentialBroker",
    [string]$TaskPath = "\",
    [switch]$RemoveUserConfig
)

$ErrorActionPreference = "Stop"

$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$logRoot = Join-Path $InstallRoot "logs"
$logPath = Join-Path $logRoot "uninstaller.log"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Write-UninstallLog {
    param([string]$Message)
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
    Add-Content -Path $logPath -Value $line -Encoding UTF8
    Write-Host $Message
}

function Normalize-TaskPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return "\"
    }

    $normalized = $Path.Trim().Trim('"')
    if (-not $normalized.StartsWith("\")) {
        $normalized = "\$normalized"
    }
    if (-not $normalized.EndsWith("\")) {
        $normalized = "$normalized\"
    }
    return $normalized
}

function Get-BrokerTaskFullName {
    param(
        [string]$Name,
        [string]$Path
    )

    $normalizedPath = Normalize-TaskPath -Path $Path
    if ($normalizedPath -eq "\") {
        return "\$Name"
    }
    return "$normalizedPath$Name"
}

function Invoke-Schtasks {
    param([string[]]$Arguments)

    Write-UninstallLog "[INFO] schtasks.exe $($Arguments -join ' ')"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & schtasks.exe @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in @($output)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-UninstallLog "[INFO] schtasks: $line"
        }
    }
}

$taskFullName = Get-BrokerTaskFullName -Path $TaskPath -Name $TaskName

Write-UninstallLog "[INFO] Credential Broker uninstall started"
Write-UninstallLog "[STEP] Stopping scheduled task: $taskFullName"
Invoke-Schtasks -Arguments @("/End", "/TN", $taskFullName)
Invoke-Schtasks -Arguments @("/Delete", "/TN", $taskFullName, "/F")
Write-UninstallLog "[ OK ] Scheduled task removed if it existed"

$exePath = Join-Path $InstallRoot "credential-broker.exe"
Write-UninstallLog "[STEP] Stopping broker process if running"
$processes = Get-CimInstance Win32_Process -Filter "Name = 'credential-broker.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $exePath }
foreach ($process in @($processes)) {
    Write-UninstallLog "[INFO] Stopping process PID=$($process.ProcessId)"
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}
Write-UninstallLog "[ OK ] Broker process stopped if it existed"

Write-UninstallLog "[STEP] Removing user environment variables"
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $null, "User")
[Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $null, "User")
Write-UninstallLog "[ OK ] User environment variables removed"

if ($RemoveUserConfig) {
    $userRoot = Join-Path $env:APPDATA "Credential Broker"
    Write-UninstallLog "[STEP] Removing user config: $userRoot"
    Remove-Item -Path $userRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-UninstallLog "[ OK ] User config removed"
}
else {
    Write-UninstallLog "[INFO] User config preserved: $(Join-Path $env:APPDATA 'Credential Broker')"
}

Write-UninstallLog "[INFO] Credential Broker uninstall completed"

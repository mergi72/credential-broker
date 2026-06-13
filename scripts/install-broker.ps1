param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker",
    [string]$ExePath,
    [string]$ConfigSourceDir,
    [string]$TaskName = "CredentialBroker",
    [string]$TaskPath = "\",
    [switch]$StartImmediately
)

$ErrorActionPreference = "Stop"

function Write-InstallLog {
    param([string]$Message)
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    Write-Host $Message
}

function Ensure-Dir {
    param([string]$Path)
    Write-InstallLog "[STEP] Creating directory: $Path"
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-InstallLog "[ OK ] $Path"
}

function Copy-Checked {
    param(
        [string]$Source,
        [string]$Target,
        [switch]$PreserveExisting
    )
    Write-InstallLog "[STEP] Copying file: $Source -> $Target"
    $resolvedSource = (Resolve-Path $Source).Path
    $resolvedTarget = $null
    if (Test-Path $Target) {
        $resolvedTarget = (Resolve-Path $Target).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedTarget) -and $resolvedSource -ieq $resolvedTarget) {
        Write-InstallLog "[ OK ] Source already in target location: $Target"
        return
    }
    if ($PreserveExisting -and (Test-Path $Target)) {
        Write-InstallLog "[ OK ] Existing file preserved: $Target"
        return
    }
    Copy-Item -Path $resolvedSource -Destination $Target -Force
    if (-not (Test-Path $Target)) { throw "File was not copied: $Target" }
    Write-InstallLog "[ OK ] $Target"
}

function Set-UserEnvironmentValue {
    param([string]$Name, [string]$Value)
    Write-InstallLog "[STEP] Setting user environment: $Name=$Value"
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value
    Write-InstallLog "[ OK ] $Name"
}

function Stop-ExistingBrokerProcess {
    param([string]$ResolvedExePath)
    Write-InstallLog "[STEP] Stopping existing broker process if running"
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'credential-broker.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -eq $ResolvedExePath }
    foreach ($process in @($processes)) {
        Write-InstallLog "[INFO] Stopping process PID=$($process.ProcessId)"
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Write-InstallLog "[ OK ] Existing broker process check completed"
}

function Wait-Health {
    param([string]$Url)
    Write-InstallLog "[STEP] Health check: $Url"
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Write-InstallLog "[INFO] Health attempt $attempt/10"
        try {
            $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 2
            if ($response.ok -eq $true) {
                Write-InstallLog "[ OK ] Health check OK"
                return
            }
            Write-InstallLog "[WARN] Health returned unexpected payload"
        }
        catch {
            Write-InstallLog "[WARN] Health check failed: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 1
    }
    throw "Credential Broker health check failed: $Url"
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
    param(
        [string[]]$Arguments,
        [switch]$IgnoreFailure
    )

    Write-InstallLog "[INFO] schtasks.exe $($Arguments -join ' ')"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & schtasks.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in @($output)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-InstallLog "[INFO] schtasks: $line"
        }
    }
    if ($exitCode -ne 0 -and -not $IgnoreFailure) {
        throw "schtasks.exe failed with exit code $exitCode"
    }
    return $exitCode
}

function Test-BrokerScheduledTask {
    param([string]$FullName)

    $exitCode = Invoke-Schtasks -Arguments @("/Query", "/TN", $FullName) -IgnoreFailure
    return ($exitCode -eq 0)
}

function Write-ScheduledTaskCandidates {
    Write-InstallLog "[INFO] Scheduled task candidates matching '*Credential*':"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & schtasks.exe /Query /FO LIST 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text -like "*Credential*") {
            Write-InstallLog "[INFO] Task candidate: $text"
        }
    }
}

function Register-BrokerScheduledTask {
    param(
        [string]$FullName,
        [string]$LauncherPath
    )

    $quotedLauncherPath = $LauncherPath.Replace('"', '\"')
    $taskCommand = '\"powershell.exe\" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"' + $quotedLauncherPath + '\"'
    Invoke-Schtasks -Arguments @("/Delete", "/TN", $FullName, "/F") -IgnoreFailure | Out-Null
    Invoke-Schtasks -Arguments @(
        "/Create",
        "/TN",
        $FullName,
        "/TR",
        $taskCommand,
        "/SC",
        "ONLOGON",
        "/RL",
        "LIMITED",
        "/F"
    ) | Out-Null
}

function Start-BrokerLauncher {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Credential Broker launcher not found: $Path"
    }

    Write-InstallLog "[STEP] Starting broker launcher: $Path"
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        $Path
    ) -WindowStyle Hidden | Out-Null
    Write-InstallLog "[ OK ] Broker launcher start requested"
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$TaskPath = Normalize-TaskPath -Path $TaskPath
$appConfigRoot = Join-Path $InstallRoot "config"
$logRoot = Join-Path $InstallRoot "logs"
$userConfigRoot = Join-Path $env:APPDATA "Credential Broker\config"
$userRoot = Split-Path -Parent $userConfigRoot
$script:LogPath = Join-Path $logRoot "installer.log"

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Write-InstallLog "[INFO] Credential Broker installation started"
Write-InstallLog "[INFO] InstallRoot: $InstallRoot"
Write-InstallLog "[INFO] User: $env:USERDOMAIN\$env:USERNAME"

Ensure-Dir $InstallRoot
Ensure-Dir $appConfigRoot
Ensure-Dir $logRoot
Ensure-Dir $userRoot
Ensure-Dir $userConfigRoot

if ([string]::IsNullOrWhiteSpace($ExePath)) { $ExePath = Join-Path $InstallRoot "credential-broker.exe" }
if ([string]::IsNullOrWhiteSpace($ConfigSourceDir)) { $ConfigSourceDir = $appConfigRoot }

$brokerConfigSource = Join-Path $ConfigSourceDir "broker.json"
if (-not (Test-Path $brokerConfigSource)) { throw "broker.json source not found: $brokerConfigSource" }
Copy-Checked -Source $brokerConfigSource -Target (Join-Path $appConfigRoot "broker.json")

$localConfigPath = Join-Path $userConfigRoot "broker.local.json"
if (-not (Test-Path $localConfigPath)) {
    Write-InstallLog "[STEP] Creating user local config placeholder: $localConfigPath"
    Set-Content -Path $localConfigPath -Value "{}" -Encoding ASCII
    Write-InstallLog "[ OK ] $localConfigPath"
}
else {
    Write-InstallLog "[ OK ] Existing user local config preserved: $localConfigPath"
}

Set-UserEnvironmentValue -Name "CREDENTIAL_BROKER_MACHINE_CONFIG_DIR" -Value $appConfigRoot
Set-UserEnvironmentValue -Name "CREDENTIAL_BROKER_USER_CONFIG_DIR" -Value $userConfigRoot

$launcherPath = Join-Path $InstallRoot "start-credential-broker.ps1"
$stdoutPath = Join-Path $logRoot "broker-stdout.log"
$stderrPath = Join-Path $logRoot "broker-stderr.log"
$launcher = @"
`$ErrorActionPreference = "Stop"
`$appRoot = Split-Path -Parent `$PSCommandPath
`$env:CREDENTIAL_BROKER_MACHINE_CONFIG_DIR = Join-Path `$appRoot "config"
`$env:CREDENTIAL_BROKER_USER_CONFIG_DIR = Join-Path `$env:APPDATA "Credential Broker\config"
`$logRoot = Join-Path `$appRoot "logs"
New-Item -ItemType Directory -Path `$logRoot -Force | Out-Null
`$exe = Join-Path `$appRoot "credential-broker.exe"
& `$exe serve >> (Join-Path `$logRoot "broker-stdout.log") 2>> (Join-Path `$logRoot "broker-stderr.log")
"@
Write-InstallLog "[STEP] Writing launcher: $launcherPath"
Set-Content -Path $launcherPath -Value $launcher -Encoding UTF8
Write-InstallLog "[ OK ] $launcherPath"

Stop-ExistingBrokerProcess -ResolvedExePath $ExePath

$taskFullName = Get-BrokerTaskFullName -Path $TaskPath -Name $TaskName

Write-InstallLog "[STEP] Registering scheduled task: $taskFullName"
try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $userSid = $identity.User.Value
    Write-InstallLog "[INFO] Scheduled task user SID: $userSid"

    Register-BrokerScheduledTask -FullName $taskFullName -LauncherPath $launcherPath
    if (-not (Test-BrokerScheduledTask -FullName $taskFullName)) {
        Write-InstallLog "[WARN] Scheduled task was registered without error but cannot be found: $taskFullName"
        Write-ScheduledTaskCandidates
    }
    else {
        Write-InstallLog "[ OK ] Scheduled task registered and verified: $taskFullName"
    }
}
catch {
    Write-InstallLog "[WARN] Scheduled task registration failed: $($_.Exception.Message)"
    Write-ScheduledTaskCandidates
}

if ($StartImmediately) {
    if (-not (Test-BrokerScheduledTask -FullName $taskFullName)) {
        Write-InstallLog "[WARN] Scheduled task not available for start, using launcher fallback: $taskFullName"
        Start-BrokerLauncher -Path $launcherPath
    }
    else {
        Write-InstallLog "[STEP] Starting scheduled task: $taskFullName"
        $runExitCode = Invoke-Schtasks -Arguments @("/Run", "/TN", $taskFullName) -IgnoreFailure
        if ($runExitCode -ne 0) {
            Write-InstallLog "[WARN] Scheduled task start failed, using launcher fallback: $taskFullName"
            Start-BrokerLauncher -Path $launcherPath
        }
        else {
            Write-InstallLog "[ OK ] Scheduled task start requested"
        }
    }
    Wait-Health -Url "http://127.0.0.1:8776/health"
}

Write-InstallLog "[INFO] Credential Broker installation completed successfully"

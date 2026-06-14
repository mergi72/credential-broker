param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Credential Broker",
    [string]$HealthUrl = "http://127.0.0.1:8776/health",
    [int]$HealthTimeoutSeconds = 60
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

function Wait-InstallConfirmation {
    param([string]$Message)

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    Write-Host "Press Enter to continue..."
    [void](Read-Host)
}

function Invoke-InstallOperation {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Step $Name
    Wait-InstallConfirmation "Before: $Name"
    & $Action
    Write-Ok $Name
    Wait-InstallConfirmation "After: $Name"
}

function Wait-BrokerHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 5
            if ($response.ok -eq $true -or $response.status -eq "ok" -or $response.service) {
                Write-Ok "Broker health OK: $Url"
                return
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }

        Start-Sleep -Seconds 1
    }

    if ($lastError) {
        Write-Info "Last broker health error: $lastError"
    }
    throw "Credential Broker health check did not pass within $TimeoutSeconds s: $Url"
}

function Quote-TaskArgument {
    param([string]$Value)

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Invoke-ExternalProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $argumentLine = ($Arguments | ForEach-Object { Quote-TaskArgument $_ }) -join " "
    Write-Info "$FilePath $argumentLine"

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $argumentLine
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        $stdout.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Info $_ }
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $stderr.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Info $_ }
    }

    return $process.ExitCode
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-QuotedPowerShellString {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Register-CredentialBrokerTask {
    param(
        [string]$TaskName,
        [string]$BrokerExePath
    )

    $taskCommand = "`"$BrokerExePath`" serve"
    if (Test-IsAdmin) {
        $exitCode = Invoke-ExternalProcess -FilePath "schtasks.exe" -Arguments @(
            "/Create",
            "/TN", $TaskName,
            "/TR", $taskCommand,
            "/SC", "ONLOGON",
            "/RL", "LIMITED",
            "/F"
        )

        if ($exitCode -ne 0) {
            throw "Credential Broker scheduled task registration failed: $TaskName"
        }
        return
    }

    Write-Info "Admin elevation is required to register scheduled task."
    $taskScriptPath = Join-Path $installRoot "register-credential-broker-task.ps1"
    $taskNameLiteral = New-QuotedPowerShellString -Value ($TaskName.TrimStart("\"))

    $taskScript = @(
        '$ErrorActionPreference = "Stop"',
        '$taskName = ' + $taskNameLiteral,
        '$exePath = Join-Path $env:LOCALAPPDATA "Credential Broker\credential-broker.exe"',
        '$taskCommand = "`"$exePath`" serve"',
        'schtasks.exe /Create /TN $taskName /TR $taskCommand /SC ONLOGON /RL LIMITED /F',
        'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
    )
    Set-Content -Path $taskScriptPath -Value $taskScript -Encoding UTF8

    Write-Info "Starting elevated task registration: $taskScriptPath"
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $taskScriptPath
    ) -Verb RunAs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Credential Broker elevated scheduled task registration failed with exit code $($process.ExitCode): $TaskName"
    }
}

trap {
    Write-ErrorLog $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-ErrorLog $_.ScriptStackTrace
    }
    throw
}

Write-Step "Preparing Credential Broker directory structure..."
Wait-InstallConfirmation "Before: Preparing Credential Broker directory structure"

Invoke-InstallOperation -Name "Create install root: $installRoot" -Action {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
}
Invoke-InstallOperation -Name "Create machine config directory: $machineConfigDir" -Action {
    New-Item -ItemType Directory -Path $machineConfigDir -Force | Out-Null
}
Invoke-InstallOperation -Name "Create log directory: $logDir" -Action {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Invoke-InstallOperation -Name "Create user config directory: $userConfigDir" -Action {
    New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
}

Write-Info "Install root: $installRoot"
Write-Info "Machine config: $machineConfigDir"
Write-Info "User config: $userConfigDir"
Write-Info "Log directory: $logDir"
Write-Info "Installer log: $installLogPath"

Invoke-InstallOperation -Name "Replace user environment CREDENTIAL_BROKER_MACHINE_CONFIG_DIR=$machineConfigDir" -Action {
    [Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_MACHINE_CONFIG_DIR", $machineConfigDir, "User")
    $env:CREDENTIAL_BROKER_MACHINE_CONFIG_DIR = $machineConfigDir
}
Invoke-InstallOperation -Name "Replace user environment CREDENTIAL_BROKER_USER_CONFIG_DIR=$userConfigDir" -Action {
    [Environment]::SetEnvironmentVariable("CREDENTIAL_BROKER_USER_CONFIG_DIR", $userConfigDir, "User")
    $env:CREDENTIAL_BROKER_USER_CONFIG_DIR = $userConfigDir
}

Invoke-InstallOperation -Name "Stop old credential-broker.exe process if running" -Action {
    $oldProcesses = Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" -ErrorAction SilentlyContinue
    if (-not $oldProcesses) {
        Write-Info "No old credential-broker.exe process found."
        return
    }

    foreach ($oldProcess in $oldProcesses) {
        Write-Info ("Stopping PID {0}: {1}" -f $oldProcess.ProcessId, $oldProcess.ExecutablePath)
        [void]$oldProcess.Terminate()
    }
}

$brokerExePath = Join-Path $installRoot "credential-broker.exe"
Invoke-InstallOperation -Name "Start credential-broker.exe serve in background: $brokerExePath" -Action {
    if (-not (Test-Path $brokerExePath)) {
        throw "Credential Broker executable not found: $brokerExePath"
    }

    Start-Process -FilePath $brokerExePath -ArgumentList @("serve") -WorkingDirectory $installRoot -WindowStyle Hidden | Out-Null
}

Invoke-InstallOperation -Name "Wait for Credential Broker health: $HealthUrl" -Action {
    Wait-BrokerHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds
}

$taskName = "\CredentialBroker"
Invoke-InstallOperation -Name "Create Credential Broker scheduled task: $taskName" -Action {
    Register-CredentialBrokerTask -TaskName $taskName -BrokerExePath $brokerExePath
}

$requiredFiles = @(
    $brokerExePath,
    (Join-Path $installRoot "config\broker.json")
)

foreach ($requiredFile in $requiredFiles) {
    Invoke-InstallOperation -Name "Verify installed file: $requiredFile" -Action {
        if (-not (Test-Path $requiredFile)) {
            throw "Required installed file not found: $requiredFile"
        }
    }
}

Write-Ok "Credential Broker directory structure prepared."
Wait-InstallConfirmation "After: Credential Broker directory structure prepared"

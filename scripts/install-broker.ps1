param(
    [string]$InstallRoot,
    [string]$HealthUrl = "http://127.0.0.1:8776/health",
    [int]$HealthTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Credential Broker"
}

$installRoot = if (Test-Path $InstallRoot) { (Resolve-Path $InstallRoot).Path } else { $InstallRoot }
$machineConfigDir = Join-Path $installRoot "config"
$logDir = Join-Path $installRoot "logs"
$userConfigDir = Join-Path $env:APPDATA "Credential Broker\config"
$installLogPath = Join-Path $logDir "installer.log"
$installIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$installUserSid = $installIdentity.User.Value
$installUserName = $env:USERNAME
$installUserDomain = $env:USERDOMAIN
$installUser = if ([string]::IsNullOrWhiteSpace($installUserDomain)) { $installUserName } else { "$installUserDomain\$installUserName" }

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

function Invoke-InstallOperation {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Step $Name
    & $Action
    Write-Ok $Name
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

function Register-CredentialBrokerTask {
    param(
        [string]$TaskName,
        [string]$BrokerExePath,
        [string]$InstallUser,
        [string]$InstallUserSid
    )

    $taskLogPath = Join-Path $logDir "task-registration.log"
    function Write-TaskRegistrationLog {
        param([string]$Message)

        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -Path $taskLogPath -Value $line -Encoding UTF8
        Write-Info "task-registration: $Message"
    }

    function Set-TaskSetting {
        param(
            [object]$Settings,
            [string]$Name,
            [object]$Value
        )

        try {
            $Settings.$Name = $Value
            Write-TaskRegistrationLog "Setting $Name=$Value"
        }
        catch {
            Write-TaskRegistrationLog "Setting $Name skipped: $($_.Exception.Message)"
        }
    }

    if (Test-Path $taskLogPath) {
        Remove-Item -Path $taskLogPath -Force
    }

    Write-TaskRegistrationLog "Starting user-context task registration."
    Write-TaskRegistrationLog "TaskName=$TaskName"
    Write-TaskRegistrationLog "InstallUser=$InstallUser"
    Write-TaskRegistrationLog "InstallUserSid=$InstallUserSid"
    Write-TaskRegistrationLog "BrokerExePath=$BrokerExePath"

    $service = New-Object -ComObject "Schedule.Service"
    $service.Connect()
    $rootFolder = $service.GetFolder("\")
    $taskDefinition = $service.NewTask(0)

    $taskDefinition.RegistrationInfo.Author = $InstallUser
    $taskDefinition.RegistrationInfo.Description = "Starts Credential Broker for the current user."

    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.Enabled = $true
    $trigger.UserId = $InstallUser

    $taskDefinition.Principal.UserId = $InstallUserSid
    $taskDefinition.Principal.LogonType = 3
    $taskDefinition.Principal.RunLevel = 0

    Set-TaskSetting -Settings $taskDefinition.Settings -Name "MultipleInstances" -Value 2
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "DisallowStartIfOnBatteries" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "StopIfGoingOnBatteries" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "AllowHardTerminate" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "StartWhenAvailable" -Value $false
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "RunOnlyIfNetworkAvailable" -Value $false
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "AllowStartOnDemand" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "Enabled" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "Hidden" -Value $false
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "RunOnlyIfIdle" -Value $false
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "WakeToRun" -Value $false
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "ExecutionTimeLimit" -Value "PT72H"
    Set-TaskSetting -Settings $taskDefinition.Settings -Name "Priority" -Value 7
    Set-TaskSetting -Settings $taskDefinition.Settings.IdleSettings -Name "StopOnIdleEnd" -Value $true
    Set-TaskSetting -Settings $taskDefinition.Settings.IdleSettings -Name "RestartOnIdle" -Value $false

    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "`"$BrokerExePath`""
    $action.Arguments = "serve"

    [void]$rootFolder.RegisterTaskDefinition($TaskName, $taskDefinition, 6, $null, $null, 3, $null)
    Write-TaskRegistrationLog "COM task registration completed."

    $queryExitCode = Invoke-ExternalProcess -FilePath "schtasks.exe" -Arguments @(
        "/Query",
        "/TN", $TaskName,
        "/V",
        "/FO", "LIST"
    )
    if ($queryExitCode -ne 0) {
        throw "Credential Broker scheduled task verification failed: $TaskName"
    }
    Write-TaskRegistrationLog "Scheduled task registration verified."
}

trap {
    Write-ErrorLog $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-ErrorLog $_.ScriptStackTrace
    }
    throw
}

Write-Step "Preparing Credential Broker directory structure..."

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
Write-Info "Install user: $installUser"
Write-Info "Install user SID: $installUserSid"

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

$taskName = "CredentialBroker"
Invoke-InstallOperation -Name "Create Credential Broker scheduled task: $taskName" -Action {
    Register-CredentialBrokerTask -TaskName $taskName -BrokerExePath $brokerExePath -InstallUser $installUser -InstallUserSid $installUserSid
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

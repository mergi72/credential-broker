$ErrorActionPreference = "SilentlyContinue"

$installRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $installRoot "credential-broker.exe"

Get-CimInstance Win32_Process -Filter "name = 'credential-broker.exe'" |
    Where-Object { $_.ExecutablePath -ieq $exePath } |
    ForEach-Object { [void]$_.Terminate() }

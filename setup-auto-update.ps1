# Run once ("Set Up NHL Auto Update.bat"). Like College Football: every 15 minutes, update the NHL
# scoreboard and publish it online. Runs only while you're logged in; overlapping runs are skipped.
$ErrorActionPreference = 'Stop'
$engine = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $engine) { $engine = (Get-Command powershell).Source }
$conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$action = New-ScheduledTaskAction -Execute $conhost -Argument ('--headless cmd.exe /c ""' + (Join-Path $PSScriptRoot 'Update NHL Scoreboard.bat') + '" /quiet"') -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName 'NHL 15-minute update' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Refresh the NHL scoreboard and publish it online every 15 minutes.' -Force | Out-Null
Get-ScheduledTask -TaskName 'NHL 15-minute update' | Select-Object TaskName,State

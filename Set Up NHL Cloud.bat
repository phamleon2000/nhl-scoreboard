@echo off
rem Run once: uploads the NHL scoreboard to GitHub so it updates and publishes online by itself.
cd /d "%~dp0"
set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-cloud.ps1"
pause

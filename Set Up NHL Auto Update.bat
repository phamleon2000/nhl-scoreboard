@echo off
rem Run once: updates and publishes the NHL scoreboard every 15 minutes (like College Football).
rem To stop: open Task Scheduler and delete "NHL 15-minute update".
cd /d "%~dp0"
set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-auto-update.ps1"
pause

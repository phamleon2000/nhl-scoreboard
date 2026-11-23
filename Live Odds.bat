@echo off
rem Keeps live NHL odds from Maddux Sports fresh for the offline page: refreshes maddux-live.js every 30 seconds.
rem Leave this window open while you watch the games; "NHL Scoreboard.html" re-reads the file every 30 seconds.
rem Close the window to stop.
setlocal
cd /d "%~dp0"

set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"

start "" "%~dp0NHL Scoreboard.html"
echo Refreshing Maddux Sports odds every 30 seconds. Close this window to stop.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0maddux-odds.ps1" -Loop -Every 30

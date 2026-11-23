@echo off
rem Publishes the current NHL pages to the online site (Cloudflare), like College Football's "4. Publish Online.bat".
rem Run "Update NHL Scoreboard.bat" first so the page has fresh data (it also publishes by itself).
cd /d "%~dp0"
set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0online\publish.ps1"
if errorlevel 1 (echo. & echo Publish did not finish. See the message above.) else (echo. & echo Online site updated.)
pause

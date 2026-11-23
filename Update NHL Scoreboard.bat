@echo off
rem Refreshes the NHL scoreboard data and rebuilds "NHL Scoreboard.html", then opens it.
rem Run with /quiet to skip opening the page and the pause.
setlocal
cd /d "%~dp0"

set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"

echo Updating NHL scoreboard (this takes a few minutes)...
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-nhl.ps1" > "%~dp0last-update.log" 2>&1
set "RESULT=%ERRORLEVEL%"
type "%~dp0last-update.log"

if not "%RESULT%"=="0" (
  echo.
  echo Update failed. Details are in last-update.log.
  if /i not "%~1"=="/quiet" pause
  exit /b 1
)

rem After "Publish NHL Online.bat" has worked once, also publish the online copy (delete online-enabled.txt to stop)
if exist "%~dp0online-enabled.txt" (
  echo Publishing online copy...
  %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-online.ps1" >> "%~dp0last-update.log" 2>&1 || echo Online publish failed. Details are in last-update.log.
)
echo.
echo Done.
if /i not "%~1"=="/quiet" (
  start "" "%~dp0NHL Scoreboard.html"
  timeout /t 5 >nul
)
exit /b 0

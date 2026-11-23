@echo off
rem Sends changed NHL scripts/template to GitHub so the cloud updates use them.
rem Run this after any change to nhl-template.html, update-nhl.ps1 or the schedule. It never touches the data branch.
cd /d "%~dp0"
if not exist ".github\workflows" mkdir ".github\workflows"
copy /y "online\update-workflow.yml" ".github\workflows\update.yml" >nul
git add -A
git commit -m "Update NHL scripts" >nul 2>nul
git push origin main
if errorlevel 1 (echo. & echo Push failed. See the message above.) else (echo. & echo Changes sent to GitHub.)
pause

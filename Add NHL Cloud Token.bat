@echo off
rem Run once: saves your Cloudflare API token as the GitHub secret for phamleon2000/nhl-scoreboard
rem (using the GitHub login on this PC), then starts the first cloud update.
cd /d "%~dp0"
echo Paste your Cloudflare API token below (right-click to paste; it stays hidden), then press Enter.
gh secret set CLOUDFLARE_API_TOKEN --repo phamleon2000/nhl-scoreboard
if errorlevel 1 (echo. & echo Saving the token failed. & pause & exit /b 1)
echo.
echo Token saved. Starting the first cloud update...
gh workflow run "Update NHL Scoreboard" --repo phamleon2000/nhl-scoreboard
if errorlevel 1 (echo Could not start the update. & pause & exit /b 1)
echo Started. Watch it at https://github.com/phamleon2000/nhl-scoreboard/actions
pause

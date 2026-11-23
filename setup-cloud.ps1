# Run once ("Set Up NHL Cloud.bat") after creating an EMPTY GitHub repo named nhl-scoreboard.
# Uploads the NHL scripts to GitHub (main branch) and your saved history to the "data" branch,
# so the GitHub workflow can update and publish the site every few hours without this PC.
param([string]$Repo = 'https://github.com/phamleon2000/nhl-scoreboard.git')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is not installed.' }
if (-not (Test-Path '.git')) { git init -b main | Out-Null }
if (-not (git remote)) { git remote add origin $Repo } else { git remote set-url origin $Repo }
git config user.name 'leon pham'
git config user.email '200858270+leonpham74@users.noreply.github.com'
# the workflow file is kept in online\ and copied into place here
New-Item -ItemType Directory -Force '.github\workflows' | Out-Null
Copy-Item 'online\update-workflow.yml' '.github\workflows\update.yml' -Force
git add -A
git commit -m 'NHL scoreboard: scripts, template and cloud update workflow' 2>&1 | Out-Host
git push -u origin main
if ($LASTEXITCODE) { throw 'Push to GitHub failed. Check that the repo exists and is empty.' }
& "$PSScriptRoot\online\save-data.ps1"
if ($LASTEXITCODE) { throw 'Saving the data branch failed.' }
'Done. On GitHub: Settings > Secrets and variables > Actions > add CLOUDFLARE_API_TOKEN (same as College Football), then Actions > Update NHL Scoreboard > Run workflow.'

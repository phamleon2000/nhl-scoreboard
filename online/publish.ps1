# Copies the current NHL pages into online\public and deploys them to Cloudflare
# (same setup as College Football: a Worker serving static files at https://nhl-picks.<you>.workers.dev).
# index.html = phone page, desktop.html = full page. Use -StageOnly to copy files without deploying.
param([switch]$StageOnly)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$pub = Join-Path $here 'public'
New-Item -ItemType Directory -Force $pub | Out-Null

Copy-Item (Join-Path $root 'NHL Scoreboard Mobile.html') (Join-Path $pub 'index.html') -Force
Copy-Item (Join-Path $root 'NHL Scoreboard.html') (Join-Path $pub 'desktop.html') -Force
Copy-Item (Join-Path $root 'nhl-data.json') (Join-Path $pub 'nhl-data.json') -Force
Write-Host "Staged files in $pub"
if ($StageOnly) { exit 0 }

if ($env:CLOUDFLARE_API_TOKEN) { $env:CLOUDFLARE_API_TOKEN = ($env:CLOUDFLARE_API_TOKEN -replace '\s', '') }
Push-Location $here
try {
  npx --yes wrangler@4 deploy
  if ($LASTEXITCODE -ne 0) { throw "Deploy failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }
Set-Content (Join-Path $root 'online-enabled.txt') 'Publishing to the nhl-picks Cloudflare worker after each update. Delete this file to stop.' -Encoding utf8

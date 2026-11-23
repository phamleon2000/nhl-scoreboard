# Kept for "Update NHL Scoreboard.bat": publishes through online\publish.ps1 (the College Football-style setup).
& (Join-Path $PSScriptRoot 'online\publish.ps1')
exit $LASTEXITCODE

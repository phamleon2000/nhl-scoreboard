# Replaces the "data" branch with one commit holding the current NHL data files (as College Football does).
# Used by the GitHub workflow after each update.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$files = @(Get-ChildItem -File -Filter *.json | ForEach-Object Name) + @('maddux-live.js', 'last-update.log') | Where-Object { Test-Path $_ }
$tmpIndex = Join-Path ([IO.Path]::GetTempPath()) ("nhl-data-index-" + [guid]::NewGuid())
$env:GIT_INDEX_FILE = $tmpIndex
try {
  git add -f -- $files
  if ($LASTEXITCODE) { throw 'git add failed' }
  $tree = git write-tree
  if (-not $env:GIT_AUTHOR_NAME) { $env:GIT_AUTHOR_NAME = 'nhl-updater'; $env:GIT_AUTHOR_EMAIL = 'nhl-updater@users.noreply.github.com' }
  $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME; $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
  $commit = "Data as of $((Get-Date).ToUniversalTime().ToString('u'))" | git commit-tree $tree
  if ($LASTEXITCODE) { throw 'git commit-tree failed' }
  git push --force origin "${commit}:refs/heads/data"
  if ($LASTEXITCODE) { throw 'git push failed' }
  "Saved $($files.Count) data files to the data branch."
} finally {
  Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
  Remove-Item $tmpIndex -ErrorAction SilentlyContinue
}

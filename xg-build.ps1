# Builds xg-table.json, the expected-goals table: the share of unblocked shots that became goals, by distance, angle,
# rebound and strength state, from every 2025-26 regular-season game (last season, so this season's results never feed
# the table). Empty-net shots and shootouts are left out. Run once (about 10 minutes); update-nhl.ps1 uses the file.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\nhl-pbp.ps1"
$season = '20252026'
$teams = 'ANA','BOS','BUF','CGY','CAR','CHI','COL','CBJ','DAL','DET','EDM','FLA','LAK','MIN','MTL','NSH','NJD','NYI','NYR','OTT','PHI','PIT','SJS','SEA','STL','TBL','TOR','UTA','VAN','VGK','WSH','WPG'
$ids = [System.Collections.Generic.HashSet[string]]::new()
foreach ($t in $teams) { try { (Invoke-RestMethod "https://api-web.nhle.com/v1/club-schedule-season/$t/$season" -TimeoutSec 30).games | Where-Object { $_.gameType -eq 2 } | ForEach-Object { [void]$ids.Add("$($_.id)") } } catch { "schedule skipped for ${t}: $($_.Exception.Message)" } }
"Games to read: $($ids.Count)"
$cells = @{}; $n = 0
foreach ($id in $ids) {
  $pbp = $null; for ($i = 1; $i -le 3 -and -not $pbp; $i++) { try { $pbp = Invoke-RestMethod "https://api-web.nhle.com/v1/gamecenter/$id/play-by-play" -TimeoutSec 30 } catch { Start-Sleep -Milliseconds (800 * $i) } }
  if (-not $pbp) { continue }
  foreach ($s in (Get-NhlShots $pbp)) { if ($s.st -eq 'EN' -or $s.ot) { continue }
    $b = Get-XgBin $s; if (-not $cells[$b]) { $cells[$b] = @(0, 0) }; $cells[$b][0]++; if ($s.goal) { $cells[$b][1]++ } }
  $n++; if ($n % 100 -eq 0) { "read $n games" }
}
# Smoothing: each cell is pulled toward its distance band's rate as if it had 30 more shots at that rate
$band = @{}; foreach ($k in $cells.Keys) { $p = $k -split '\|'; $bk = "$($p[0])|$($p[3])"; if (-not $band[$bk]) { $band[$bk] = @(0, 0) }; $band[$bk][0] += $cells[$k][0]; $band[$bk][1] += $cells[$k][1] }
$tbl = [ordered]@{}; $shots = 0; $goals = 0
foreach ($k in ($cells.Keys | Sort-Object)) { $p = $k -split '\|'; $b = $band["$($p[0])|$($p[3])"]; $prior = ($b[1] + 1) / ($b[0] + 20)
  $tbl[$k] = [math]::Round(($cells[$k][1] + 30 * $prior) / ($cells[$k][0] + 30), 4); $shots += $cells[$k][0]; $goals += $cells[$k][1] }
$bandOut = [ordered]@{}; foreach ($k in ($band.Keys | Sort-Object)) { $bandOut[$k] = [math]::Round(($band[$k][1] + 1) / ($band[$k][0] + 20), 4) }
[ordered]@{ season = $season; games = $n; shots = $shots; goals = $goals; built = (Get-Date).ToUniversalTime().ToString('o'); cells = $tbl; bands = $bandOut } |
  ConvertTo-Json -Depth 4 -Compress | Set-Content "$PSScriptRoot\xg-table.json" -Encoding utf8
"xg-table.json: $n games, $shots shots, $goals goals ($([math]::Round(100 * $goals / [math]::Max(1, $shots), 1))% of unblocked shots), $($tbl.Count) cells"

# This season's game-by-game hockey stats for the framework model, from the NHL's own API (api-web.nhle.com), plus
# probable starting goalies (DailyFaceoff) and injuries (ESPN). Dot-sourced by update-nhl.ps1:
#   $extra = Add-NhlStats $games $teams     adds to each game:
#     x   (finished games) regulation stats, [away, home] pairs:
#         t5 5-on-5 minutes; tp PP minutes; x5 / xp / xs / xo expected goals at 5-on-5, on the power play, shorthanded
#         and in other states (4-on-4, extra attacker); g5 / gp / gs / go goals in the same states; en empty-net goals;
#         e1 / e2 empty-net goals scored with a 1- or 2-goal lead; fa unblocked shots; hd high-danger shots (within 20 ft);
#         pn penalties taken; p1 1st-period goals; rg regulation goals; end REG / OT / SO;
#         gk goalies [id, side, xG faced, goals allowed, starter 1/0] (empty-net shots left out)
#     pg  (upcoming games, next 3 days) probable starters { a: [id, name, status], h: [...] }, status Confirmed /
#         Likely / Projected, from DailyFaceoff
#     ninj (upcoming games, next 8 days) injured players { a: [[id, name, status]], h: [...] }, from ESPN
#   and returns @{ players = { id: [team, name, F/D/G, games, avg minutes, last game date] }; goalies = { id: [name, team] } }
# Expected goals come from xg-table.json (last season's shots, see xg-build.ps1). Stats are cached in
# nhl-stats-history.json, so each finished game is read once.
. "$PSScriptRoot\nhl-pbp.ps1"
$NHL_STATS_VER = 1
function Get-NhlJson($u) { for ($i = 1; $i -le 3; $i++) { try { return Invoke-RestMethod $u -TimeoutSec 30 } catch { if ($i -eq 3) { throw }; Start-Sleep -Milliseconds (700 * $i) } } }
function Add-NhlStats($games, $teams) {
  $toNhl = @{ LA = 'LAK'; NJ = 'NJD'; SJ = 'SJS'; TB = 'TBL'; UTAH = 'UTA' }; $toEspn = @{}
  foreach ($k in $teams.Keys) { $n = if ($toNhl[$k]) { $toNhl[$k] } else { $k }; $toEspn[$n] = $k }
  $xt = Get-Content "$PSScriptRoot\xg-table.json" -Raw | ConvertFrom-Json -AsHashtable
  $xgOf = { param($s) $c = $xt.cells[(Get-XgBin $s)]; if ($null -ne $c) { [double]$c } else { $p = (Get-XgBin $s) -split '\|'; $b = $xt.bands["$($p[0])|$($p[3])"]; if ($null -ne $b) { [double]$b } else { 0.05 } } }
  $cachePath = "$PSScriptRoot\nhl-stats-history.json"
  $cache = if (Test-Path $cachePath) { Get-Content $cachePath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }; if (-not $cache) { $cache = @{} }
  $et = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
  $etDay = { param($d) [TimeZoneInfo]::ConvertTimeFromUtc(([datetime]$d).ToUniversalTime(), $et).ToString('yyyy-MM-dd') }
  # NHL game ids by Eastern date and teams, from the weekly schedule
  $nid = @{}; $need = @($games | Where-Object { $_.s -eq 'post' -and -not ($cache["$($_.id)"] -and $cache["$($_.id)"].v -eq $NHL_STATS_VER) })
  if ($need.Count) {
    $days = @($need | ForEach-Object { & $etDay $_.d } | Sort-Object -Unique); $seen = @{}
    foreach ($day in $days) { if ($seen[$day]) { continue }
      $s = Get-NhlJson "https://api-web.nhle.com/v1/schedule/$day"
      foreach ($wk in $s.gameWeek) { $seen[$wk.date] = 1; foreach ($x in $wk.games) { $nid["$($wk.date)|$($toEspn[$x.awayTeam.abbrev])|$($toEspn[$x.homeTeam.abbrev])"] = $x.id } } }
  }
  "NHL stats: $($need.Count) finished games to read"
  foreach ($g in $need) {
    $id = $nid["$(& $etDay $g.d)|$($g.a)|$($g.h)"]; if (-not $id) { "NHL stats: no NHL game found for $($g.a)@$($g.h) $($g.d)"; continue }
    try {
      $pbp = Get-NhlJson "https://api-web.nhle.com/v1/gamecenter/$id/play-by-play"; $box = Get-NhlJson "https://api-web.nhle.com/v1/gamecenter/$id/boxscore"
      $z = { @(0.0, 0.0) }
      $f = [ordered]@{ v = $NHL_STATS_VER; n = $id; t5 = 0.0; tp = (& $z); x5 = (& $z); xp = (& $z); xs = (& $z); xo = (& $z); g5 = (& $z); gp = (& $z); gs = (& $z); go = (& $z)
        en = (& $z); e1 = (& $z); e2 = (& $z); fa = (& $z); hd = (& $z); pn = (& $z); p1 = (& $z); rg = (& $z); end = "$($box.gameOutcome.lastPeriodType)"; gk = @(); sk = @() }
      # Time in each strength state (regulation): each gap between plays counts toward the state of the earlier play
      $plays = @($pbp.plays | Where-Object { $_.periodDescriptor.number -le 3 -and $_.periodDescriptor.periodType -eq 'REG' })
      for ($i = 0; $i -lt $plays.Count - 1; $i++) { $p = $plays[$i]; $q = $plays[$i + 1]; if ($p.periodDescriptor.number -ne $q.periodDescriptor.number) { continue }
        $dt = ((Get-NhlSecs $q) - (Get-NhlSecs $p)) / 60.0; if ($dt -le 0) { continue }
        $c = "$($p.situationCode)"; if ($c.Length -ne 4 -or $c[0] -eq '0' -or $c[3] -eq '0') { continue }
        $as = [int]"$($c[1])"; $hs = [int]"$($c[2])"
        if ($as -eq 5 -and $hs -eq 5) { $f.t5 += $dt } elseif ($hs -gt $as) { $f.tp[1] += $dt } elseif ($as -gt $hs) { $f.tp[0] += $dt } }
      # Shots and goals by state; goalies' expected goals faced
      $gk = @{}
      foreach ($s in (Get-NhlShots $pbp)) {
        $side = if ($s.home) { 1 } else { 0 }; $xg = & $xgOf $s
        if ($s.st -ne 'EN' -and $s.gid) { $k = "$($s.gid)|$(1 - $side)"; if (-not $gk[$k]) { $gk[$k] = @(0.0, 0) }; $gk[$k][0] += $xg; if ($s.goal) { $gk[$k][1]++ } }
        if ($s.ot) { continue }
        if ($s.st -eq 'EN') { if ($s.goal) { $f.en[$side]++ }; continue }
        $f.fa[$side]++; if ($s.dist -lt 20) { $f.hd[$side]++ }
        switch ($s.st) { 'EV' { $f.x5[$side] += $xg; if ($s.goal) { $f.g5[$side]++ } } 'PP' { $f.xp[$side] += $xg; if ($s.goal) { $f.gp[$side]++ } }
          'SH' { $f.xs[$side] += $xg; if ($s.goal) { $f.gs[$side]++ } } default { $f.xo[$side] += $xg; if ($s.goal) { $f.go[$side]++ } } }
      }
      foreach ($p in $plays) {
        if ($p.typeDescKey -eq 'goal') { $side = if ($p.details.eventOwnerTeamId -eq $pbp.homeTeam.id) { 1 } else { 0 }
          $f.rg[$side]++; if ($p.periodDescriptor.number -eq 1) { $f.p1[$side]++ }
          if ((Get-NhlState "$($p.situationCode)" ([bool]$side)) -eq 'EN') { $lead = if ($side) { $p.details.homeScore - $p.details.awayScore } else { $p.details.awayScore - $p.details.homeScore }
            if ($lead - 1 -eq 1) { $f.e1[$side]++ } elseif ($lead - 1 -eq 2) { $f.e2[$side]++ } } }
        if ($p.typeDescKey -eq 'penalty' -and $p.details.typeCode -in 'MIN', 'MAJ', 'BEN') { $side = if ($p.details.eventOwnerTeamId -eq $pbp.homeTeam.id) { 1 } else { 0 }; $f.pn[$side]++ }
      }
      foreach ($sd in @(@('awayTeam', 0), @('homeTeam', 1))) { $t = $box.playerByGameStats.($sd[0])
        foreach ($gl in $t.goalies) { $k = "$($gl.playerId)|$($sd[1])"; $v = $gk[$k]; if ($v -or $gl.starter) { $f.gk += , @($gl.playerId, $sd[1], [math]::Round($(if ($v) { $v[0] } else { 0 }), 3), $(if ($v) { $v[1] } else { 0 }), [int][bool]$gl.starter, "$($gl.name.default)") } }
        foreach ($pl in @($t.forwards) + @($t.defense)) { if (-not $pl.toi) { continue }; $m = "$($pl.toi)" -split ':'; $f.sk += , @($pl.playerId, $sd[1], [math]::Round([int]$m[0] + [int]$m[1] / 60, 1), $(if ($pl.position -eq 'D') { 'D' } else { 'F' }), "$($pl.name.default)") } }
      foreach ($k in 't5') { $f[$k] = [math]::Round($f[$k], 2) }
      foreach ($k in 'tp', 'x5', 'xp', 'xs', 'xo') { $f[$k] = @([math]::Round($f[$k][0], 3), [math]::Round($f[$k][1], 3)) }
      $cache["$($g.id)"] = $f
    } catch { "NHL stats skipped for $($g.a)@$($g.h): $($_.Exception.Message)" }
  }
  $cache | ConvertTo-Json -Compress -Depth 6 | Set-Content $cachePath -Encoding utf8
  # Rosters: full names and ids, for goalie and injury matching
  $roster = @{}; $names = @{}
  foreach ($k in $teams.Keys) { $ab = if ($toNhl[$k]) { $toNhl[$k] } else { $k }
    try { $r = Get-NhlJson "https://api-web.nhle.com/v1/roster/$ab/current"
      foreach ($grp in @(@($r.forwards, 'F'), @($r.defensemen, 'D'), @($r.goalies, 'G'))) { foreach ($p in $grp[0]) { $full = "$($p.firstName.default) $($p.lastName.default)"
        $roster["$k|$($full.ToLower())"] = $p.id; $roster["$k|last|$("$($p.lastName.default)".ToLower())"] = $p.id; $names["$($p.id)"] = @($k, $full, $grp[1]) } } } catch { "roster skipped for ${k}: $($_.Exception.Message)" } }
  $findId = { param($team, $name) $n = "$name".ToLower().Trim(); $id = $roster["$team|$n"]; if (-not $id) { $id = $roster["$team|last|$(($n -split ' ')[-1])"] }; $id }
  # Players: games and average minutes this season, from the box scores
  $pl = @{}; $byDate = $games | Where-Object { $_.s -eq 'post' -and $cache["$($_.id)"] } | Sort-Object d
  $goalies = @{}
  foreach ($g in $byDate) { $f = $cache["$($g.id)"]
    foreach ($s in $f.sk) { $k = "$($s[0])"; $team = if ($s[1]) { $g.h } else { $g.a }; if (-not $pl[$k]) { $pl[$k] = @($team, "$($s[4])", $s[3], 0, 0.0, '') }
      $pl[$k][0] = $team; $pl[$k][3]++; $pl[$k][4] += [double]$s[2]; $pl[$k][5] = $g.d.Substring(0, 10) }
    foreach ($q in $f.gk) { $goalies["$($q[0])"] = @($(if ($names["$($q[0])"]) { $names["$($q[0])"][1] } else { "$($q[5])" }), $(if ($q[1]) { $g.h } else { $g.a })) } }
  $players = [ordered]@{}; foreach ($k in $pl.Keys) { $v = $pl[$k]; $nm = if ($names[$k]) { $names[$k][1] } else { $v[1] }
    $players[$k] = @($v[0], $nm, $v[2], $v[3], [math]::Round($v[4] / [math]::Max(1, $v[3]), 1), $v[5]) }
  foreach ($k in $names.Keys) { if ($names[$k][2] -eq 'G' -and -not $goalies[$k]) { $goalies[$k] = @($names[$k][1], $names[$k][0]) } }
  foreach ($g in $games) { $f = $cache["$($g.id)"]; if ($g.s -eq 'post' -and $f) { $x = [ordered]@{}; foreach ($k in $f.Keys) { if ($k -notin 'sk', 'v') { $x[$k] = $f[$k] } }
    $x.gk = @($f.gk | ForEach-Object { , @($_[0], $_[1], $_[2], $_[3], $_[4]) }); $g | Add-Member -NotePropertyName x -NotePropertyValue $x -Force } }
  # Probable starters, next three days (DailyFaceoff: Confirmed / Likely; no word yet = Projected)
  $now = (Get-Date).ToUniversalTime(); $pgN = 0
  for ($k = 0; $k -le 2; $k++) { $day = [TimeZoneInfo]::ConvertTimeFromUtc($now, $et).AddDays($k).ToString('yyyy-MM-dd')
    try { $html = (Invoke-WebRequest "https://www.dailyfaceoff.com/starting-goalies/$day" -UseBasicParsing -TimeoutSec 30 -UserAgent 'Mozilla/5.0').Content
      $m = [regex]::Match($html, '<script id="__NEXT_DATA__"[^>]*>(.*?)</script>'); if (-not $m.Success) { continue }
      foreach ($r in ($m.Groups[1].Value | ConvertFrom-Json -Depth 50).props.pageProps.data) { $a = $toEspn["$($r.awayTeamAbbreviation)"]; $h = $toEspn["$($r.homeTeamAbbreviation)"]; if (-not $a -or -not $h) { continue }
        $g = $games | Where-Object { $_.s -eq 'pre' -and $_.a -eq $a -and $_.h -eq $h -and [math]::Abs((([datetime]$_.d).ToUniversalTime() - $now).TotalDays) -lt 4 } | Sort-Object d | Select-Object -First 1; if (-not $g) { continue }
        $st = { param($x) if ("$x" -match 'Confirmed') { 'Confirmed' } elseif ("$x" -match 'Likely') { 'Likely' } elseif ("$x" -match 'Unconfirmed') { 'Unconfirmed' } else { 'Projected' } }
        $pg = [ordered]@{ a = @((& $findId $a $r.awayGoalieName), "$($r.awayGoalieName)", (& $st $r.awayNewsStrengthName)); h = @((& $findId $h $r.homeGoalieName), "$($r.homeGoalieName)", (& $st $r.homeNewsStrengthName)); at = $now.ToString('o') }
        $g | Add-Member -NotePropertyName pg -NotePropertyValue $pg -Force; $pgN++ } } catch { "DailyFaceoff skipped for ${day}: $($_.Exception.Message)" } }
  # Injuries (ESPN), on upcoming games in the next 8 days
  $injN = 0
  try { $byName = @{}; foreach ($k in $teams.Keys) { $byName["$($teams[$k][0]) $($teams[$k][1])"] = $k }
    $inj = @{}; foreach ($t in (Get-NhlJson 'https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/injuries').injuries) { $k = $byName["$($t.displayName)"]; if (-not $k) { continue }
      $inj[$k] = @($t.injuries | ForEach-Object { , @((& $findId $k $_.athlete.displayName), "$($_.athlete.displayName)", "$($_.status)") }) }
    foreach ($g in $games) { if ($g.s -ne 'pre' -or ([datetime]$g.d).ToUniversalTime() -gt $now.AddDays(8)) { continue }
      $g | Add-Member -NotePropertyName ninj -NotePropertyValue ([ordered]@{ a = @($inj[$g.a]); h = @($inj[$g.h]) }) -Force; $injN++ } } catch { "Injuries skipped: $($_.Exception.Message)" }
  "NHL stats: $(@($games | Where-Object x).Count) games with stats, $pgN with probable goalies, $injN with injury lists, $($players.Count) players"
  return @{ players = $players; goalies = $goalies }
}

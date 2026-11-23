# Pulls the 2026-27 NHL regular season from ESPN (schedule and scores), Maddux Sports (odds from six sportsbooks, live and
# closing lines) and Sports Betting Dime (% of bets and % of money), writes nhl-data.json for the online page and builds
# "NHL Scoreboard.html" (data built in) plus "NHL Scoreboard Mobile.html", the phone edition.
# The page is the same one the NFL scoreboard uses (nhl-template.html); league = "nhl" switches it to hockey (goals, the
# puck line, no weather, no halves).
$ErrorActionPreference = 'Stop'
# A game counts as not started only while ESPN says so AND its kickoff time hasn't passed: ESPN's schedule feed can lag
# for hours, and pre-game snapshots saved after kickoff held in-game lines and splits (Nov 14: NMSU@MOST, SJSU@AFA, UTAH@ARIZ)
function Test-Pre($g) { $g.s -eq 'pre' -and ([datetime]$g.d).ToUniversalTime() -gt (Get-Date).ToUniversalTime() }
$espn = 'https://site.api.espn.com/apis/site/v2/sports/hockey/nhl'
$season = 2027   # ESPN names the 2026-27 season 2027
function Get-Espn($u) { for ($i = 1; $i -le 4; $i++) { try { return Invoke-RestMethod $u -TimeoutSec 30 } catch { if ($i -eq 4) { throw }; Start-Sleep -Milliseconds (700 * $i) } } }

# ── Teams ──
$tl = Get-Espn "$espn/teams"
$teams = [ordered]@{}; $teamId = @{}
foreach ($x in $tl.sports[0].leagues[0].teams.team) { $teams[$x.abbreviation] = @($x.location, $x.name, $x.color); $teamId[$x.abbreviation] = $x.id }

# ── Games: every team's regular-season schedule (ESPN's scoreboard only serves one day at a time) ──
$byId = [ordered]@{}
foreach ($ab in $teams.Keys) {
  $sch = Get-Espn "$espn/teams/$($teamId[$ab])/schedule?season=$season&seasontype=2"
  foreach ($e in $sch.events) { if (-not $byId.Contains("$($e.id)")) { $byId["$($e.id)"] = $e } }
}
# Weeks run Monday to Sunday (Eastern time), Week 1 being the week of the first game
$et = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
$toEt = { param($d) [TimeZoneInfo]::ConvertTimeFromUtc(([datetime]$d).ToUniversalTime(), $et) }
$firstEt = (& $toEt (($byId.Values | ForEach-Object { ([datetime]$_.date).ToUniversalTime() } | Sort-Object | Select-Object -First 1))).Date
$monday = $firstEt.AddDays(-(([int]$firstEt.DayOfWeek + 6) % 7))
$scoreOf = { param($c) if ($null -eq $c.score) { '0' } elseif ($c.score.displayValue) { "$($c.score.displayValue)" } else { "$($c.score)" } }
$games = foreach ($e in $byId.Values) {
  $c = $e.competitions[0]; $h = $c.competitors | Where-Object homeAway -eq 'home'; $a = $c.competitors | Where-Object homeAway -eq 'away'
  if (-not $h -or -not $a -or -not $teams.Contains($h.team.abbreviation) -or -not $teams.Contains($a.team.abbreviation)) { continue }
  $kick = ([datetime]$e.date).ToUniversalTime()
  [pscustomobject]@{ w = [int][math]::Floor(((& $toEt $kick).Date - $monday).TotalDays / 7) + 1; d = $kick.ToString('yyyy-MM-ddTHH:mmZ')
    s = "$($c.status.type.state)"; st = "$($c.status.type.shortDetail)"
    h = $h.team.abbreviation; hs = (& $scoreOf $h); a = $a.team.abbreviation; as = (& $scoreOf $a)
    v = "$($c.venue.fullName)"; tv = (@($c.broadcasts | ForEach-Object { $_.media.shortName }) | Where-Object { $_ }) -join '/'; n = [bool]$c.neutralSite
    id = "$($e.id)"; indoor = $true; hq = @(); aq = @() }
}
$games = @($games | Sort-Object d)
"Games: $($games.Count) ($(@($games | Where-Object s -eq 'post').Count) final), teams: $($teams.Count), weeks: $(($games | Measure-Object w -Maximum).Maximum)"
function Find-Game($a, $h) { $games | Where-Object { $_.s -eq 'pre' -and $_.a -eq $a -and $_.h -eq $h } | Sort-Object d | Select-Object -First 1 }
$fullName = @{}; foreach ($k in $teams.Keys) { $fullName["$($teams[$k][0]) $($teams[$k][1])"] = $k }
$byNick = @{}; foreach ($k in $teams.Keys) { $byNick["$($teams[$k][1])"] = $k }
$teamOf = { param($name) $nm = "$name".Trim(); if ($fullName[$nm]) { $fullName[$nm] } elseif ($teams.Contains($nm)) { $nm } else { $last = ($nm -split ' ')[-1]; $byNick[$last] } }

# ── Betting splits: Sports Betting Dime (% of bets and % of money on the puck line and the total) ──
$splits = 0
try {
  . "$PSScriptRoot\sbd-splits.ps1"
  foreach ($r in @(Get-SbdSplits 'nhl' { param($tm) $ab = & $teamOf "$($tm.market) $($tm.name)"; if (-not $ab) { $ab = & $teamOf $tm.abbreviation }; $ab })) {
    if ($r -is [string]) { $r; continue }
    $g = Find-Game $r.a $r.h; if (-not $g) { continue }
    # 0% / 0% means no bets counted yet on that market
    foreach ($k in 'sb', 'sm', 'ob', 'om') { if ($r[$k] -and -not (($r[$k] | Measure-Object -Sum).Sum)) { $r[$k] = $null } }
    if (-not $r.sb -and -not $r.ob) { continue }
    if (-not $g.ms) { $g | Add-Member -NotePropertyName ms -NotePropertyValue ([ordered]@{}) -Force }
    $g.ms[$r.src] = [ordered]@{ sb = $r.sb; sm = $r.sm; ob = $r.ob; om = $r.om; line = $r.line; tot = $r.tot }; $splits++
  }
} catch { "Betting splits skipped: $($_.Exception.Message)" }
"Betting splits: $splits"

# ── Hockey stats for the framework model: expected goals, special teams, goalies, ice time, probable starters, injuries ──
$extra = @{ players = @{}; goalies = @{} }
try { . "$PSScriptRoot\nhl-stats.ps1"; $r = Add-NhlStats $games $teams; foreach ($o in $r) { if ($o -is [string]) { $o } elseif ($o -is [hashtable]) { $extra = $o } } }
catch { "NHL stats skipped: $($_.Exception.Message)" }

# ── Live sportsbook odds (Maddux Sports): each game's line from the middle of the books (the closing line once started) ──
$now = (Get-Date).ToUniversalTime()
$soon = @($games | Where-Object { (Test-Pre $_) -and ([datetime]$_.d).ToUniversalTime() -lt $now.AddDays(8) })
$histPath = "$PSScriptRoot\picks-history.json"
$hist = if (Test-Path $histPath) { Get-Content $histPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }; if (-not $hist) { $hist = @{} }
$mx = $null; $mxLine = @{}; $mxAlias = [ordered]@{}; $matched = 0
try {
  . "$PSScriptRoot\maddux-odds.ps1"
  $mx = Get-MadduxOdds
  $median = { param($v) $s = @($v | Where-Object { $_ -ne $null } | Sort-Object); if (-not $s.Count) { $null } elseif ($s.Count % 2) { $s[($s.Count - 1) / 2] } else { ($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2 } }
  # Prices: American odds jump from -100 to +100, so the middle of -101 and +102 is not +0.5. Prices are worked in
  # "cents from even" (-105 is -5, +102 is +2) and turned back into odds (Nov 20 fix: ML -2, over/under -79 and -70 were saved)
  $toC = { param($o) if ($o -lt 0) { $o + 100 } else { $o - 100 } }
  $fromC = { param($c) if ($null -eq $c) { $null } elseif ($c -lt 0) { $c - 100 } else { $c + 100 } }
  $medOdds = { param($v) & $fromC (& $median @(foreach ($o in $v) { if ($null -ne $o) { & $toC $o } })) }
  foreach ($x in $mx.games) {
    $a = & $teamOf $x.a; $h = & $teamOf $x.h; if (-not $a -or -not $h) { continue }
    $mxAlias[$x.a] = $a; $mxAlias[$x.h] = $h
    $ko = [DateTimeOffset]::new(([datetime]$x.d).ToUniversalTime()).ToUnixTimeSeconds()
    $g = $games | Where-Object { $_.a -eq $a -and $_.h -eq $h -and [math]::Abs((([datetime]$_.d).ToUniversalTime() - ([datetime]$x.d).ToUniversalTime()).TotalHours) -lt 12 } | Select-Object -First 1
    if (-not $g) { continue }
    $rows = @(); foreach ($bk in $x.b.Values) { $r1 = $bk['1']; if ($r1 -and ((Test-Pre $g) -or ($r1[8] -and $r1[8] -le $ko))) { $rows += , $r1 } }
    $sp = & $median @(foreach ($r1 in $rows) { if ("$($r1[0])" -ne '') { [double]$r1[0] } })
    $tot = & $median @(foreach ($r1 in $rows) { if ("$($r1[3])" -ne '') { [double]$r1[3] } })
    $mla = & $medOdds @(foreach ($r1 in $rows) { if ("$($r1[6])" -match '^[+-]?\d') { [double]$r1[6] } })
    $mlh = & $medOdds @(foreach ($r1 in $rows) { if ("$($r1[7])" -match '^[+-]?\d') { [double]$r1[7] } })
    # puck-line prices at the middle line, and over / under prices at the middle total (a "u-115" price mirrors to -105 on the over,
    # the other side of a 20-cent line: -130 mirrors to +110)
    $atSp = @($rows | Where-Object { "$($_[0])" -ne '' -and $sp -ne $null -and [double]$_[0] -eq ([math]::Floor($sp * 2 + 0.5) / 2) })
    $plh = & $medOdds @(foreach ($r1 in $atSp) { if ("$($r1[1])" -match '^[+-]?\d') { [double]$r1[1] } }); $pla = & $medOdds @(foreach ($r1 in $atSp) { if ("$($r1[2])" -match '^[+-]?\d') { [double]$r1[2] } })
    $mir = { param($r1, $s) $pr = "$($r1[5])"; if ($pr -notmatch '^[+-]?\d') { return $null }; $v = [double]$pr; if ($r1[4] -eq $s) { $v } else { & $fromC (-(& $toC $v) - 20) } }
    $atT = @($rows | Where-Object { "$($_[3])" -ne '' -and $tot -ne $null -and [double]$_[3] -eq ([math]::Floor($tot * 2 + 0.5) / 2) })
    $ovp = & $medOdds @(foreach ($r1 in $atT) { & $mir $r1 'o' }); $unp = & $medOdds @(foreach ($r1 in $atT) { & $mir $r1 'u' })
    if ($tot -ne $null -or $mla -ne $null) {
      $mxLine["$($g.id)"] = @($(if ($sp -ne $null) { [math]::Floor($sp * 2 + 0.5) / 2 } else { $null }), $(if ($tot -ne $null) { [math]::Floor($tot * 2 + 0.5) / 2 } else { $null }),
        $(if ($mla -ne $null) { [math]::Round($mla) } else { $null }), $(if ($mlh -ne $null) { [math]::Round($mlh) } else { $null }),
        $(if ($pla -ne $null) { [math]::Round($pla) } else { $null }), $(if ($plh -ne $null) { [math]::Round($plh) } else { $null }),
        $(if ($ovp -ne $null) { [math]::Round($ovp) } else { $null }), $(if ($unp -ne $null) { [math]::Round($unp) } else { $null })); $matched++ }
    if (Test-Pre $g) {
      $bkLines = [ordered]@{}
      foreach ($kv in $x.b.GetEnumerator()) { $r1 = $kv.Value['1']; if ($r1) { $bkLines[$kv.Key] = @($r1[0], $r1[1], $r1[2], $r1[3], $r1[6], $r1[7], $r1[4], $r1[5]) } }
      $o1 = $x.open['1']; if ($o1) { $bkLines['Open'] = @($o1[0], $o1[1], $o1[2], $o1[3], $o1[6], $o1[7], $o1[4], $o1[5]) }
      if ($bkLines.Count) { $g | Add-Member -NotePropertyName bk -NotePropertyValue $bkLines -Force }
    }
  }
  $mx | Add-Member -NotePropertyName alias -NotePropertyValue $mxAlias -Force
  [IO.File]::WriteAllText("$PSScriptRoot\maddux-live.js", "window.MADDUX = $(($mx | ConvertTo-Json -Depth 8 -Compress).Replace('</', '<\/'));", (New-Object Text.UTF8Encoding $false))
  "Maddux Sports: $(@($mx.games).Count) games, $matched matched lines"
} catch { "Maddux Sports odds skipped: $($_.Exception.Message)" }

# ── Pre-game snapshots (picks-history.json), so finished games are graded on what was known before the puck drop ──
foreach ($g in $soon) {
  $open = $null; if ($g.bk -and $g.bk['Open']) { $open = "$($g.bk['Open'][0])" }
  $nowSp = if ($mxLine["$($g.id)"]) { "$($mxLine["$($g.id)"][0])" } else { $null }
  # (with the probable goalies and injury list as they stood before the game, for the framework model)
  if ($g.ms -or $g.bk -or $g.pg) { $hist["$($g.id)"] = [ordered]@{ ms = $g.ms; sp = @($open, $nowSp); bk = $g.bk; pg = $g.pg; ninj = $g.ninj; at = $now.ToString('o') } }
}
foreach ($g in $games) { if ($g.s -eq 'post' -and $hist["$($g.id)"]) { $g | Add-Member -NotePropertyName snap -NotePropertyValue $hist["$($g.id)"] -Force } }
# Games in progress: the sites drop their splits at the puck drop, so carry over the last pre-game ones
foreach ($g in $games) { $hh = $hist["$($g.id)"]; if ($g.s -eq 'in' -and $hh -and -not $g.ms -and $hh['ms']) { $g | Add-Member -NotePropertyName ms -NotePropertyValue $hh['ms'] -Force } }
$hist | ConvertTo-Json -Compress -Depth 8 | Set-Content $histPath -Encoding utf8

# ── Lines for grading (lines-history.json): the Maddux line before the game, its closing line once started, otherwise
#    ESPN's closing line from each finished game's summary (fetched once) ──
$linePath = "$PSScriptRoot\lines-history.json"
$lineHist = if (Test-Path $linePath) { Get-Content $linePath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }; if (-not $lineHist) { $lineHist = @{} }
foreach ($g in $games) { $m = $mxLine["$($g.id)"]; if (-not $m -or $m[1] -eq $null) { continue }
  $e = [ordered]@{ sp = $m[0]; tot = [double]$m[1]; src = $(if (Test-Pre $g) { 'Maddux Sports live odds (middle of the books)' } else { 'Maddux Sports closing line (middle of the books)' }) }
  if ($m[2] -ne $null -and $m[3] -ne $null) { $e.ml = @($m[2], $m[3]) }
  if ($m[4] -ne $null -and $m[5] -ne $null) { $e.pl = @($m[4], $m[5]) }
  if ($m[6] -ne $null -and $m[7] -ne $null) { $e.ou = @($m[6], $m[7]) }
  $lineHist["$($g.id)"] = $e }
# Period scores (periods-history.json: [away periods, home periods], overtime and shootout included), from the same summaries
$perPath = "$PSScriptRoot\periods-history.json"
# A saved line with a price between -100 and +100 can't be real (saved before the Nov 20 fix): read ESPN's closing line again
$badLine = { param($e) $e -and @(@($e.ml) + @($e.pl) + @($e.ou) | Where-Object { $null -ne $_ -and [double]$_ -gt -100 -and [double]$_ -lt 100 }).Count -gt 0 }
$perHist = if (Test-Path $perPath) { Get-Content $perPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }; if (-not $perHist) { $perHist = @{} }
$need = @($games | Where-Object { $_.s -eq 'post' -and (-not $lineHist["$($_.id)"] -or -not $lineHist["$($_.id)"].ml -or -not $lineHist["$($_.id)"].ou -or (& $badLine $lineHist["$($_.id)"]) -or -not $perHist["$($_.id)"]) })
"Fetching $($need.Count) finished games' closing lines and period scores from ESPN..."
foreach ($g in $need) {
  try {
    $sum = Get-Espn "$espn/summary?event=$($g.id)"
    $pc = $sum.pickcenter | Select-Object -First 1
    $old = $lineHist["$($g.id)"]
    if ($pc -and $pc.overUnder -and (-not $old -or -not $old.ml -or -not $old.ou -or (& $badLine $old))) {
      $e = [ordered]@{ sp = $(if ($null -ne $pc.spread) { [double]$pc.spread } else { $null }); tot = [double]$pc.overUnder; src = "$($pc.provider.name) close (ESPN)" }
      if ($pc.homeTeamOdds.moneyLine -and $pc.awayTeamOdds.moneyLine) { $e.ml = @([double]$pc.awayTeamOdds.moneyLine, [double]$pc.homeTeamOdds.moneyLine) }
      if ($pc.homeTeamOdds.spreadOdds -and $pc.awayTeamOdds.spreadOdds) { $e.pl = @([double]$pc.awayTeamOdds.spreadOdds, [double]$pc.homeTeamOdds.spreadOdds) }
      if ($pc.overOdds -and $pc.underOdds) { $e.ou = @([double]$pc.overOdds, [double]$pc.underOdds) }
      if ($old -and -not $e.ml) { $e = $old }
      $lineHist["$($g.id)"] = $e
    }
    $cs = $sum.header.competitions[0].competitors
    $qa = @(($cs | Where-Object homeAway -eq 'away').linescores | ForEach-Object { [int]$_.displayValue }); $qh = @(($cs | Where-Object homeAway -eq 'home').linescores | ForEach-Object { [int]$_.displayValue })
    if ($qa.Count -ge 3 -and $qh.Count -ge 3) { $perHist["$($g.id)"] = @(, $qa) + @(, $qh) }
  } catch { "Summary skipped for $($g.a)@$($g.h): $($_.Exception.Message)" }
}
$lineHist | ConvertTo-Json -Compress -Depth 4 | Set-Content $linePath -Encoding utf8
$perHist | ConvertTo-Json -Compress -Depth 4 | Set-Content $perPath -Encoding utf8
foreach ($g in $games) { $q = $perHist["$($g.id)"]; if ($g.s -eq 'post' -and $q) { $g.aq = @($q[0]); $g.hq = @($q[1]) } }
foreach ($g in $games) { if ($g.s -eq 'post' -and $lineHist["$($g.id)"]) { $g | Add-Member -NotePropertyName vl -NotePropertyValue $lineHist["$($g.id)"] -Force } }

# ── Data file and the offline pages ──
$json = [ordered]@{ league = 'nhl'; updated = $now.ToString('o'); teams = $teams; others = [ordered]@{}; confs = [ordered]@{}
  books = @(); coaches = $null; mx = $mx; adv = $null; players = $extra.players; goalies = $extra.goalies; games = $games } | ConvertTo-Json -Compress -Depth 8
Set-Content "$PSScriptRoot\nhl-data.json" $json -Encoding utf8
$page = (Get-Content "$PSScriptRoot\nhl-template.html" -Raw).Replace('<title>NFL 2026 Scoreboard</title>', '<title>NHL 2026-27</title>')
$inline = "<script>window.NFL_DATA = $($json.Replace('</', '<\/'));</script>`n<script>`n(async"
$page = $page.Replace("<script>`r`n(async", "<script>`n(async").Replace("<script>`n(async", $inline)
Set-Content "$PSScriptRoot\NHL Scoreboard.html" $page -Encoding utf8
Set-Content "$PSScriptRoot\NHL Scoreboard Mobile.html" ("<script>window.NFL_MOBILE = true;</script>`n" + $page) -Encoding utf8
"Wrote nhl-data.json, NHL Scoreboard.html and NHL Scoreboard Mobile.html - $($games.Count) games, $(@($games | Where-Object s -eq 'post').Count) final, $(@($games | Where-Object vl).Count) with a grading line"

# Live NHL odds from Maddux Sports (madduxsports.com/nhl-hockey-odds.php).
# The page embeds every game's lines as JSON ("var data = {...}"): six sportsbooks plus the opener, for the full game (1),
# 1st half (2) and 2nd half (3), with live scores. This script turns that into a compact list.
#
#   Dot-sourced by update-nhl.ps1:  . "$PSScriptRoot\maddux-odds.ps1"; $mx = Get-MadduxOdds
#   Run directly to refresh maddux-live.js for the offline page (it re-reads the file every minute):
#     powershell -File maddux-odds.ps1            (once)
#     powershell -File maddux-odds.ps1 -Loop      (every 60 seconds until the window is closed)
param([switch]$Loop, [int]$Every = 60, [string]$Out = "")

function Get-MadduxOdds {
  $html = $null
  for ($try = 1; $try -le 3 -and -not $html; $try++) {
    try { $html = (Invoke-WebRequest "https://www.madduxsports.com/nhl-hockey-odds.php" -UseBasicParsing -TimeoutSec 30 -UserAgent "Mozilla/5.0").Content }
    catch { Start-Sleep -Seconds (3 * $try) }
  }
  if (-not $html) { throw "Maddux Sports didn't respond" }
  $m = [regex]::Match($html, '(?s)var data = (\{.*?\});\s*\n')
  if (-not $m.Success) { throw "Maddux Sports page layout changed (no odds data found)" }
  $j = $m.Groups[1].Value | ConvertFrom-Json
  $names = @{}
  foreach ($b in [regex]::Matches($html, '\{"id":(\d+),"name":"([^"]+)","fullname"')) { $names[$b.Groups[1].Value] = $b.Groups[2].Value }
  # One period's line as [home spread, home price, away price, total, o/u side the price is for, total price, away ML, home ML, changed (unix)]
  $period = {
    param($p)
    if (-not $p) { return $null }
    $tot = $null; $tag = ""; $tp = ""
    foreach ($s in @($p.away, $p.home)) {
      $t = [regex]::Match("$s", '^\s*([\d.]+)\s*([ou])\s*([+-]?\d+|EV|ev)?')
      if ($t.Success) { $tot = $t.Groups[1].Value; $tag = $t.Groups[2].Value; $tp = $t.Groups[3].Value }
    }
    # Books that haven't posted a line show zeros ("0 0 / 0u0"); treat those as missing
    $hs = "$($p.ps.home_spread)"; $hp = "$($p.ps.home_price)"; $ap = "$($p.ps.away_price)"
    if ($hp -eq "0" -and $ap -eq "0") { $hs = ""; $hp = ""; $ap = "" }
    if ($tot -eq "0") { $tot = $null; $tag = ""; $tp = "" }
    if (-not $hs -and -not $tot -and -not "$($p.money.home)") { return $null }
    return @($hs, $hp, $ap, $tot, $tag, $tp, "$($p.money.away)", "$($p.money.home)", $p.change_time)
  }
  $games = foreach ($s in $j.schedulers) {
    $tn = ("$($s.team_names)" -split '<br\s*/?>')
    if ($tn.Count -lt 2) { continue }
    $books = [ordered]@{}
    foreach ($bp in $s.odds.PSObject.Properties) {
      $per = [ordered]@{}
      foreach ($k in "1", "2", "3") { $v = & $period $bp.Value.$k; if ($v) { $per[$k] = $v } }
      $bn = $names[$bp.Name]; if (-not $bn) { $bn = "Book $($bp.Name)" }
      if ($per.Count) { $books[$bn] = $per }
    }
    $open = [ordered]@{}
    foreach ($k in "1", "2", "3") { $v = & $period $s.opener.$k; if ($v) { $open[$k] = $v } }
    $sc = $null
    if ("$($s.score.away_score)" -ne "") { $sc = @($s.score.away_score, $s.score.home_score) }
    [ordered]@{ a = $tn[0].Trim(); h = $tn[1].Trim(); d = $s.raw_date; st = "$($s.event_state)"; sc = $sc
      clk = "$($s.score.description)"; lp = "$($s.score.latest_period)"; open = $open; b = $books }
  }
  return [ordered]@{ updated = (Get-Date).ToUniversalTime().ToString("o"); src = "Maddux Sports"; games = @($games) }
}

if ($MyInvocation.InvocationName -ne '.') {
  if (-not $Out) { $Out = Join-Path $PSScriptRoot "maddux-live.js" }
  do {
    try {
      $mx = Get-MadduxOdds
      $json = $mx | ConvertTo-Json -Depth 8 -Compress
      [IO.File]::WriteAllText($Out, "window.MADDUX = $($json.Replace('</', '<\/'));", (New-Object Text.UTF8Encoding $false))
      "$(Get-Date -Format T)  Maddux odds saved: $($mx.games.Count) games"
    } catch { "$(Get-Date -Format T)  Couldn't refresh Maddux odds: $($_.Exception.Message)" }
    if ($Loop) { Start-Sleep -Seconds $Every }
  } while ($Loop)
}

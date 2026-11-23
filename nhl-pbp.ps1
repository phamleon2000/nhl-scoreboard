# Shot-level reading of NHL play-by-play (api-web.nhle.com), shared by xg-build.ps1 and nhl-stats.ps1.
#   Get-NhlShots $pbp        every unblocked shot attempt (shot on goal, miss, goal) with its distance, angle, rebound
#                            flag, strength state for the shooting team and the goalie in net
#   Get-XgBin $shot          the expected-goals table cell a shot falls in
# situationCode digits: away goalie in net (1/0), away skaters, home skaters, home goalie in net (1/0).
function Get-NhlSecs($p) { $t = "$($p.timeInPeriod)" -split ':'; (([int]$p.periodDescriptor.number) - 1) * 1200 + [int]$t[0] * 60 + [int]$t[1] }
function Get-NhlState([string]$code, [bool]$isHome) {
  if ($code.Length -ne 4) { return 'OT' }
  $ag = $code[0]; $as = [int]"$($code[1])"; $hs = [int]"$($code[2])"; $hg = $code[3]
  $oppGoalie = if ($isHome) { $ag } else { $hg }; $own = if ($isHome) { $hs } else { $as }; $opp = if ($isHome) { $as } else { $hs }
  $ownGoalie = if ($isHome) { $hg } else { $ag }
  if ($oppGoalie -eq '0') { return 'EN' }            # shooting at an empty net
  if ($ownGoalie -eq '0') { return 'XA' }            # own goalie pulled for an extra attacker
  if ($own -eq 5 -and $opp -eq 5) { return 'EV' }
  if ($own -gt $opp) { return 'PP' }
  if ($own -lt $opp) { return 'SH' }
  return 'OE'                                        # 4 on 4, 3 on 3
}
function Get-NhlShots($pbp) {
  $homeId = $pbp.homeTeam.id; $out = [System.Collections.Generic.List[object]]::new(); $last = $null
  foreach ($p in $pbp.plays) {
    $k = $p.typeDescKey
    if ($p.periodDescriptor.periodType -eq 'SO') { continue }
    if ($k -notin 'shot-on-goal', 'missed-shot', 'goal') { if ($k -in 'faceoff', 'stoppage', 'period-start') { $last = $null }; continue }
    $d = $p.details; if ($null -eq $d.xCoord -or $null -eq $d.yCoord) { continue }
    $isHome = $d.eventOwnerTeamId -eq $homeId
    # the net the shooting team attacks: the home team defends homeTeamDefendingSide, so it shoots at the other end
    $netX = if (($isHome -and $p.homeTeamDefendingSide -eq 'left') -or (-not $isHome -and $p.homeTeamDefendingSide -eq 'right')) { 89 } else { -89 }
    $dx = [math]::Abs($netX - [double]$d.xCoord); $dy = [math]::Abs([double]$d.yCoord)
    $dist = [math]::Sqrt($dx * $dx + $dy * $dy); $ang = if ($dx -eq 0) { 90 } else { [math]::Atan($dy / $dx) * 180 / [math]::PI }
    $secs = Get-NhlSecs $p
    $reb = [bool]($last -and $last.home -eq $isHome -and $secs - $last.secs -le 3 -and $secs -ge $last.secs)
    $s = [pscustomobject]@{ home = $isHome; secs = $secs; per = [int]$p.periodDescriptor.number; ot = $p.periodDescriptor.periodType -eq 'OT'
      dist = $dist; ang = $ang; reb = $reb; st = (Get-NhlState "$($p.situationCode)" $isHome); goal = $k -eq 'goal'; gid = $d.goalieInNetId; xg = 0.0 }
    $out.Add($s); $last = $s
  }
  return $out
}
# Table cell: distance (5 ft bands to 60, then 60+), angle (15-degree bands, 60+), rebound, and state (EV / PP / other)
function Get-XgBin($s) {
  $db = [math]::Min(12, [math]::Floor($s.dist / 5)); $ab = [math]::Min(4, [math]::Floor($s.ang / 15))
  $sb = if ($s.st -eq 'PP') { 'P' } elseif ($s.st -eq 'EV' -or $s.st -eq 'OE') { 'E' } else { 'O' }
  "$db|$ab|$([int]$s.reb)|$sb"
}

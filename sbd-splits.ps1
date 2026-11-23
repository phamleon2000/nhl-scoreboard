# Sports Betting Dime public betting (sportsbettingdime.com/<league>/public-betting-trends): % of bets and % of money
# (stake) on the spread and the total, averaged over the sportsbooks Sports Betting Dime works with, updated through the
# day. Read from the JSON feed the page's own splits table loads. Dot-sourced by money-splits.ps1 (NFL) and
# cfb-sources.ps1 (college).
#   Get-SbdSplits <nfl | ncaafb> <team mapper>
# returns rows shaped like Get-MoneySplits / Get-CfbSplits:
#   @{ src = 'SportsBettingDime'; a; h; sb = @(away %, home %); sm = @(away %, home %); ob = @(over %, under %); om = @(over %, under %) }
# The mapper gets the feed's team (abbreviation, market = school or city, name = nickname) and returns this page's
# team abbreviation, or nothing to skip the game.
function Get-SbdSplits([string]$league, [scriptblock]$toAbbr) {
  $sbdUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
  $page = @{ nfl = 'nfl'; ncaafb = 'college-football'; nhl = 'nhl' }[$league]
  $get = { param($b) (Invoke-WebRequest "https://www.sportsbettingdime.com/wp-json/adpt/v1/$league-odds?books=$([uri]::EscapeDataString($b))&format=us" -UseBasicParsing -TimeoutSec 40 -UserAgent $sbdUA `
      -Headers @{ Referer = "https://www.sportsbettingdime.com/$page/public-betting-trends/" }).Content | ConvertFrom-Json -Depth 50 }
  $feed = try { & $get 'sr:book:7612,sr:book:31520,sr:book:28901,sr:book:32784' } catch { $null }
  if (-not $feed -or -not @($feed.data).Count) {
    # The page names the books its table asks for: use those if the saved list stops working
    $html = [Net.WebUtility]::HtmlDecode((Invoke-WebRequest "https://www.sportsbettingdime.com/$page/public-betting-trends/" -UseBasicParsing -TimeoutSec 40 -UserAgent $sbdUA).Content)
    $ids = @([regex]::Matches($html, '"id":"(sr:book:\d+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($ids.Count) { $feed = & $get ($ids -join ',') }
  }
  $pct = { param($v) if ($null -eq $v) { $null } else { [int][math]::Round([double]$v) } }
  foreach ($ev in @($feed.data)) {
    $s = $ev.bettingSplits; if (-not $s -or $ev.status -ne 'not_started') { continue }   # splits stop at kickoff
    $awayAb = & $toAbbr $ev.competitors.away; $homeAb = & $toAbbr $ev.competitors.home; if (-not $awayAb -or -not $homeAb) { continue }
    $row = [ordered]@{ src = 'SportsBettingDime'; a = $awayAb; h = $homeAb; sb = $null; sm = $null; ob = $null; om = $null; line = $null; tot = $null }
    if ($s.spread -and $null -ne $s.spread.away.betsPercentage) {
      $row.sb = @((& $pct $s.spread.away.betsPercentage), (& $pct $s.spread.home.betsPercentage))
      if ($null -ne $s.spread.away.stakePercentage) { $row.sm = @((& $pct $s.spread.away.stakePercentage), (& $pct $s.spread.home.stakePercentage)) } }
    if ($s.total -and $null -ne $s.total.over.betsPercentage) {
      $row.ob = @((& $pct $s.total.over.betsPercentage), (& $pct $s.total.under.betsPercentage))
      if ($null -ne $s.total.over.stakePercentage) { $row.om = @((& $pct $s.total.over.stakePercentage), (& $pct $s.total.under.stakePercentage)) } }
    if ($row.sb -or $row.ob) { $row }
  }
}

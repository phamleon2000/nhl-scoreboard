NHL 2026-27 SCOREBOARD
======================

What's inside
-------------
NHL Scoreboard.html          Open this. Double-click it to view the scoreboard in your browser. Works with no
                             internet: scores, predictions, odds and betting splits are built into the file.
NHL Scoreboard Mobile.html   The phone edition: same data, bottom tab bar, simpler cards.
nhl-template.html            The page without data (the update builds the two pages above from it).
nhl-data.json                The data: every game, moneylines, puck lines, totals, betting splits.
update-nhl.ps1               Refreshes everything and rebuilds the pages.
maddux-odds.ps1              Reads live NHL odds from madduxsports.com (six sportsbooks).
maddux-live.js               The latest Maddux odds, re-read by the page every 30 seconds.
sbd-splits.ps1               Betting splits (% of bets vs % of money) from Sports Betting Dime.
picks-history.json           Pre-game snapshots (odds, splits), used to grade finished games. Keep it.
lines-history.json           Closing moneyline, puck line and total for each finished game. Keep it.
periods-history.json         Period scores of finished games (fetched once per game).
nhl-stats.ps1                Reads this season's games from the NHL's own API: expected goals by strength (5-on-5, power
                             play, shorthanded), empty-net goals, 1st-period goals, penalties, starting goalies and ice
                             time; probable goalies from DailyFaceoff; injuries from ESPN.
nhl-pbp.ps1                  Shot reader shared by the two scripts here (distance, angle, rebound, strength).
xg-build.ps1                 Builds xg-table.json, the expected-goals table, from all 2025-26 shots. Already run; run it
                             again only to rebuild the table (about 10 minutes).
xg-table.json                The expected-goals table (109,422 shots from last season).
nhl-stats-history.json       Each finished game's stats, read once. Keep it.

THE PREDICTION FRAMEWORK
------------------------
The NHL picks follow your "NHL Next Game Prediction Framework". The "How it works" tab lists every rule. In short:
- Each game is forecast only from information known before it (earlier games, the goalies and injury list saved
  before the game, the pregame price). Expected goals come from 5-on-5 strength, special teams, finishing, the
  starting goalie, schedule (back-to-backs, travel, road trips) and lineup absences, then a Poisson score model
  corrected for ties, empty-net goals and overtime / shootout.
- Every priced market shows Raw P (the model), Market P (price with the bookmaker's cut removed) and Final P (a blend
  whose weight is fit on earlier weeks only), plus fair odds, expected return, the worst playable price, goalie
  status and a backup-goalie check.
- Release status per market: UNTESTED / PROVISIONAL / VALIDATED / SUSPENDED, with the rules fixed in advance.
- PLAY only when the market is PROVISIONAL or VALIDATED, Final P is 45%+, expected return is +3%+, both goalies are
  Confirmed or Likely, and the edge survives a backup goalie. Otherwise PASS. Top 3 only when three qualify.
- Picks tab: "Final Card · Top 3" with every candidate. Results tab: "Framework validation" (log loss vs the market,
  probability groups 55%+ / 60%+ / 65%+, calibration, units, closing line value, model checks).
- Games before Oct 24 were graded at ESPN's closing price with the actual starting goalies, since no pregame report
  was saved for them. From Oct 24 on, each update saves the pregame price, probable goalies and injuries.
- Run "Update NHL Scoreboard.bat" at least once on each game day (ideally late afternoon) so the pregame report is
  saved before the games start.
Live Odds.bat                Double-click on game nights: opens the page and refreshes the odds every 30 seconds.
Update NHL Scoreboard.bat    Double-click to update now. Opens the page when done.

How the NHL page differs from the football pages
-------------------------------------------------
- The main pick is the MONEYLINE (who wins, overtime and shootout included), shown as "BOS ML -125".
  It is the side our model rates higher than the sportsbooks do. The win chance is shown next to the
  chance the price needs ("57% to win (needs 58%)").
- No weather, indoor/outdoor, day/night, 1st/2nd half picks, deep matchup or playoff odds.
- Scores and edges are in goals. Rest factor: back-to-backs.
- Safety check: until the model's disagreements with the market have actually predicted results
  (100+ games tested), every moneyline pick gets a red flag and a PASS decision.
- "Use my own line": leave the puck line empty for the moneyline, or type -1.5 / +1.5 to pick and grade
  on the puck line instead.
- My picks keep the moneyline price, so My money pays each pick at its own price.

Updating the data
-----------------
Keep all the files in the same folder. Double-click "Update NHL Scoreboard.bat" (needs internet, a few
minutes the first time). The output of the last run is saved in last-update.log.

PHONE (Mobile.html): copy just that one file to the phone. With internet it gets live scores from ESPN and, for games that
haven't started, live DraftKings odds through ESPN (refreshed every minute; picks and bet decisions update on the new lines).
Live Odds.bat on the PC gives six sportsbooks instead. It also re-reads Action Network's % of bets and % of money every minute,
so sharp money, picks and bet decisions update with it (the other split sites update when you run Update).
Copy the new Mobile.html to the phone after each update.

LIVE ODDS SOURCE: live scores and the full-game lines every pick uses come from ESPN (DraftKings), refreshed every
minute before games, on the PC and the phone. Live Odds.bat (Maddux Sports) is now only needed for the 1st- and 2nd-half
lines and the other sportsbooks' columns in the Live odds table.

Update fix - Nov 14: pre-game snapshots stop at kickoff
-------------------------------------------------------
ESPN's schedule feed can keep a game marked "not started" for hours after kickoff, and the update used to keep
overwriting that game's pre-game snapshot (lines, betting splits, sharp money) with in-game numbers. Finished games were
then graded on in-game data (Nov 14 college football: NMSU@MOST, SJSU@AFA and UTAH@ARIZ lost their TOP BET that way).
Now a game counts as not started only while ESPN says so AND its kickoff time hasn't passed (Test-Pre in the update
script): snapshots, the books' lines, 1st-half lines and the "closing line" all stop at kickoff. Snapshots already
overwritten before this fix can't be recovered. Backup of the old script: *.bak-before-kickoff-guard.

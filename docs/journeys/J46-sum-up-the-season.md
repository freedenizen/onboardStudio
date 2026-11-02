# J46 Sum up the season
*Source: #355 — at the end of a year the driver had the logbook's rows and no page that said what
happened: how many days and laps, how far, which bests fell, which corner improved most, what is
still planned.*

1. **Window ▸ Logbook**, switch the toolbar's view to **Season**; pick the **Year** (newest first)
   and, with more than one car, the **Car**.
2. The page: track days, sessions, laps and kilometres; personal bests set; the best at each
   circuit with its date, car and visits, starred when it was a new personal best; a chart of every
   circuit's best lap by visit; the most improved and the most costly corner against the visit
   before; and the plans still open at the circuits visited.
3. **Export as PDF…** writes the page for printing; **Export Card…** writes a 1080 × 1920 picture
   of the title and the headline lines, the Social template's shape, to post.

Tests: `SeasonUITests.testTheSeasonPageSumsTheYearAndExportsACard`. Model: `SeasonSummaryTests`.

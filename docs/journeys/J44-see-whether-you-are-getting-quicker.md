# J44 See whether you are getting quicker
*Source: #353 (and #332) — the question after a season is simple, am I faster than in April and
where, and nothing in the app could answer it; every logbook draws the lap-time chart.*

1. **Window ▸ Logbook**, pick a circuit in the sidebar (or let the only one stand), and switch the
   toolbar's view to **Trends**.
2. The chart draws the best, optimal and fastest rolling lap of every session, evenly spaced in
   the order they were driven (or entered when the file carries no date) and grouped by track day:
   the date under each day, a dashed line between days, so a day of six sessions and a gap of
   months both read (#424). The line under the title says how far the best moved — with several
   sessions a day, from the best of the first day to the best of the last. Narrow to one **Car**
   when the logbook has more than one there. Click a point to open that session in the Sessions
   view.
3. **Consistency** shows each session's spread of flying laps, one bar under each point of the
   chart above; lower is steadier.
4. **Corner by corner** reads the best lap of the latest track day against the best of the track
   day before and the personal best, and says which laps those are (#426): brake point, minimum
   speed and time in corner, with the differences. A comparison with nothing to compare — no
   earlier day, or the latest day set the personal best — has no columns. Sessions entered
   before corners were kept get a **Read Their Corners** button that reads their files once.
5. VoiceOver reads the charts as sentences.

Tests: `LogbookTrendsUITests.testTrendsReadAcrossTwoVisits`. Model: `LogbookTrendsTests`.

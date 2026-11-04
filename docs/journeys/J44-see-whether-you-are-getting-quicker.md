# J44 See whether you are getting quicker
*Source: #353 (and #332) — the question after a season is simple, am I faster than in April and
where, and nothing in the app could answer it; every logbook draws the lap-time chart.*

1. **Window ▸ Logbook**, pick a circuit in the sidebar (or let the only one stand), and switch the
   toolbar's view to **Trends**.
2. The chart draws the best, optimal and fastest rolling lap of every visit (by the day it was
   driven, or entered when the file carries no date); the line under
   the title says how far the best moved and over how many visits. Narrow to one **Car** when the
   logbook has more than one there. Click a point to open that session in the Sessions view.
3. **Consistency** shows each visit's spread of flying laps; lower is steadier.
4. **Corner by corner** reads the latest visit against the one before and the personal best's
   session: brake point, minimum speed and time in corner, with the differences. Sessions entered
   before corners were kept get a **Read Their Corners** button that reads their files once.
5. VoiceOver reads the charts as sentences.

Tests: `LogbookTrendsUITests.testTrendsReadAcrossTwoVisits`. Model: `LogbookTrendsTests`.

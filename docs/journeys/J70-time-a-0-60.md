# J70 Time a 0–60
*Source: #553. Every GPS performance meter gives 0–60, the quarter mile and 60–0 without being
asked, and the data the app reads holds them. Before this, a driver with a drag-strip or test-road
log had to work them out by hand to tell whether a change made the car quicker in a straight line.*

1. Add a log with no laps and no runs to the Logbook: a drag strip, a test road.
2. Select it. Its **Performance** section lists each standing start as **Start 1**, **Start 2**, …
   with a column for each measure it reached. These are 0–30, 0–60, 0–100 and 60–130 mph (or the
   km/h set), then 60 ft to ¼ mile with trap speeds at the eighth and the quarter. Below them each
   **Stop** from 60 mph shows its distance and time. The best of each is in the accent colour; a
   note says when a start was on a slope or logged under 10 Hz.
3. Turn off **Performance runs**: the numbers go. **Edit ▸ Undo Turn Off Performance Runs** brings
   them back. On a circuit's session the switch starts off, and turning it on measures the
   session's standing starts.
4. In a project, the same switch is under **Laps** in the data file's inspector. A Stat Card's
   **0–60 time**, **Quarter mile** and **60–0 braking distance** rows show the best, or the start
   at the playhead.

Tests: `PerformanceUITests.testAStraightLineLogIsTimedLikeAPerformanceMeter`. Model:
`PerformanceRunsTests`, `PerformanceResultsTests`, `PerformanceImportTests`, `PerformanceEntryTests`,
`StatCardTests.theSessionCardShowsTheBestLaunchQuarterMileAndStop`.

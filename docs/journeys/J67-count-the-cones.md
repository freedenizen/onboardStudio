# J67 Count the cones
*Source: #552 — an autocross run's time counts with its cones, and a run that went off course
counts not at all, but the Logbook kept only the clock's time, so the best run, the personal best
and Trends could be a run that never counted.*

1. Select a session of runs in the Logbook. Each run lists the time that counts, its **cones**
   and a **DNF** box; a run that never reached the finish is a DNF already.
2. Add a cone to a run: its time goes up by the day's penalty, the clock's time and the cones show
   beneath it, and if it was the best run another may be the best now. **Edit ▸ Undo Change Cones**.
3. Tick **DNF** on a run that went off course: it shows DNF and no longer counts.
   **Edit ▸ Undo Mark Off Course**.
4. On the day, **Per cone** sets the penalty for every run on it (2 s to begin with).

Tests: `ConesUITests.testConesAndAnOffCourseDecideWhichRunCounts`. Model: `RunPenaltyTests`.

# J68 Let the driving suggest the lines
*Source: #552 — timing an autocross or a hill climb in runs meant placing a start line and a finish
line by hand, at the preview position, for a file that carried no gates.*

1. Add a data file of a point-to-point course with no gates of its own, select it, and under
   **Laps** set **Timing** to **Runs**.
2. The status line says *Suggested a start where 3 runs set off and a finish where 2 of them
   ended; check both on the map*, and the inspector lists the runs, the one that went off course a
   **DNF**.
3. **Suggest Start and Finish from the Data** asks again; the preview-position buttons and the
   fields move either line. **Edit ▸ Undo Time in Runs** goes back to laps.

`onboard probe <file> --suggest-runs` prints the same lines as `--lap-line` and `--finish-line`.

Tests: `SuggestedRunLinesUITests.testChoosingRunsSuggestsTheStartAndTheFinish`. Model:
`RunLineFinderTests`.

# J65 Time an autocross in runs
*Source: #552 — an autocross, a hill climb or a rally stage could not be timed: laps came only
from one start/finish line, and a VBO file's finish gate was read and then ignored.*

1. Add a data file recorded on a point-to-point course. A VBO file with a start and a finish gate
   is timed in runs at once; for any other file, select it and set **Timing** to **Runs** under
   **Laps** in the inspector, then put the start and the finish where the preview shows them.
2. The inspector lists each run with its time. A run that never reached the finish says **DNF**;
   the driving back to the start between runs is not listed.
3. **Timing ▸ Laps** goes back to laps; **Edit ▸ Undo Time in Laps** brings the runs back.
4. **Marker ▸ Next Lap** (⌥↓) goes to the first run and the status line says *Run 1*.

Tests: `RunsUITests.testAFileWithAStartAndAFinishIsTimedInRuns`. Model: `RunDetectorTests`,
`RunImportTests`, `RendererBehaviourTests.aTimerDuringARunSaysRunAndBetweenRunsShowsNoNumber`.

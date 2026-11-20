# J77 Look at laps as data
*Source: #556 — delta-T, overlaid speed traces and a map that points to the same place on every
trace existed only as overlay objects placed by hand in a project, so checking one corner's traces
meant building a video.*

1. In the Logbook, choose a session and click **Analyse Laps…** (also on the row's right-click menu
   and in the menu bar's session menu), or open a project and choose **Window ▸ Analysis**.
2. The session's quickest lap is the reference and its next quickest is laid over it. Tick up to
   four laps in the list, from this session or another at the circuit in the Logbook; the first
   ticked is the reference, and **Make Reference** on a lap's right-click menu changes it.
3. **Delta-T** shows how far each lap is behind the reference along the lap, **Speed** each lap's
   speed, and any channel added from **Panels ▸ Add Trace** (throttle and brake to begin with)
   under it. Move the pointer over any trace: the cursor moves on every trace, the cars move on
   the map and the friction circle, and the line above reads each lap's time, gap and speed there.
   The friction circle's dashed line is the car's grip in conditions like these, from the Logbook
   (#631): points short of it in a direction are grip left there.
4. Click a corner on the map, or choose one from **Go to Corner**, and the traces zoom to it from
   the braking into it to the drive out; **Whole Lap** shows the lap again.
5. **Panels** shows or hides delta-T, speed, the map and the friction circle, adds or removes
   traces, and makes them taller or shorter; the window opens the same way next time.
6. When a lap has video — the project's own picture, or a Logbook day's clip that the camera's
   clock puts the lap in — **Picture** above the map shows it at the cursor. **Play** runs it from
   there, the cursor following round every trace; with more than one lap filmed, the pop-up beside
   it chooses whose picture.
7. The same view is in two more places: **Data** in the Coaching window's toolbar, which starts
   on the coached lap against Coaching's reference, and **Analysis** in the Logbook (**View ▸
   Analysis**, ⌘4), which shows the session selected under Sessions.

Tests: `LapAnalysisUITests.testALogbookSessionsLapsAreLaidOverEachOther`,
`LapAnalysisUITests.testCoachingAndTheLogbookShowTheLapsAsDataToo`,
`LapAnalysisUITests.testAProjectsLapsShowTheirPicture`. Model: `LapAnalysisTests`,
`AnalysisLayoutTests`, `GripTargetTests`, `GripOutlineTests`.

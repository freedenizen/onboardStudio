# J33 Find where the time went
*Source: #321, #322 — every coaching product surveyed ranks the corners by time lost and says what to
change; the app showed sector deltas and left the rest to the driver.*

1. **Project ▸ Coaching…** (⌃⌘C), then **All Corners** in the toolbar (the window opens on the
   walkthrough, J57, until All Corners was used last). It reads the lap at the playhead against
   the session's best lap. The headline says how far behind it finished and how the two were
   lined up.
2. Choose the **Lap** to read and what it is **Compared with**: the best lap, the fastest rolling
   lap, the optimal lap spliced from the best sectors, another lap, or a lap of another data file.
   **Line up by position** matches two laps of one session by where the car was instead of metre
   for metre, for a corner driven two different ways on purpose (#333).
3. Read the **Opportunities**: the three corners that cost the most, each with the phase, what
   happened and what to try. **Show Me** moves the playhead to where braking began for that corner
   on the lap being read, and the preview shows it.
4. Sort the **corner table** by any column — time lost, brake point, minimum speed, exit speed,
   throttle, consistency — and select a row to go to that corner's turn-in. The corner's detail
   opens beside the table: the time lost per phase, both laps' readings with their sources, and
   the two lines through the corner with brake points and slowest points marked.
5. **Compare in Video** lays the project out with both laps' pictures over that corner, the
   export range set to it; **Undo Compare Laps** puts the layout back.
6. **Undo** steps back through the lap and reference choices; both are saved with the project.

Tests: `CoachingUITests.testTheCoachingWindowRanksCornersAndShowsThem`. Model:
`CoachingAnalysisTests`, `CornerMetricsTests`, `CoachingReferenceTests`, `LapAlignmentTests`,
`CoachingSettingsTests`.

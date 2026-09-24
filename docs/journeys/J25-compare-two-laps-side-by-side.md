# J25 Compare two laps side by side
*Source: #154 — the way to see where a lap was lost is two laps playing side by side, locked by
distance so the same corner arrives at the same moment; nothing did it for video.*

1. **Project ▸ Compare Laps…**. The sheet offers the lap at the playhead against the session's best
   (or the next lap, when the playhead is on the best). Each side can be any complete lap of any
   data file in the project, with the camera that filmed it — two laps of one session, or today
   against last month.
2. Choose **Side by side** or **Stacked** and **Compare**. The objects are replaced by the
   comparison layout: each lap's picture with its lap timer and speed, and the delta between them.
   The playhead goes to the start of the lap and the export range becomes the lap.
3. Play: the compared lap is slowed down and sped up so both pictures reach every corner together.
   The delta says how far ahead (−, green) or behind (+, red) the lap playing is at that point.
4. Any object can be switched to **Shows the compared lap** in its inspector. **Undo** puts the old
   layout back; **Project ▸ Stop Comparing Laps** removes the compared lap and keeps the rest.

Tests: `CompareLapsUITests.testComparingLapsLaysOutBothAndStoppingKeepsTheLap`. Model:
`LapTimeWarpTests`, `ComparedLapTrackTests`, `CompareLapsLayoutTests`.

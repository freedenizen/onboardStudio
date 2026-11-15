# J72 Leave a lap that doesn't count out
*Source: #554 — a lap spoiled by traffic, a flag or an off counted like any other lap, so it could
be the session's best, feed the optimal lap and the personal best, and widen the consistency
figures; and the driver could not see which laps the optimal lap came from.*

1. Select a session in the Logbook. Its detail lists every lap with a **⋯** menu, and the
   **Optimal lap** row names the laps it is spliced from.
2. On the best lap, choose **⋯ ▸ Off Track** (or right-click it): the lap reads "left out: off
   track" in grey, and **Best lap** moves to the quickest lap that counts. The optimal and rolling
   laps, the personal best, Trends, goals and consistency follow.
3. **Edit ▸ Undo Leave Lap 7 Out** counts it again, and the best lap is what it was.
4. In the Coaching window, the picker beside **Lap** does the same for the lap being read: from
   **Counts** to **Left Out: Traffic**, **Flag**, **Off Track** or **Other**. When the telemetry
   suggests traffic on it, the walkthrough's first step offers **Leave Lap 7 Out**.
5. `onboard coach session.csv --leave-out 5,9:flag` does it from the command line.

The video counts every lap as it was driven: the overlays are unchanged by a lap left out.

Tests: `LapsLeftOutUITests.testALapLeftOutIsNoLongerTheBest`. Model: `LapMarksTests`,
`LapMarksLogbookTests`, `CoachingSettingsTests.lapsLeftOutRoundTripApplyToTheirInputAndAreAbsentInOlderSettings`.

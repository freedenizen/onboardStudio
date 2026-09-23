# J3c Jump between laps
*Source: RaceChrono and TrackAddict both list laps and seek to them.*

1. With a video and a data file loaded, the data gets its own timeline bar with a divider at each
   lap boundary.
2. **Marker ▸ Next Lap** (**⌥↓**) moves to the next lap and names it in the status line with its
   time; **Previous Lap** (**⌥↑**) goes back.
3. Before the first lap the status line says there is no lap that way rather than sitting silent.

Tests: `LapUITests.testJumpsBetweenTheLapsOfTheDataFile`. Model: `LapNavigationTests`.

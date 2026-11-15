# J71 Read a session lap by lap
*Source: #557: a session's laps in the Logbook were a number and a time each. Where in the lap the
time came and went, which lap had the best sector, how far each lap was off the best and how fast
each went meant opening a project or the Coaching window.*

1. Choose a session in the Logbook. **Laps** lists every lap with its time, its gap to the best
   lap, its sector times (S1, S2, S3) and its top and lowest speed.
2. Read down a column. The quickest S1, S2 and S3, the best lap and the best top and lowest speeds
   are in the accent colour; a sector the lap did not time is a dash, and an unfinished lap says
   *partial*.
3. Choose a session added before the Logbook kept sector times. They are read from its file while
   a line under the laps says so, and the columns fill in; nothing else about the session changes.

Tests: `LapSectorsUITests.testASessionsLapsShowTheirSectorsAndTheBestOfEach`. Model:
`LapSplitsTests`.

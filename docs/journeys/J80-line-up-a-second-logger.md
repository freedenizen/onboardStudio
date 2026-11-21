# J80 Line up a second logger by what both recorded
*Source: #562 — an ECU or CAN logger's CSV has RPM, throttle, pressures and temperatures but no
GPS, and its clock seldom agrees with the GPS logger's; video lines up by motion, but a second data
file only by its timestamps or by hand, so its channels drifted against the lap.*

1. Add the GPS logger's file to a project, then the second logger's.
2. Select the second file. Its **Synchronization** gains **Line Up with *first file***, a menu of the
   channels both files recorded, RPM first, then speed, throttle and G.
3. Choose one. The second file slides along until that channel reads as it does in the first, and
   the status line says where it begins against the first and how well it matched (*Lined up by
   rpm: ecu.csv begins 37.50 s after session.csv (match 0.98)*). It is one step of **Edit ▸ Undo**.
4. When the match is not clear — revs that barely change, a channel that means something else in
   each file — nothing moves, and the status line says to try another channel or set the offset by
   hand.

Tests: `DataAlignmentUITests.testASecondDataFileIsLinedUpByItsRPM`. Model: `DataAlignmentTests`.

# J64 Set a goal and follow it
*Source: #461 — the app recorded what happened, and nothing of what the driver was aiming for: no
target lap time at a circuit, no target for a corner or for consistency, and nothing in Trends or
Season that said how far there was to go or that a target was reached.*

1. In the Logbook, choose the circuit under **Circuits**. On its card, **Add Goal…**: a lap time,
   consistency (flying laps within so many seconds), or a corner's time or apex speed, in any car
   or one, by a date if you like.
2. The goal is listed on the card with how far there is to go, or the day it was reached. The
   minus removes it; **Edit ▸ Undo Remove Goal** brings it back.
3. **Trends** draws a lap-time goal as a dashed line across the lap-time chart, and a consistency
   goal across the consistency chart, and says so beneath them.
4. After the next day's files are added, the report says *Goal reached: 1:40.00 lap at Sonoma
   Raceway* or how much closer the day came.
5. The **Season** lists the goals reached in the year, on screen and in its PDF.

Tests: `GoalsUITests.testALapTimeGoalIsFollowedOnTheCardTrendsAndSeason`. Model: `GoalTests`.

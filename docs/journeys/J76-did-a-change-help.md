# J76 Did a change help
*Source: #559 — Trends narrowed only by circuit and car, so "were my laps quicker on the new tyres?"
or "did dropping the rear pressure help through turn 4?" could not be answered, and a gain in one
corner lost in another went unseen.*

1. Note the tyres, a setup (J75) or the conditions on the sessions at a circuit.
2. In the Logbook, choose the circuit and **Trends**. Under the summary, a pop-up for each of
   **Tyres**, **Setup**, **Surface** and **Weather** that the sessions noted two or more of narrows
   every chart and table to the sessions driven that way; **Show All** puts the rest back.
3. **Before and after**, below the corners, splits what is left by one thing the sessions differ
   by — the tyre set, the setup, the surface, the weather, or any one value of the setup sheet, such
   as *Cold Pressure, Rear Left* — and reads the two sides against each other: sessions, each
   session's best averaged, the best, the optimal and the lap spread, then every sector and every
   corner (*Quicker in sector 1; slower in sector 2*).
4. It says when the difference may not be the change: one session on a side, or every session of
   one side on another surface, tyre set or in other weather.

Tests: `SetupTrendsUITests.testTrendsSplitTheSessionsByTheirTyres`. Model: `SetupComparisonTests`.

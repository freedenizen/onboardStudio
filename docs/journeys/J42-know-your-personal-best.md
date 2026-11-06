# J42 Know your personal best
*Source: #351 — the app's best lap was the best of one session; drivers think in personal bests: at
this circuit, in this car, this year, ever. With the logbook that is a question it can answer.*

1. **Window ▸ Logbook**: the **PB** column marks every session that set a personal best at its
   circuit when it was driven — overall, or in its car: a filled star on the session that holds it
   now, a hollow one on a session since beaten (#422). Select a session: the detail's **Personal
   best here** says the best at that circuit, when, in what, and how many visits — track days —
   the logbook has.
2. In a project, a **Text** object or a **Title Card** can show `{pb}`, `{pbDate}`, `{pbCar}` and
   `{visits}`: the personal best at the circuit the project's data is at — in the project's car
   when the logbook has one there, else overall — filled at render time from the logbook, so a
   detail you typed under the same name still wins.
3. A **Timer** in *Delta* or *Projected lap* mode can **Compare with ▸ Personal best (logbook)**:
   the gap to the personal best lap at the same distance into the lap, that lap's session read on
   demand; when the personal best is this very session, or the logbook has none here, it measures
   the session best as before.

Tests: `PersonalBestUITests.testTheLogbookBadgesAndNamesThePersonalBest`. Model:
`PersonalBestsTests`, `PersonalBestTimerTests`, `LogbookDerivedTests`.

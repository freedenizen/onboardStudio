# J16 Say what the session was, once
*Source: #74 — "Sonoma · 2026-08-23 · M2" had to be typed into a Text object in every project.*

1. Add a RaceChrono file. **Project ▸ Show Project Details** (⌃⌘I): **Track** and **Driver** are
   already filled in from the file.
2. Type the **Car**. *Add Detail…* → *Tyres* adds a detail of your own.
3. **Add Object ▸ Title Card** reads `{track} · {date}` and draws the track and day.
   **Insert Detail** lists *Car (M2 Competition)*; choosing it appends `{car}`, and ⌘Z takes it
   back.

Tests: `DetailsUITests.testDetailsFillFromTheDataAndATitleCardShowsThem`. Model:
`ProjectDetailsTests`, `SessionDetailsTests`, `DetailTextRenderTests`.

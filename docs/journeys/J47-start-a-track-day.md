# J47 Start a track day
*Source: #392, #393 — a track day is a thing before it is files: a driver knows the date, the circuit
and the car on the way there, and wants somewhere to write the conditions once. Every tool a season
is kept in groups sessions under a day or an event first.*

1. **Window ▸ Logbook**, then **New Track Day…** in the toolbar (or **File ▸ New Track Day…**,
   ⌥⌘N, from anywhere). The sheet asks the date, the circuit (search the catalogue, or keep a name
   as typed), the car (with the cars the logbook knows a click away), the driver, the weather and
   the track, and notes.
2. **Create**. The day appears under **Track Days** in the sidebar — "23 Aug 2026 · Sonoma
   Raceway", under its year when the logbook spans more than one — chosen, with its header above
   an empty table: *No sessions yet. Add Sessions… or drop the day's files here.* The car and
   driver are fields in the header; **Conditions and Notes** fold out under it. Edits are kept as
   they are made, as a session's conditions are.
3. **Add Sessions…**, or drop the logger's files on the window: each goes on this day, with the
   day's car, driver and conditions to begin with. The sheet says what happened to each file.
4. **Add Files…** with no day chosen still works as before: each file goes on the day its date and
   circuit say, made if need be, and the sheet's line says which (*…, in 23 Aug 2026 · Sonoma*).
   Sessions from before days existed are placed the same way the first time the window opens.
5. **Remove Track Day…** (the trash button in the header) takes the day and its sessions out of
   the logbook; the files are not touched.

Tests: `TrackDayCreateUITests.testADayIsBegunAndItsSessionsAddedUnderIt`. Model: `TrackDayTests`,
`TrackDayImportTests.filesGoOnTheChosenDayOrOnTheDayTheySay`.

# J47 Start a track day
*Source: #392, #393 — a track day is a thing before it is files: a driver knows the date, the circuit
and the car on the way there, and wants somewhere to write the conditions once. Every tool a season
is kept in groups sessions under a day or an event first.*

1. **Window ▸ Logbook**, then **New Track Day…** in the toolbar (or **File ▸ New Track Day…**,
   ⌥⌘N, from anywhere). The sheet asks the date, the circuit (search the catalogue, or keep a name
   as typed), the car (with the cars the logbook knows a click away), the driver, the weather and
   the surface (dry, damp, wet…), and notes.
2. **Create**. The day appears under **Track Days** in the sidebar — "23 Aug 2026 · Sonoma
   Raceway", under its year when the logbook spans more than one — chosen, with its header above
   an empty table: *No sessions yet. Add Files… or drop the day's files here.* The car and
   driver are fields in the header; **Conditions and Notes** fold out under it. Edits are kept as
   they are made, as a session's conditions are.
3. **Add Files…**, or drop the logger's files on the window: each goes on this day, with the
   day's car, driver and conditions to begin with. The sheet says what happened to each file. A
   file with no circuit of its own takes the day's, and its line says so.
4. If some of the files are not from this day — dated another day, or recorded at another circuit
   (#456: the wrong folder, last month's, or the parent of several days) — the sheet adds the
   ones that could be the day's and asks about the rest: *3 of these 8 files are not from
   23 Aug 2026 · Sonoma Raceway*, each listed with what is different. **Put on Their Own Days**
   (the default) files each on the day its own date and circuit say; **Add to This Day** puts
   them on this day anyway, for a logger or a camera whose clock was wrong; **Leave Them Out**
   adds none of them. Nothing is filed for them before the answer. When the new days are in
   other years, the sidebar folds its days under their years; the year of the day you are on
   stays open, with its row selected (#485).
5. **Add Files…** with no day chosen still works as before: each file goes on the day its date and
   circuit say, made if need be, and the sheet's line says which (*…, in 23 Aug 2026 · Sonoma*).
   Sessions from before days existed are placed the same way the first time the window opens.
6. **Remove Track Day…** (the trash button in the header) takes the day and its sessions out of
   the logbook; the files are not touched.

Tests: `TrackDayCreateUITests.testADayIsBegunAndItsSessionsAddedUnderIt`,
`TrackDayCreateUITests.testFilesOfOtherDaysGoOnTheirOwnDaysWhenToldTo`. Model: `TrackDayTests`,
`TrackDayImportTests.filesGoOnTheChosenDayOrOnTheDayTheySay`, `TrackDayStraysTests`.

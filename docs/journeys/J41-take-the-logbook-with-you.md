# J41 Take the logbook with you
*Source: #350 — years of track days should survive a new Mac, be sharable with an instructor and
readable by other tools; a logbook you cannot take with you is a trap.*

1. **Window ▸ Logbook**, then the **Export or Import** menu in the toolbar. Narrow the table first
   (a circuit, a car, a year, a search) to export only that; otherwise everything goes.
2. **Export Logbook…** writes a `Logbook` folder of one file per session plus the garage into the
   folder you choose; **Export Logbook with Data Files…** copies each session's data file in
   beside them, so the folder is complete on another Mac.
3. **Export Sessions as CSV…** (one line per session: date, circuit, car, driver, laps, best,
   optimal, rolling, top speed, conditions, notes, file) and **Export Laps as CSV…** (one line per
   lap) for a spreadsheet; **Export Logbook as Markdown…** for a coach: a table of the sessions, then
   each session's laps and notes.
4. **Import Logbook Export…** reads such a folder back: a session already here (the same bytes) is
   skipped, or updated when the file's copy is newer; copied data files are found beside their
   entries; cars join the garage. The line under the table says what happened.
5. From the command line: `onboard logbook export <folder> [--with-files]`,
   `onboard logbook export sessions.csv [--laps]`, `onboard logbook export season.md`,
   `onboard logbook import <folder>`.

Tests: `LogbookTransferUITests.testTheLogbookExportsAsAFolderAndAsCSV`. Model:
`LogbookTransferTests`.

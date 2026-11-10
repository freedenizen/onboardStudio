# J37 Add a track day to the logbook
*Source: #345, #346 — a track day is five to eight files and a season twenty of those; nobody adds a
hundred files one project at a time, so a logbook that only filled that way would stay empty.*

1. **File ▸ Add Track Day to Logbook…**, choose the day's telemetry files and camera clips, or
   the folders they are in.
2. The sheet reads them one by one and says what happened to each: *added: Sonoma, 12 laps, best
   1:56.88*; *already in the logbook as …*; *the same session as session_v3.csv, already in the
   logbook: …*; *not a telemetry file this app reads*; *no position or laps in it*. The circuit is
   recognised, the date read from the file, the car taken from your last session at that circuit.
3. **Done**. The status bar says how many sessions were added. The same files added again are
   skipped, whatever they are called now — and so is a session in a second export format (a
   RaceChrono CSV beside its `.rcz`, or v2 beside v3): one drive is one session (#465).
4. From the command line: `onboard logbook add <files or folders> --car Miata` and
   `onboard logbook list`.

Tests: `TrackDayUITests.testAFolderOfSessionsIsEnteredAndReportedPerFile`. Model:
`TrackDayImportTests` (`theSameSessionInASecondFormatIsNotAddedAgain` among them),
`LogbookSameSessionTests`, `LogbookTests`.

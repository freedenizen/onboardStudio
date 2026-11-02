# The logbook: every track day in one place

*Milestone D (v0.32.0, GitHub milestone #12). Issues #345–#350.*

## The gap

A project remembers the data files it was made from and nothing else does. The track library
(`docs/tracks-and-sectors.md`) remembers a circuit's start/finish, sectors and corner names, so the
app knows *where* a new file was recorded — but not that the driver was there before, in which car,
what the best lap was or which file holds it. Twenty track days in three cars are twenty folders of
logger files and nothing that reads across them. Every tool people keep a season in has a session
list as its foundation: AiM's Race Studio groups a session database by date, vehicle and event;
Garmin keeps a history across days, years and cars; ApexLog, Track Evolution and Track Attack are
logbooks first and analysers second.

## The shape (#345)

`LogbookEntry` (`Sources/ProjectModel/Logbook.swift`) is one session as numbers without samples:

- **the file** — its path when added, a security-scoped bookmark that follows a move (a plain
  bookmark when the scope cannot be had), the SHA-256 of its bytes and their count, and the
  importer that read it. The hash is how the same file is never entered twice, whatever it is
  called or wherever it lives; `resolveFile()` tries the bookmark, then the path;
- **where and when** — the circuit's Wikidata id when `CircuitCatalog` recognised it, the file's
  own track name, and the date the file carries (`SessionInfo.createdAt`); `title` is the circuit,
  else the track name, else the file's name;
- **what** — the car (typed once, remembered per circuit by the import) and the driver (the file's,
  else typed);
- **the laps** — number, time and completeness for each, and the session's best (with its number),
  optimal (`SessionStats.optimalLap`, the best sectors spliced) and **fastest rolling lap**
  (`CoachingReference.fastestRolling`), and the top speed in m/s;
- **words** — notes and tags now; weather, track condition, temperature, tyres and setup come with
  #348, as optional keys the decoder already tolerates;
- **the projects** made from it, by path and name (#349 fills them in);
- `added` and `modified`.

Every key but `file` is optional on the way in, so an entry written by any build reads in any
other; dates are ISO 8601, like the track definitions.

`Car` is the garage: a name and notes. Cars are a list in `garage.json`, not a table — a driver
has three, not three hundred.

`Logbook` is the library: one `<uuid>.onboardsession` JSON file per entry and the garage file in
`~/Library/Application Support/OnboardStudio/Logbook`, beside `Tracks` and `Templates`, read and
written through the same pattern as `TrackLibrary` (`entries()` newest session first, `save`
stamps `modified`, unreadable files are skipped rather than failing the list). Separate files, as
the tracks are, so a season can be copied, backed up, diffed or handed over as files; a selection
export and a merge-by-hash import are #350. **Local only: nothing is uploaded.**

What is deliberately not here: samples (the file has them; an entry is a card, not a copy),
sector times per lap (read from the file when the detail pane wants them, #347), and anything a
later build might compute differently from the same file — an entry records what the app read
when it was added, like a project does, and is re-read only when the user asks.

## Adding a track day (#346)

`TrackDayImport` (`Sources/MediaKit/TrackDayImport.swift`) takes files and folders: folders are
walked (hidden files and packages left alone) for every importer's extensions plus camera clips;
each file is hashed first and skipped when the logbook already has those bytes; `FormatDetector`
names the importer; the session is built with default options and the circuit identified; a file
with no laps at a circuit whose start/finish the track library knows is read again with that line,
as adding it to a project would; the car is the batch's, else the last session's at that circuit;
the driver is the batch's, else the file's, else the last session's. Every file gets a `Report`
whose `line` is the sentence the sheet and the CLI print. Project ▸ Add Track Day to Logbook… runs
it off the main thread behind a sheet (`TrackDayImportSheet`); `onboard logbook add` and `list`
do it on the command line. Under UI tests the app's logbook is a scratch folder
(`ONBOARD_TEST_LOGBOOK_DIR`), as the templates are.

## What comes next

#347 the Logbook window (with drag-and-drop onto it); #348 conditions; #349 the two-way link with projects; #350 export, import,
CSV and Markdown. Milestone E (#351–#355) reads across the entries: personal bests, logbook laps as
coaching references, trends per corner, car against car, a season summary.

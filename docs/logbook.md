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
whose `line` is the sentence the sheet and the CLI print. File ▸ Add Track Day to Logbook… runs
it off the main thread behind a sheet (`TrackDayImportSheet`); `onboard logbook add` and `list`
do it on the command line. Under UI tests the app's logbook is a scratch folder
(`ONBOARD_TEST_LOGBOOK_DIR`), as the templates are.

## The window (#347)

`LogbookWindow` (`Sources/OnboardStudioApp/LogbookWindow.swift`), Window ▸ Logbook, ⌃⌘L — a
`Window` scene like Attributes and Coaching, not a document: a `NavigationSplitView` whose sidebar
is the scopes `LogbookFilter` computes (all, circuits by most sessions, cars, years) and whose
detail is an `HSplitView` of a sortable `Table` and `LogbookDetail`. `LogbookFilter`
(`ProjectModel/LogbookFilter.swift`) does the choosing — scope and a case-insensitive any-word
search over circuit, car, driver, notes, tags and file name — so it is tested without a view.
`LogbookModel.shared` holds the entries and re-reads them after any write. **Open as Project**
hands the entry to the next editor through `PendingLogbookOpen`, as New from Template hands a
template; **Add to Current Project** calls the front editor's `addData(at:)`. The toolbar's Add
Track Day… and a drop of files or folders on the window run `TrackDayImport` behind the same
sheet. Fits 1024×768 (sidebar 170–280, detail 720 minimum).

## Conditions and notes (#348)

`SessionConditions` (`ProjectModel/SessionConditions.swift`) — weather and track from short
lists, the air temperature in °C, tyres and setup as text — sits on the entry as `conditions`,
beside `notes`; every part optional and the decoder forgiving of words a later build adds (an
unknown weather reads as not noted rather than failing the entry). `ConditionsEditor` in the
window's detail writes straight to the entry: pickers and the temperature as set, text fields on
Return or losing focus, never per keystroke. `summary` is the table's column and the sheet's
future "what the day was like". These are library files, not a document, so the edits are not
undoable, as the track definitions' are not.

## Projects and the logbook (#349)

`ProjectLogbook` (`MediaKit/ProjectLogbook.swift`) and `EditorModel+Logbook.swift`. A data file
the user has just added is entered after its first compile — the same moment the track definition
and the details are applied, and under the same rule: only for a file just added, never on
opening a saved project. The entry is found by the file's bytes or made, the input keeps its
`logbookEntryID` as bookkeeping written without an undo step of its own (an undo of Add Data
takes the whole input away anyway), and blank car and driver details are filled from the entry.
`Preferences.logbookAutoAdd` (Settings ▸ Logbook) turns it off. A project with a place on disk is
recorded on its entries' `projects` after each compile; every finished export (the sheet, the
vertical clip, the debrief) on `exports`. Relinking runs once per load: an input whose file is
missing takes the entry's bookmark's place as an undoable *Relink Data File*; an entry whose path
is stale while the project's is good learns the new one.

## Taking it with you (#350)

`LogbookTransfer` (`ProjectModel/LogbookTransfer.swift`). **Export** writes the entries as the
same `.onboardsession` files the library keeps, plus `garage.json`, into a folder; with data files,
each session's file is copied under `Files/` as `<hash prefix>-<name>` and the written entry's
path points there, relative, with no bookmark. **Import** reads any folder of entry files: merge
by content hash — unknown bytes are added, known bytes skipped unless the arriving copy's
`modified` is newer, in which case it replaces the entry under the id the logbook already uses
(so projects keep their link); an entry whose path no longer resolves takes the copy under
`Files/` when there is one, or keeps the known entry's file; imported entries keep their own
`modified` (`Logbook.save(_:keepingModified:)`). **CSV**: one line per session with the numbers,
conditions and notes, and one per lap, RFC 4180 quoting, seconds and km/h and ISO 8601 dates, so
a spreadsheet needs no parsing; **Markdown**: a table of the sessions and each session's laps and
notes. The window exports what the table shows, so a scope or a search is the selection; the CLI
exports the whole book. Zip is left to the Finder.

## What comes next
 #348 conditions; #349 the two-way link with projects; #350 export, import,
CSV and Markdown. Milestone E (#351–#355) reads across the entries: personal bests, logbook laps as
coaching references, trends per corner, car against car, a season summary.

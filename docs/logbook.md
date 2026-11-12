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
  called or wherever it lives; `resolveFile()` tries the bookmark, then the path. The same
  *drive* in another file is caught by its numbers instead (#465, below);
- **where and when** — the circuit's Wikidata id when `CircuitCatalog` recognised it, the file's
  own track name, and the date the file carries (`SessionInfo.createdAt`); `title` is the circuit,
  else the track name, else the file's name. The file's name is a title only: the *circuit* a
  session is grouped under (`LogbookFilter.circuitKey`) is the id, else the track name, else
  nothing (#455, below);
- **what** — the car (typed once, remembered per circuit by the import) and the driver (the file's,
  else typed);
- **the laps** — number, time and completeness for each, and the session's best (with its number),
  optimal (`SessionStats.optimalLap`, the best sectors spliced) and **fastest rolling lap**
  (`CoachingReference.fastestRolling`), and the top speed in m/s; and which reading the laps are
  from (`lapMeasurement`, #498, below);
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
whose `line` is the sentence the sheet and the CLI print. File ▸ Add Files to Logbook… runs
it off the main thread behind a sheet (`TrackDayImportSheet`); `onboard logbook add` and `list`
do it on the command line. Under UI tests the app's logbook is a scratch folder
(`ONBOARD_TEST_LOGBOOK_DIR`), as the templates are.

## The window (#347)

`LogbookWindow` (`Sources/OnboardStudioApp/LogbookWindow.swift`), Window ▸ Logbook, ⌃⌘L — a
`Window` scene like Attributes and Coaching, not a document: a three-column `NavigationSplitView`
whose sidebar is the scopes `LogbookFilter` computes (all, circuits by most sessions, cars, years),
whose content is a sortable `Table` (or Trends, or the Season) and whose detail is `LogbookDetail`
(#503). `LogbookFilter`
(`ProjectModel/LogbookFilter.swift`) does the choosing — scope and a case-insensitive any-word
search over circuit, car, driver, notes, tags and file name — so it is tested without a view.
`LogbookModel.shared` holds the entries and re-reads them after any write. **Open as Project**
hands the entry to the next editor through `PendingLogbookOpen`, as New from Template hands a
template; **Add to Current Project** calls the front editor's `addData(at:)`. The toolbar's Add
Track Day… and a drop of files or folders on the window run `TrackDayImport` behind the same
sheet. Fits 1024×768 (sidebar 170–280, the sessions 460 minimum, a session's detail 320–420).

The menu bar (#450): the window publishes a `LogbookCommandContext` as a focused scene value — the
session on show, its view, whether the table has the keyboard, and the same closures the detail's
buttons and the toolbar call — and `LogbookCommands` builds the **Session** menu and the window's
items in File, Edit and View from it, so a menu item and its button cannot drift apart. Commands
that exist for two windows hold their key only while their own window is in front
(`keyboardShortcut(_:modifiers:when:)`): a dimmed menu item still takes its key and does nothing
with it, and of two items on one key a dimmed one listed first blocks the other (measured with
`NSMenu.performKeyEquivalent`). That is why the editor's menus (`EditorCommands`,
`TimelineCommands`) give up their keys with no project in front, why ⌃⌘C is Coaching… in a
project and Coach… in the Logbook, and why ⌘⌫ removes a session only while the table has the
keyboard. The toolbar is customizable (`.toolbar(id: "logbook")` over the list, `"logbook.session"` over the session).

The detail keeps the width it was dragged to (#483). SwiftUI's `HSplitView`, where the detail
was until #503, has no autosave name and puts a pane back at its minimum width every time it
returns — after a visit to Trends, after the selection is lost and made again, at the next launch
— and the system inspector column (`.inspector`) opens at its ideal width once and at its minimum
after that; around the whole `NavigationSplitView` it also raised an AppKit update-constraints
exception when its edge was dragged. A divider of the app's own was tried and kept the width, with
a stray hairline in the detail's foot to show for it. So the split view stays as it is, and
`LogbookDetailWidthKeeper` — a zero-size view in the detail column — finds the `NSSplitView`
SwiftUI made, sets its last divider from the kept width when the column appears, and writes the
width down when
`NSSplitView.didResizeSubviewsNotification` says a divider was dragged (a window resize does not
count). The width is the preference `logbook.detailWidth`; `LogbookDetailWidth.fitted` holds it
to 320–420 and shows it narrower, without forgetting it, in a window too narrow to leave the
sessions their minimum. Under the UI tests the width is kept in a store of its own
(`UITestSupport.paneDefaults`), emptied at launch unless `-keepPaneWidths YES`, so a test neither
reads nor leaves a width in the real preferences.

## Laps read before a correction (#498)

An entry keeps the laps it was read with, so a fix to how a file's laps are read does not reach
the sessions already in the logbook: after #477 a RaceChrono session added earlier went on showing
a first lap that had swallowed the out-lap (`.rcz`) or was called partial (CSV), while the same
file opened in a project gave the corrected laps. Each entry now records which reading its laps
are from — `lapMeasurement`, always written, absent = 1; `LogbookEntry.lapMeasurement` is the
build's, and 2 is #477 — as `cornerMeasurement` does for corners (#438).

`needsLapReading` is true for an entry of an earlier reading that the correction can change: an
archive, or a file whose first lap is partial, and in both only when the laps do not begin at
lap 0. Lap 0 is the app's own count from a start/finish line, which #477 did not touch, and which
a plain re-read would not reproduce. `LapReadingOffer` shows above the table when any session in
it needs reading, and `LogbookReferences.readLapsAgain(of:in:)` reads each file with the importer
that read it first and calls `LogbookEntry.readLaps(of:)` — the laps, best, optimal, fastest
rolling lap and the best lap's corners, and nothing the driver wrote. It returns the ids it could
not read; those keep their laps and their `lapMeasurement`, so they are offered again.

Asked for, not done at launch: it reads every such file, and it can change a best lap, which the
user should see happen rather than find. The next correction to lap reading steps
`LogbookEntry.lapMeasurement` and widens or replaces the test in `needsLapReading`.

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

## One drive, two files (#465)

RaceChrono exports a session as CSV v2, CSV v3 and `.rcz`, and a folder often holds more than
one. Their bytes differ, so the hash calls them different files, and the drive was entered twice:
two rows, two points in Trends. `LogbookEntry.isSameSession(as:)`
(`ProjectModel/LogbookSameSession.swift`) compares what the entries keep: the length of the log
(within 0.25 s or 0.05 %), the distance driven (within 1 m or 0.01 %; both known or both
unknown), the date (within a day — a CSV dates the session by its header to the minute, an
`.rcz` by its first sample), and the time of every lap that both number alike and call complete
(within 0.02 s). Which laps are complete is left to each format. Measured on one real session in
all three formats: the two CSVs read alike to the last digit, and the `.rcz` was 0.04 s longer,
0.02 m further and equal to a millisecond on the laps both called complete.

Strict on purpose: two cars in the same track session, or two loggers in one car, differ by
seconds and metres and stay two sessions; a drive exported again after its finish line was
corrected has other lap times and is its own session; an entry with no length recorded is never
taken for another. `Logbook.entry(sameSessionAs:)` is asked after the hash, in
`TrackDayImport.importOne` — the outcome is `.sameSession`, counted with the files already there,
and its line names the file the logbook has the session from — and in `ProjectLogbook.enter`, so
a project given the other export remembers the entry the logbook already has. The check comes
before a day is found or made, so a file that is not added leaves no day behind. Duplicates
entered before this are not merged: nothing in the logbook can be merged yet (#454).

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

## Personal bests (#351, Milestone E)

`PersonalBests` (`ProjectModel/PersonalBests.swift`) is queries over the entries: the best at a
circuit key, narrowed to a car and a year; the visits; the sessions that set a best when driven
(a chronological sweep per circuit and per circuit-and-car, which is what the window's star
means); and the text keys. At compile, `LogbookDerived` (MediaKit) reads the user's logbook —
`ProjectCompiler.logbookDirectory`, a scratch folder under UI tests — only when the project names
a key (`Project.usesLogbookKeys`) or has a timer against the personal best (`needsPersonalBest`):
the keys go into `LoadedProject.derivedDetails` and reach text through `ProjectDetails.adding`,
under any detail the user typed; the personal-best lap's session is read on demand and its
`LapProfile` handed to the timer through `ObjectContext.personalBest`, except when the best is
this very session (same bytes), where the session best already measures it. The timer's delta is
by distance into the lap, the one alignment a live readout can have across sessions.

## Trends (#353, with #332)

`CornerRecord`s — brake point, minimum speed, exit speed and time in corner of each corner of the
session's best lap — are read when an entry is made (`LogbookEntry.cornerRecords(of:)`, the
coaching detector and metrics on that lap) and kept with it, so corner trends across visits are a
read of the logbook, not of every file; entries from before get them on demand (*Read Their
Corners*). Each entry records which measurement read its corners (`cornerMeasurement`, #438;
`LogbookEntry.cornerMeasurement` is the build's): when a fix changes what is measured the number
steps, and Trends offers the same button for entries read by an earlier one, so a corrected
reading reaches the sessions already in the logbook. 2 is the first correction: braking that
begins after a corner has ended is the next corner's. `LogbookTrends` (`ProjectModel/LogbookTrends.swift`) turns the entries at a circuit key
into dated points (best, optimal, rolling, and the spread of flying laps as consistency), a
sentence for the summary and VoiceOver, and per-corner trends: the latest visit against the one
before and the personal best's session, matched by the corner's label. The window's Trends view
(`LogbookTrendsView`, SwiftUI Charts, semantic colours, a tap on the chart opening the nearest
session) is the second of its two views. This is where #332's "did the plan work?" lives: the
plan on the circuit's definition says what was meant, the corner table says what moved.

## Car against car (#354)

`CarVersusCar` (`MediaKit/CarVersusCar.swift`) takes the two cars' best entries at a circuit
(`PersonalBests.best(…, car:)`), reads both files in, and runs the two-session coaching analysis
with the first car's best lap against the second's — the same by-position reading as two drivers'
laps, the reference phrased as "the GR86's best lap" so the existing notes already name the car.
`sentences` turns each `CornerComparison` into one line (who is quicker, by how much, and where
the difference is: brake point, apex speed, exit speed, thresholds as the notes use);
`speedTraces` thins both profiles' speed channels for a chart. `CarVersusCarSection` sits at the
foot of the Trends view when the circuit has two cars; `LogbookModel.carComparison` keeps the
result per pair of sessions for the app's life.

## The season (#355)

`SeasonSummary` (`ProjectModel/SeasonSummary.swift`) composes a year — by the day driven, or
entered when the file carried no date — out of what the entries already hold: distinct days,
sessions, complete laps, the sum of `distanceMeters` (new on the entry, from the distance channel),
the personal bests set that year (`PersonalBests.entriesSettingBests`), the best at each circuit
(`PersonalBests.best`), the corner that moved most either way (`LogbookTrends.cornerTrends` per
circuit, latest visit against the one before) and the open plans on the visited circuits'
definitions. `SeasonPage` is the view in the window and, with `forPrint`, the PDF through the same
`ImageRenderer` path as the coaching sheet; `SeasonCard` is the 9:16 picture, rendered to PNG.

## A day first (#392, v0.34.0)

Every tool a season is kept in groups sessions under a day or an event before anything else, and
the workflow the app is built around from v0.34.0 begins there: a driver *creates a track day*,
adds its sessions and clips, and gets coaching and projects from them. `TrackDay`
(`Sources/ProjectModel/TrackDay.swift`) is that record: the day (midnight, local calendar), the
circuit (catalogue id, else the name typed), the car and driver, the day's conditions (the default
for a session added to it), notes and tags, and the camera's clips (`ClipRecord`: the file by path,
bookmark and a fingerprint of its first mebibyte, the chapters that follow it, when the camera's
clock says it started and for how long, and the session it was matched to and how — #394 does the
matching). One `<uuid>.onboardday` file per day beside the entries, read and written through the
same `Logbook` (`days()`, `saveDay`, `removeDay(id:andSessions:)`, `sessions(of:)`).

An entry carries `trackDayID`. Entries from before days existed, or arriving from a build without
them, are put on one by `Logbook.ensureDays()`: the day with the same calendar day
(`date ?? added`) and circuit key, made from the entry (its car and driver copied) when there is
none. It runs whenever the window reloads and after a logbook import, and is idempotent, so a
logbook never has a session off a day. `Logbook.day(for:)` is the same find-or-make, which #393's
import uses to place a file that was not added to a chosen day. `LogbookScope.day` narrows the
window to one day and `LogbookFilter.days(in:days:)` lists them newest first with their counts,
an empty day included, since a day is begun before its files exist.

`LogbookTransfer` writes the days the exported sessions belong to and reads days back by id
(newer `modified` wins); the sessions CSV gains a `day` column with the day's label
("23 Aug 2026 · Sonoma Raceway"). An entry also records `durationSeconds` now, so a clip can be
matched to it by clock without reading the file again.

## New Track Day… (#393)

`NewTrackDaySheet` (`Sources/OnboardStudioApp/TrackDayViews.swift`): a `Form` of the date, the
circuit (a search of `CircuitCatalog` with the match chosen, or the name kept as typed), the car
(a text field with the logbook's cars in a menu beside it), the driver, the weather and surface
pickers and notes; Create saves the day, adds a new car to the garage, and chooses the day in the
sidebar. It opens from the toolbar, the empty state and File ▸ New Track Day… (⌥⌘N, which opens
the Logbook window with `LogbookModel.newDayRequested`). The sidebar's **Track Days** section
(`TrackDaySidebarSection`) lists `LogbookFilter.days` newest first, under a `DisclosureGroup` per
year when there is more than one — folded shut, except that `LogbookModel.choose(_:)` opens the
year of the day chosen (`openYears`, #485), so the selected row is never folded out of sight when
a second year arrives; choosing one narrows the table and puts `TrackDayHeader` above
it — title, date and count, car and driver as fields committed on Return or losing focus, the
`ConditionsEditor` (now over either an entry or a day) folded under *Conditions and Notes*, the
empty-day line, **Add Files…** and **Remove Track Day…** (a confirmation; the sessions go
with it, the files stay).

A session that names no circuit has none (#455). `LogbookFilter.circuitKey(of:)` used to fall back
to the file's name, so every unrecognised file was a circuit of its own in the sidebar and two
files named alike were two visits to one place. The key is now empty for such a session;
`circuits(in:)` gathers them as one group, id `""`, titled *No circuit* and sorted last;
`PersonalBests`, `LogbookTrends.points` and `LogbookReferences.sessions(at:)` answer nothing for
the empty key. The project side asks the entry first: `LogbookDerived.circuitKey(for:session:entries:)`
takes the key of the entry the input was entered as (`logbookEntryID`), which is where a circuit
named afterwards is kept.

A circuit is named on the day. `TrackDayHeader` has a **Circuit** row holding `CircuitChooser`,
the control the New Track Day sheet uses (catalogue matches, `LogbookFilter.typedCircuits` — the
names typed before — and the text as typed); `Logbook.updateDay` carries the day's new circuit to
the sessions whose key was the day's old one, as it does the car. A session takes the day's
circuit on the way in as well: `TrackDayImport.file` when the chosen day's circuit was typed, and
`Logbook.assignDay(to:)` — used by the import with no day chosen and by `ProjectLogbook.enter` —
when a session with no circuit joins, by its date, a day that has one. `Logbook.day(for:)` dates
an undated session by its file (`fileDate`, the earlier of creation and last change) rather than
by the day it was added. `LogbookWindow.followTheChosenDay` keeps the sidebar's selection when a
day's label changes with its circuit.

The Testing menu's second-visit hooks say where the coaching fixture was driven
(`UITestSupport.secondVisitDay`): its file names no circuit, so two of its sessions are two visits
to one place only once that is said, as it is for a user.

A session takes its car and driver from the day when it is added, and that copy used to be final
(#453): correcting the day's car changed the header alone, and a session had no field of its own.
`Logbook.updateDay(_:)` — what `LogbookModel.saveDay` calls — writes the day and carries a change
of car or driver to the sessions that still have what the day had; one given its own keeps it.
`SessionCarFields` puts **Car** and **Driver** in a session's detail, committed like the day's.
Every Car field offers `LogbookFilter.knownCars(in:days:)`: the days' cars and the sessions', one
list, so the New Track Day sheet no longer prefills one name and offers another.

The toolbar's **Add Files…** (and a drop on the window) runs `TrackDayImport.run(…, day:)` with
the chosen day, so the sessions take its id, car, driver and conditions; with no day chosen each
file goes on the day `Logbook.day(for:)` finds or makes, and the report line ends ", in 23 Aug
2026 · Sonoma". `ProjectLogbook.enter` places a file added to a project the same way. The
request and the sheet live on `LogbookModel` (`trackDayRequest`), so the Testing menu's *Add
Fixture Sessions to Selected Day* can drive them.

A chosen day does not take a file that says it is from another (#456). The sheet runs the import
with `strays: .kept`: a session dated another calendar day than the day's, or whose trace was
recognised at another catalogue circuit, and a clip whose clock says another day, are read and
returned as `Outcome.waiting(Stray)` — nothing is saved for them, and no day is made. A file with
no date is not another day's, a trace no circuit was recognised in is not another circuit's (it
takes the day's, and `Report.notes` says so in the line), and a day with a typed circuit is
compared by date alone. The sheet then asks, and `TrackDayImport.place(_:onto:into:)` files what
was kept without reading it again: onto the day (the line notes *dated another day than this
one*), or with `nil` onto the day each file's own date and circuit say, exactly as an import with
no day chosen. The default, `strays: .ontoTheDay`, is what `onboard logbook add --day` does:
naming the day on the command line is the answer.

## The day's clips (#394)

`ClipMatcher` (`Sources/MediaKit/ClipMatcher.swift`) is the clocks and nothing else:
`record(_:chapters:)` probes a recording (`MediaProbe`, every chapter's length summed), takes
its start from `TimestampSync.recordingStart` — a GoPro's GPS clock, a DJI or Sony sidecar, the
container's creation date — else the file's own date, and fingerprints the first mebibyte and
the length (a 20 GB clip is not read through); `match(_:to:)` gives the clip to the session its
span overlaps most, and when neither side has a clock to the only session of the day; a dated
session the clock rules out is never a match. `TrackDayImport.run` groups clips with
`CameraChapters.group`, imports the telemetry first so a clip and its log in one batch pair up,
then records each clip on its day (`Logbook.day(on:)` by the clock when no day was chosen),
matches it, and — for a clip with GPS and no session of its own — reads it as a session first,
as it was before days existed. New outcomes `.clip(_, session:)` and `.clipAlreadyThere`, with
lines in the user's words.

In the window the day's header lists the clips with a pop-up of the day's sessions (a choice is
`matchedBy: .byHand`), the session detail lists its clips under *Video*, and **New Project**
(`LogbookOpenRequest`: the entry, its clips' files with their chapters, a template, and what to
show next) applies the template, adds the videos (`addVideos(at:)`, chapters joined) and then the
data file, so the editor's own clock sync lines them up. The template is the one the last New
Project used (`logbook.projectTemplate`), Classic Dash to begin with; a pop-up offers them all.

## The window at launch (#395)

From v0.34.0 the Logbook is what opens when the app does (`.defaultLaunchBehavior` on its
`Window` scene, `Preferences.openLogbookAtLaunch`, Settings ▸ Logbook; `AppDelegate` opens no
untitled document while it is on). The welcome window's reasons to exist moved: starting a
project is the toolbar's **New Project** menu (a blank project, the built-in and user templates,
Open Project…, Templates… and the sample project; while a session is selected its Blank Project
and templates make the project from that session, under a heading that names it, and **New
Project Without a Session** is the empty one — #449, `LogbookWindow.shownEntry`),
recents are File ▸ Open Recent, and the template cards with their right-click management (#44,
J17) are the **Templates** window (`TemplatesWindow.swift`, Window ▸ Templates), which is the old
launcher view without its identity pane and project buttons. An editor no longer dismisses the
launch window: the Logbook stays behind the project, since the next session comes from it. The
UI tests launch with `-skipLogbook YES` (was `-skipLauncher`), so every journey that starts on a
blank project is unchanged; `LogbookLaunchUITests` starts with the Logbook.

## The ways out of a session (#397)

**Coach…** in a session's detail reads the project open on the session when there is one
(#462, `CoachingWindow.open(_:coaching:)`; see `docs/coaching.md`), else the session alone.
Beside it: **Compare With ▸** (`LogbookWindow.comparisons(for:)` —
`LogbookReferences.sessions` at the entry's circuit key, the personal best and the last visit
named first) writes the chosen session onto the entry's `coaching.reference` as
`.logbook(entryID:lap:)` and opens the Coaching window on it, exactly the state the window would
have reached by hand; **Export Coaching Debrief…** is `LogbookModel.openAsProject(_:template:then:)`
with the Coaching Debrief template and `then: .debrief`, so the new editor puts the debrief sheet
up once it appears. It is disabled until the session has a clip on its day, with the help text
saying why.

The window is a three-column `NavigationSplitView`, as Mail is (#503): the sidebar, the content
(the sessions, Trends or the Season) and the session chosen, with its column widths. The toolbar
follows the columns — each column's `.toolbar` items sit over that column — so the list's buttons
stay over the list and **New Project** over the session however wide it is dragged. Before, the
detail was a pane of an `HSplitView` beside a two-column split view (#448), and the toolbar, laid
out across the whole window, ran under its edge: at 420 points New Track Day sat half over each.
The system inspector inside the content column was measured too: its toolbar did not follow its
edge either, and it lost the kept width. The session's column stays beside Trends and the Season,
with **No Session Selected** when there is none (a `NavigationSplitView` cannot hide its last
column while the sidebar shows). Before #448 the detail was an `HSplitView` inside the detail
column, which gave the table and the detail their minimum widths and left the rest of the column
empty. The table's **PB** column comes first, as Mail's flags do: last, it was the first a narrow
table scrolled out of view.
The buttons are in `FlowLayout` rows in a `safeAreaInset` under the scrolling detail: one that does
not fit starts another row, and none of them scrolls out of view. **New Project** is one `Menu`
with a `primaryAction` — a split button — in place of a button and an icon-only menu beside it.

## On the command line (#398)

`onboard logbook new-day` (`--date`, `--circuit` as a catalogue search or id, else kept as typed,
`--car`, `--driver`, `--notes`) saves a `TrackDay` and prints its label and id; `days` lists them
newest first with their car, session and clip counts (`--json` for the records); `add … --day
<id | 2026-08-23> [--circuit]` runs the import onto that day (a date with more than one day asks
for the circuit or the id); `list` prefixes each session with its day's label. `ensureDays` runs
before `days`, so a logbook written by an older build lists correctly.

## What comes next
v0.34.0 (#392–#398) turns the workflow round so it begins here: a day created first (#393 New
Track Day…), its clips matched to its sessions by clock (#394), the logbook as the window at
launch (#395), coaching straight from a session (#396), the debrief and comparisons from a
session (#397) and the same on the command line (#398).

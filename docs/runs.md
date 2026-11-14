# Runs: autocross, hill climb and stages (#552) — design

**Status:** steps 1 (runs in the project), 2 (runs and courses in the Logbook) and 3 (cones and
DNF) are built; step 4 (suggested lines) is to come. How step 2 keeps courses is in
`docs/logbook.md`, *Runs and courses*.

Draft of 2026-11-13. The decisions it builds on were made by the user on 2026-11-13. A circuit lap
starts and ends at one line. A **run** starts at one line and ends at another: an autocross, a hill
climb, a rally stage. This design adds runs without a second timing system. **A run is a `Lap`**,
so everything that already reads laps works on runs as soon as they exist: coaching, Compare Laps,
deltas, the Timer, sectors, the optimal lap, and *Every lap, one file each*.

## What the driver sees

1. **The lines.** In a data file's *Laps* section in the inspector, *Timing* chooses **Laps** (as
   today) or **Runs**. With Runs come two lines, **Start** and **Finish**, each set at the preview
   position or typed in. The start can also be dragged on the track map, as the start/finish is
   today. A loop course timed from a standing start puts both lines in one place: the run ends at
   the line's last crossing before the car stops. A VBO file that carries `Start` and `Finish`
   gates turns Runs on and places both lines by itself (the status bar says so), just as its
   start/finish and splits are used today. Suggesting the lines from the data is step 4.
2. **The runs.** The timeline's data bar divides at each run's start and finish, and the bar is
   dimmed between runs. Runs are numbered 1, 2, 3. ⌥↑ / ⌥↓ go from run to run, and the status line
   reads "Run 3 — 52.341". A run that never reached the finish is shown as **DNF**.
3. **The Logbook.** A session timed in runs lists them as runs: raw time, **Cones** and **DNF**
   (both editable and undoable), and the **official time** (raw + cones × the day's penalty per
   cone, 2 s unless the day says otherwise). The best run, the personal best, Trends, goals and the
   import report's "x s quicker than last time" all use the official time and ignore DNFs. Coaching
   reads any run's driving, a coned one included, because the cones say nothing about the line.
4. **Courses.** Under a venue in the sidebar are its **courses**: *Course of 12 Oct 2026* by
   default, renamable. A new session joins a course of the same venue when the geometry matches
   (see below). Otherwise it starts a new one. *Same Course as ▸* and *New Course* put a mistake
   right, and each is one undo. Personal bests, Trends, goals, the card's plan and *Compare With ▸*
   are kept per course, so a hill climb collects its history visit after visit, and each autocross
   layout gets its own.
5. **Wording.** Wherever a session in runs is shown, the app says *run* rather than *lap*. That
   covers the Logbook, the Coaching window, Compare Laps (*Compare Runs*), the export sheet
   (*Every run, one file each*) and the Timer's labels. The **fastest rolling lap** is not offered
   for runs, because it has no meaning on an open course.
6. **The video** shows the raw run time. An official-time readout with cones is a later step. It is
   kept out of this design so that penalties stay in the Logbook and a project never changes when a
   cone count does.

## How it works

### Detection (`TelemetryKit`)

- `LapDetector.runs(in:start:finish:)` reads the crossings of both lines, each filtered by heading.
  Heading matters most on a hill climb, where the drive back down crosses both lines going the
  other way.
- Crossing the start opens a run. Further start crossings while a run is open are ignored, because
  autocross courses often pass the start area again.
- **Which finish crossing ends a run.** The session is cut wherever the car stood still, and a run
  ends at the **last** finish crossing before the next stop. A course that passes the finish
  mid-run therefore does not end the run early. (The draft said "the crossing nearest the median
  distance"; the stops make that unnecessary.)
- **When a run is a DNF.** A run with no finish crossing before the car stops is
  `isComplete == false` and counts as a DNF. A run shorter than 90 % of the longest is demoted the
  way a short lap already is.
- **One line for both.** A start and a finish in the same place need no flag: a run opens at the
  start crossing and ends at a *later* crossing before the car stops.
- **A stop** is speed under 3 m/s (about 11 km/h) for 2 s, both parameters of `RunDetector`.
- **A line with no heading** (a VBO gate) takes the direction the car first crossed it in, so the
  drive back down a hill climb is not a run.
- **Laps stay contiguous.** `[Lap].lap(containing:)` assumes laps cover the session end to end. So
  the stretch before, between and after runs becomes a lap marked `isTransit`, with no number shown.
  Lists, counts, bests and dividers skip it, the same way partial lap 0 is skipped today. This is
  the smaller change. Allowing gaps would touch every caller of `lap(containing:)` and the timeline.
- Corner detection already treats an open path as open (`CornerDetector`, `isClosed`). Sectors at
  *equal distances* work on a run unchanged.

### Suggesting the lines (`StartFinishFinder`)

- **Start:** where runs launch from a standstill. That is the points where speed rises from under
  5 km/h to over 30 km/h within 5 s, clustered. The line goes through the cluster's centre, across
  the launch direction.
- **Finish:** the last point all runs pass at speed before they slow to a stop. A single run uses
  the point where speed falls below 40 % of its top speed for good.
- **Trust.** Both say where they came from and are meant to be checked, as the start/finish
  suggestion is today. The thresholds are parameters, not constants spread through the code.

### Courses in the Logbook (`ProjectModel`)

- **As built:** a course is not a list of its own. Each session on it keeps its `CourseTag` (an id
  and a name), its `runLines` and its best run's `coursePath`, so renaming a course or moving a
  session between courses is an ordinary logbook edit that undoes as one. A new session matches
  the course of the first entry whose lines are each within 15 m of its own and whose path is within
  5 m on average, measured both ways; there is no venue test, because lines that close are at the
  same venue.
- **Keys.** For a session on a course, `circuitKey` is `course:<id>`. Personal bests, Trends,
  goals, the circuit card and *Compare With ▸* key on it unchanged; `venueKey` is the circuit
  without the course, for comparing a session with its track day.
- **Per-run fields.** `LapRecord` gains `cones: Int` and `offCourse: Bool`, entered by the driver.
  A run is a DNF when detection found no finish or the driver ticked it off course (the draft had
  one `dnf` flag; two keep what detection found apart from what the driver said).
  `TrackDay.penaltyPerCone`, 2 s when unset, is copied onto the day's sessions in runs, as a day's
  car is, so an entry's best counts the same wherever it is read.
- **Saving the course.** Venues are mostly not in the catalogue: there are no hill climbs in it, and
  car parks aren't circuits. They are named by hand, as a *No circuit* day is today.
  `TrackDefinition` gains `finish: LapLineSpec?`, so *Save … for This Track* keeps a hill climb's
  lines for the next visit.

### Project format

- `DataInputSettings.runFinishLine: LapLineSpec?` is added. A project saved earlier has none,
  decodes to `nil`, and keeps its laps exactly. No migration and no schema step are needed,
  because no default changes. `docs/project-format.md` documents it.

## Build order

One PR each, in this order, each with its tests and its docs:

1. **Runs in the project.** Detection, transit stretches, the Timing switch and both lines in the
   inspector, the VBO `Finish` gate, *run* wording in the editor, Timer and export sheet, the
   rolling lap hidden, and runs in `onboard probe`.
2. **Runs in the Logbook, and courses.** Entries read runs, courses are matched by geometry with
   the overrides, and PB, Trends, goals and the card are kept per course.
3. **Cones and DNF.** Per-run fields, the day's penalty per cone, and the official time feeding the
   best run, PB, Trends, goals and the import report.
4. **Suggested lines.** Start from launches, finish from where the runs end.

**Tests.** Synthetic fixtures only, with no real sample data:

- An autocross trace of four runs: one coned, one DNF, and one whose course passes the finish
  mid-run.
- A hill climb up and back down.
- A loop course where the finish is the start line (to add with step 4's suggestions).
- Two layouts at one venue that differ by one gate, which must not match.

**Docs.**

- A user-guide section, *Runs: autocross, hill climbs and stages*.
- A journey, *J65 Time an autocross*, with its XCUITest.
- `formats.md`: the VBO `Finish` gate is now used.
- `project-format.md`, `tracks-and-sectors.md`, `parity.md` and `landscape.md`.

## Not in this design

- An official-time readout with cones in the video (a follow-up issue).
- Importing cones from club results files such as AXware or MotorsportReg.
- Drift, which is scored on angle and line, not time.
- Live timing and auto-start from the accelerometer, which are capture features.
- Reaction time and drag-strip timing (#553).

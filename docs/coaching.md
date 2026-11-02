# Coaching

Design for the coaching features: what the app says about a lap beyond showing its numbers, and
what it says to try next time. Written from a survey of the coaching tools drivers actually use,
from the data-analysis literature, and from how HPDE instructors debrief, all recorded below so the
reasoning can be re-checked rather than taken on trust.

Milestones: **v0.29.0 — Coaching: where the time went** (#315–#322), **v0.30.0 — Coaching in the
video** (#323–#329), **v0.31.0 — Coaching between sessions** (#330–#335).

## The gap

Onboard Studio measures a lot — laps, sectors, the optimal lap time, deltas to the best lap,
Compare Laps side by side, the corners of the circuit — and interprets none of it. A driver still
reads a delta graph and works out for themselves that the time went in Turn 4 because they braked
early. Every coaching product surveyed does that step for the driver, and an instructor does it in
person after each session, with a track map and three things to try in the next one.

Two forms were asked for: **in the app**, after the session, interactively; and **in the video**,
so a rendered lap can carry its own debrief. Real-time in-car coaching is not one of them (see
*Deliberately not doing*).

## What the field does

Surveyed 2026-11-01. The products converge on one shape, and the shape is what is built here.

| Product | What it does with a lap | Source |
| --- | --- | --- |
| **Coach Dave Delta — Auto Insights** (sim) | Splits every corner into **braking, entry, apex, exit**, says which phase cost time against a reference lap, ranks the corners, and in 2.0 recognises **linked corners** ("compromising T3 for T4") | [docs](https://coachdaveacademy.com/documentation/how-to-use-auto-insights-ai-coaching-in-delta/), [2.0 announcement](https://coachdaveacademy.com/announcements/auto-insights-2-ai-driving-coach-delta/) |
| **Garmin Catalyst** (real cars) | After the session, the **top three opportunities** ranked by time available; for braking, a **video frame at the better lap's brake point** as a sight picture; a **True Optimal Lap** spliced from the best segments; audio cues in the car | [Grassroots Motorsports, a year on](https://grassrootsmotorsports.com/articles/year-later-garmin-catalyst-still-revolution/), [Speed Secrets](https://speedsecrets.com/q-can-you-tell-me-about-the-garmin-catalyst/) |
| **Trophi.ai** (sim) | Corner-by-corner time-loss ranking, technique grading per phase, reference laps from experts and the community | [features](https://www.trophi.ai/sim-racing-coaching) |
| **Track Titan** (sim) | "Coaching Flows": the single biggest mistake across the lap and how to fix it; braking-zone by braking-zone analysis | [tracktitan.io](https://www.tracktitan.io/), [review](https://moorepodiums.com/track-titan-review-iracing-ai-coaching/) |
| **Garage 61** (sim) | The delta graph first ("look for where the line is steepest"), a **driving-line offset graph** (left/right of the reference), brake and throttle overlays against thousands of laps | [changelog](https://garage61.net/whatsnew) |
| **Racelogic Circuit Tools** (real cars) | **Delta-T** aligned by **GPS position** rather than distance, because two drivers' lines differ by more than 10 m over a lap; side-by-side video stepped a sample at a time; "are you braking where the faster driver brakes?" as the method | [How to use Circuit Tools to become faster](https://en.racelogic.support/VBOX_Motorsport/Software_Info/Circuit_Tools/Knowledge_Base/How_to_Use_Circuit_Tools_to_Become_Faster), [Delta-T](https://www.racedatasystems.com/pages/analysis-software-racelogic-circuit-tools-html) |
| **AiM Race Studio 3** | Time Compare; the map coloured by it; per-corner and per-straight **reports** with braking and acceleration items; math channels for time spent braking, cornering and **coasting** | [analysis manual](https://www.aim-sportline.com/docs/racestudio3/manual/html/analysis.html) |
| **MoTeC i2** | Time Variance; section **channel reports** (min, average per section); the **fastest rolling lap** — a real contiguous lap-length stretch timed from anywhere — beside the theoretical ("eclectic") lap; consistency highlighting | [forum](https://www.motec.com.au/forum/viewtopic.php?f=26&t=3664), [product page](https://www.motec.com.au/products/I2) |
| **Apex Pro** | A grip-utilisation score from an IMU model, shown as lights | [apextrackcoach.com](https://apextrackcoach.com/) — a different idea, not pursued here |
| **Blayze** (human coaches) | A 10–12 minute video debrief, corner by corner, to re-watch between sessions; the car's view out of the windscreen is what matters, overlays are not needed | [methodology](https://blayze.io/blog/car-racing/blayze-motorsports-coaching-methodology) |

What an engineer or coach reads off a corner, from Segers' *Analysis Techniques for Racecar Data
Acquisition* (SAE, 2nd ed., chapter 14 "Analyzing the Driver"), AiM's sample math channels and
OptimumG's columns in *Racecar Engineering*: the brake point and how hard; where the brakes came
off and how much of that overlapped with cornering (trail braking); the turn-in point; the
**minimum speed and where it fell relative to the apex**; entry and exit speed; where the throttle
came back and where it reached full; **coasting** (neither pedal); time in the corner; peak lateral
G; steering smoothness. And across laps, **consistency**: the spread of brake point and minimum
speed in each corner. A recurring warning in all three: brake-point comparison is meaningless once
the two laps' distances have drifted apart by more than about 5 m.

How instructors debrief, from the Metro NY Region PCA instructor training manual and Ross Bentley's
*Speed Secrets* column: with a track map; three goals for the next session; goals phrased as
**experiments** ("brake at the 2 board instead of the 3 and see whether exit speed improves"), not
targets ("two seconds faster"); from the second session on, one or two corners at a time.

## The shape

Everything below is one pipeline. Each stage is a plain value in `TelemetryKit`, so the window,
the CLI, the video objects and the next-session plan read the same result.

```
LapProfile(lap)  ──┐
                   ├─ LapDeltaTrace ─┐
LapProfile(ref)  ──┘                 ├─ CornerComparison per corner ─ Opportunity, ranked ─ CoachingNote
CornerDetector(ref) ─────────────────┘
```

### Profiles: a lap as functions of distance

`Sources/TelemetryKit/LapProfile.swift` (#315). A `LapProfile` is a stretch of session time — a
lap, or any window — resampled onto a grid every 2 m of distance travelled. It carries elapsed
time, position and heading, and the recorded channels that matter to driving (speed, throttle,
brake, brake pressures, longitudinal and lateral G, steering, RPM, gear), each in its canonical
unit.

**The grid is in metres, not seconds**, for the same reason `CornerDetector` resamples: a brake
point found on a 10 Hz GoPro log and one found on a 100 Hz RaceChrono log must be the same kind of
number. Two metres is finer than any GPS fix and coarser than nothing a driver can act on.

**What the logger did not record is derived where the physics allows**, and the profile says so:

| Channel | When derived | How | `source(of:)` |
| --- | --- | --- | --- |
| Speed | no speed channel | distance per time across the step either side of each grid point | `.speedTrace` |
| Longitudinal G | no `longitudinalG` channel | `v · dv/ds`, smoothed over 25 m | `.speedTrace` |
| Lateral G | no `lateralG` channel | `v² · κ`, κ the heading change per metre of the path, smoothed over 25 m; positive turning right, the sign the recorded channel uses | `.position` |
| Heading | always, when there is position | bearing from the grid point before to the one after | `.position` |

A GoPro, a phone, a RaceBox record none of throttle, brake or steering; these derivations are
what let the rest of the pipeline say anything about a braking zone for them. The derived values
exist only in the profile. They are never added to the session, so no saved project renders
differently because they exist.

### Alignment: lining two laps up

`Sources/TelemetryKit/LapDelta.swift` (#315). A `LapDeltaTrace` is the lap's elapsed time minus
the reference's at each grid point of the reference, positive behind; the change in it across a
stretch is the time lost there, which is what "0.3 s lost in Turn 4" means. Three alignments:

- **By distance**, metre for metre. Right when both laps follow the same line, which two laps of
  one session do to about a metre: lap-to-lap spread on the reference Sonoma session is 0.9 m
  median (`docs/tracks-and-sectors.md`). It is what sectors, the delta channels and the Sector
  Times panel already use, so the coaching numbers agree with the overlays.
- **By fraction of lap**, for two laps of different length without positions: what `LapTimeWarp`
  does to keep two pictures level. A fallback, and the trace's `confidence` says so.

- **By position** (`Sources/TelemetryKit/PositionMatcher.swift`, #316), for a lap from another
  session or another driver. A different line, a different logger or a start/finish line placed
  a few metres differently changes a lap's length by around 1 %, and by fraction that is 30 m by
  the end of a 3 km lap — the drift MoTeC warns makes brake-point comparison meaningless. Each
  point of the reference's grid is matched to the nearest point of the other lap's line, looking
  only ±60 m along that line from the previous match so the match never jumps to the far side of
  a tight circuit and never runs the lap backwards. That gives the other lap's distance at the
  same place and, for free, the **lateral offset** between the two lines, positive to the right
  of the reference's direction of travel. Racelogic's Delta-T is built the same way for the same
  reason.

  Three details worth keeping: the first point is looked for in the first quarter of the other
  lap and, failing that, the last quarter, because two lines overlap at the start/finish and the
  nearest point to the reference's start is as likely to be just before the other lap's end as
  just after its start — a closed lap is searched round its ends for the same reason; the match
  falls back to fraction of lap with `confidence = 0` when more than a twentieth of the points
  are further from the line than the tolerance (30 m by default), or when the other lap does not
  begin near the reference's start, so a lap timed from elsewhere on the circuit is refused
  rather than mis-aligned; and `lapDistances` is kept on the trace, which is how a corner found
  on the reference is read at the right place on the other lap.

`confidence` is a guide, not a measurement: by distance, 1 when the two laps are the same length
to within 2 %, falling to 0 at a 10 % difference; by fraction, 0 at 20 %; by position, one minus
the median separation of the two lines over the tolerance, and 0 after a fallback. Measured on the
synthetic circuit moved 3 m sideways: matched within 3 m everywhere (an east–west straight is 3 m
further along one line than the other), the offset reads −3 m through the right-hander that heads
south and +3 m through the one that heads north, and nothing on the straights that run east and
west. On a circuit with 1 % longer straights, each apex meets its own apex within 1.5 m where
alignment by distance is 6 m out.

### References: what a lap is compared with

Four, all producing a `LapProfile` (#317 for the last two):

| Reference | What it is | Why |
| --- | --- | --- |
| **Best lap** | the session's quickest complete lap (`LapDeltas.sessionBest`) | the default; zero setup |
| **A lap from another input** | another session's or another driver's lap, as Compare Laps already takes | the coaching case with the most to teach; aligned by position |
| **Optimal lap (spliced)** | the best sector of each lap, joined by distance; MoTeC's eclectic lap, Garmin's True Optimal Lap | the lap the driver has already shown they can do, 1:54.54 against 1:56.88 at Sonoma; speed is discontinuous at the seams and the UI says which laps it was spliced from |
| **Fastest rolling lap** | the quickest lap-length stretch starting anywhere, found by sliding a window of the median lap length over the distance channel within the complete laps so the pit lane cannot win | the timing line cuts a driver's best sequence of corners in two more often than not; MoTeC's term |

Both of the last two are **spliced profiles** (`Sources/TelemetryKit/LapProfile+Splicing.swift`,
`CoachingReference.swift`, #317): stretches of several laps joined end to end on one grid, the
clock running on across the joins. A rolling lap that straddles the line is re-based to it — the
piece after the line first, then the piece before it — so its distances are distances into a lap
and its corners line up with every other lap's; one that happens to lie within a lap is that lap.
The optimal lap is one cut per sector, from the lap that set that sector's best, over the
layout's distances, so its duration is the Sector Times panel's theoretical time to the
microsecond. Every profile lists its `pieces`; `seams` is where they join, for a tick on the map
and for a warning when a corner straddles one, since speed and the pedals can step there.

The rolling window is found by sliding one lap length along the distance channel within the
complete laps — so the pit lane and an out lap can never be part of it — and interpolating the
moment the length is reached; a later window must be quicker by more than a millisecond to take
over, so steady laps give the first lap rather than wherever floating point dipped. The optimal
lap uses the session's own sectors when it has them, and corner-aware sectors otherwise.

Measured on the synthetic fixtures: a fast stretch the timing line splits in two is found as the
rolling lap within 0.5 s of its true start and is quicker than any whole lap; the spliced optimal
lap's duration equals `theoreticalLapTime` to 1 µs and its position is continuous at the seams.

### Corners: phases, metrics, time lost

Corners come from `CornerDetector` run on the **reference** lap and are applied to the compared lap
by distance, exactly as sectors are (`docs/tracks-and-sectors.md`). Each corner is split into four
phases that tile a window around it, so the time lost in the phases adds up to the time lost in the
corner:

| Phase | From | To |
| --- | --- | --- |
| Braking | the brake point | turn-in (the corner's start) |
| Entry | turn-in | the minimum-speed point |
| Apex | the minimum-speed point | throttle pick-up |
| Exit | throttle pick-up | the corner's end, extended to full throttle, capped at the next corner's brake point |

A corner never braked for has an empty braking phase. Without a throttle channel the apex phase
ends where longitudinal acceleration turns positive.

Per corner, per lap (`Sources/TelemetryKit/CornerMetrics.swift`, `CornerMeasurement.swift`,
#318): brake point (metres before the apex), peak braking G, brake release, trail-braking overlap,
entry speed, minimum speed and where it fell relative to the apex, exit speed, throttle pick-up,
full throttle, coasting time, peak lateral G, time in corner and steering smoothness. Every
threshold is a fraction of the channel's own range or a value in g, in `CornerMetrics.Options`
with defaults; none is tied to a logger. Every pedal reading records which channel it came from
(`CornerMetrics.Source`), so the window can say "from the speed trace".

Three decisions in the reading are worth not re-deriving:

- **Pedals by priority, then physics.** Brake point from the brake channel, else a brake
  pressure, else deceleration (a recorded accelerometer, else the speed trace) at or beyond 0.25 g.
  Throttle from the throttle channel, else acceleration beyond 0.05 g. Coasting and full throttle
  are reported only from recorded pedals: the physics cannot tell a lifted throttle from a light
  brake.
- **A deceleration threshold reads late.** On a smoothed trace the crossing comes some metres
  after the pedal went down — about `(threshold / effort − ½) × smoothing`, 8 m for a gentle
  0.3 g stop. The reading walks back to where the trace crosses half the threshold, which lands
  within two or three metres of the onset whatever the effort. On the synthetic fixture the
  speed-trace brake point is within 3 m of the recorded pedal's.
- **The straight after a corner is its exit.** A slow exit costs time all the way to the next
  brake point, so the exit phase runs there (the last corner's to the end of the lap), and the
  comparison hands over from one corner to the next at the earlier of the two laps' brake points.
  Nothing between the first brake point and the line is counted twice or left out; what is lost
  before the first brake point belongs to the previous lap's last corner.

The apex a corner's metrics are relative to is `Corner.apexDistance`, and #318 changed how the
detector finds it: the middle of the stretch where curvature is within 2 % of its peak, rather than
the single highest sample. A constant-radius bend has no single tightest point and the old rule
put its apex at one end; the track map's corner numbers moved to the middle of such bends with it.

`CornerComparison` (`CornerComparison.swift`) pairs the two laps' readings for each corner and
reads the time lost in each phase off the delta trace, with the circuit's own corner labels when
`TelemetrySession.cornerLabels` has them. The line offset at the apex comes with position
alignment (#316).

### Opportunities and notes

`Sources/TelemetryKit/Coaching.swift`, `CoachingNotes.swift`, `ConsistencyStats.swift` (#319).
`CoachingAnalysis.analyse` runs the whole pipeline for one lap against a reference: profiles,
alignment (by distance within a session, by position across two, unless the options say
otherwise), corners found on the **reference** and read on the lap at the aligned place, the
comparison per corner, the opportunities, consistency and a list of warnings for the window to
say out loud (alignment fell back; pedals read from the speed trace; a spliced reference changes
lap inside these corners; too few laps to judge consistency).

**Ranking.** Corners that lost at least 0.03 s, biggest loss first; the phase with the largest
loss is the opportunity's phase. A corner whose loss the next corner wins back entirely is a
compromise that paid — Coach Dave Delta's linked-corner case — and is not an opportunity. The top
three are the headline; every corner that lost time is in the list.

**Kind.** One of nine, by the first rule that fits the worst phase: braked early or late (brake
point more than 5 m from the reference's), braked softer (peak braking 15 % weaker), over-slowed
(minimum speed more than 2 % lower), minimum too late (slowest point more than 10 m after the
reference's), throttle late (pick-up more than 5 m later), coasting (0.3 s more off both pedals),
slow exit, and *line* when none of the pedals explains it, which sends the driver to the video.
Every threshold is in `CoachingOptions`.

**Consistency first.** `ConsistencyStats` reads every complete lap's corners and keeps the
spread (sample standard deviation) of brake point, minimum speed and time in corner, plus the
lap-time spread, over the **flying laps** — complete laps within 10 % of the best, so an out lap,
an in lap or a lap behind traffic says nothing about repeatability. A corner is consistent when
the brake points lie within 10 m and the minima within 5 %: on five flying laps at Sonoma the
minimum speeds spread 3–10 % by corner, and the corners a coach would call repeatable sit under
5 %. Three flying laps is the minimum. An inconsistent corner's suggestion begins "This corner
varies lap to lap (brake point spread 23 m): repeat your best lap's brake point first, then …",
because every coach says consistency before speed.

**Notes** are deterministic phrase templates filled from the numbers, in the units asked for
(km/h and metres, or mph and feet): a headline ("Turn 4: 0.31 s lost on entry"), the evidence
that applies ("Braked 18 m earlier than your best lap", "Minimum speed 4 km/h lower, 12 m later",
"Throttle 9 m later", "Pedals read from the speed trace") and one suggestion per kind, phrased as
an experiment ("Try braking where your best lap did, 18 m later, with the same pressure, and see
whether the minimum speed comes up"). The reference is named the way the driver thinks of it:
"your best lap", "lap 5", "the rolling lap", "the optimal lap", or the other input's name. The
same lap gives the same note every time, which a test holds it to.

The corner detector's apex is the median of the samples within 5 % of peak curvature. The first
version of the plateau rule took a contiguous run from the first such sample and broke at the
first numerical dip, which put a constant-radius bend's apex a third of the way in when the
corners were found on a profile rather than a lap; the median is the middle of a plateau and the
peak of a point, and the track map's numbers did not move.

## On the command line (#320)

`onboard coach <file|project> [--lap N] [--reference best|rolling|optimal|lap:N] [--units metric|imperial] [--all] [--json]`
(`Sources/OnboardStudioCLI/Coach.swift`) runs the analysis without the app: the headline, the top
three opportunities as notes, the corner table and the warnings, or the whole `CoachingReport` as
JSON (`Sources/TelemetryKit/CoachingReport.swift`: words and numbers, never samples). Without
`--lap` it reads the quickest lap that is not the reference, so the comparison has something to
say; the last complete lap, the obvious default, is usually the cool-down lap. A project is read
through `ProjectCompiler.load`, so it carries the project's sectors and corner names. This is how
every later piece is checked against the real sessions before it reaches the window.

## In the app (#321, #322)

A **Coaching window** beside the document (`Sources/OnboardStudioApp/CoachingWindow.swift`,
Project ▸ Coaching…, ⌃⌘C), built in #321: a *Lap* picker and a *Compared with* picker (this
session's best, rolling and optimal laps and its other laps, then each other data file's laps);
the headline; the top three opportunities as cards with a *Show Me* button that moves the
playhead to where braking began for that corner on the lap being read; and the corner table,
sortable by any column, whose selection moves the playhead to the corner's turn-in. The words and
the table cells are the ones `onboard coach` prints (`CoachingRows.swift`), so the two never
disagree. The analysis runs off the main thread and is re-read when the lap, the reference or the
data changes. The window follows the front document through `ActiveEditor`, as the attribute
window does, and its choices live in `Project.coaching`, so they come back on reopening and each
change is one undo step ("Change Coaching Lap", "Change Coaching Reference"). Edit ▸ Undo works
from the window: a separate window has its own, empty undo manager, so the window registers itself
(`DocumentWindowTag`) and `UndoMenuState` names and performs the document's undo while it is key;
the editor is published to the menu bar from the window too, so the Project menu applies.

Without a choice the lap read is the lap at the playhead when it is complete and not the
reference, else the quickest lap that is not the reference. Units follow the app's speed unit:
mph gives mph and feet, anything else km/h and metres.

The selected corner's **detail** (`CoachingDetail.swift`, #322) sits beside the table: the time
lost per phase as bars, both laps' readings side by side with where each came from, and the two
lines through the corner drawn in a `Canvas` from the profiles' positions — the lap's at the
aligned distances, so a lap from another session draws at the right place — with the brake points
and slowest points marked, north up, in metres about the reference's apex. *Compare in Video*
calls the existing Compare Laps with the corner's span as the range (one undo step, "Compare
Laps"), so the export is the corner's clip; it is offered only when the reference is a real lap
with a camera, because a rolling or spliced lap has no single picture until #328.

A window rather than an inspector section because a corner table needs width and the inspector is a
column (#192, `.claude/rules/appui.md`); rather than a sheet because it exists to drive the preview.
The chosen reference is saved in the project (`Project.coaching`, optional, so no migration) and
changing it is undoable; the selected row is view state.

The GPS caveat is stated where the lines are drawn: lap-to-lap spread is about a metre and absolute
accuracy one to three, so two lines are a relative comparison, never a measurement of where the car
was on the tarmac.

## In the video (v0.30.0)

**Every lap, read once per compile.** The window reads one lap; a video plays them all. A
`CoachingTrack` (`Sources/TelemetryKit/CoachingTrack.swift`) reads every complete lap of a data
input against the project's coaching reference — the reference's corners and the session's
consistency read once and shared, so thirty laps cost thirty profiles rather than nine hundred —
and answers, at any moment, which lap is being driven and which corner is in play: the one being
driven, else the next one from a lead time before its brake point, else the last one for a hold
time after its end. `ProjectCompiler.load` builds one per data input (`MediaKit/CoachingTracks.swift`)
when anything in the project draws from it (`Project.needsCoaching`), off the main thread and reused
across compiles while the inputs, their sessions and the reference are unchanged, and
`RenderPlanner` hands it to each renderer through `ObjectContext.coaching`. The notes are written
in the app's speed unit, the same reading the window makes; the callout re-words its own card in
the object's resolved unit, so an object pinned to mph says feet.
A Script object reads the same track as `data.reference`, `data.corners` and `data.coaching`
(`Sources/Scripting/DataBridge+Coaching.swift`, documented in `docs/scripting.md`) — the corner in
play with both laps' metrics and the callout's own words — so a user can draw a callout the
built-in object does not offer; the compile reads the track when the script mentions them.

**Corner Callout** (`RenderKit/CornerCalloutRenderer.swift`, #323): the card for the corner in
play — the headline coloured by loss or gain, the evidence, what to try wrapped to the card's width,
the headline shrunk to fit rather than clipped. With no session at all (a template's picture) it
draws an example card. Golden `corner-callout-turn1.png` on the committed coaching fixture.

**Track Map** (`RenderKit/TrackMapRenderer+Coaching.swift`, #324): four options, all off by
default so a saved map draws as it did. The reference's line is the coaching reference's profile
positions, dashed. Colour by delta paints the lap being driven over the outline in runs where the
delta grew or shrank by more than 0.03 s over 20 m, leaving level stretches to the plain line.
Brake marks are a circle at the brake point and a square at the slowest point for both laps. Follow
builds a projection over the corner's time span (brake point − 60 m to exit + 60 m) and frames it;
the cached trace image is keyed per lap and per followed corner, so the first frame of each pays
and the rest are a blit.

**Graph ghost** (#325): a lap-axis graph's ghost can be the coaching reference. The reference is a
profile on a distance grid, which is what the lap axis plots against, and its channels are stored
canonically as the session's are, so the same display conversion applies; a channel the profile
does not carry (an OBD temperature, say) has no ghost rather than a wrong one. Older files keep the
best lap.

**The spliced lap as a picture** (#328, `LapTimeWarp(lap:in:sync:splice:in:comparedSync:)`):
Compare Laps' compared side can be the fastest rolling lap or the optimal lap of the same data
input (`LapComparisonSettings.comparedSplice`). The warp maps the lap playing by fraction onto the
splice's distances and takes each distance back to its source lap through the profile's pieces
(`Piece.sourceFrom`), with a pair of knots a hair apart at every seam so nothing is interpolated
across a join; `insertWarped` already cuts the picture at every knot and never inserts before the
end of what it has, so a jump back in session time is just another cut. The Coaching window's
Compare in Video now offers it for those references.

**Compare Corners** (#326, `MediaKit/CornerExports.swift`): `ExportRange.eachCorner` writes one
file per corner of the coaching lap, each from two seconds before its brake point to two seconds
after it, in the project's own layout — so with Compare Laps and a Corner Callout it is the
side-by-side corner clip with the note on it. The corners come from the coaching track (read at
compile when the range asks for it, or on demand for the sheet's preview of the files). The slow
motion through the braking zone and the held frame of the reference's brake point described in
the issue are not in this version; they need a per-piece playback rate the composition does not
have yet and are filed separately.

**Coaching Debrief** (#327, `MediaKit/Debrief.swift`, `DebriefExporter.swift`): Project ▸ Export
Coaching Debrief… writes one video from a `DebriefPlan` — a title card (track, day, best, optimal
and fastest rolling lap, and how far behind the reference the lap read finished), the top
opportunities of the coaching lap as `CornerExport` clips in the project's own layout, and a
closing card with one suggestion per corner from `CoachingNotes`. Each card is one frame drawn by
the project's text objects (`CardWriter`, which wraps the lines itself since the text renderer does
not) and written for its length with the export's codec; each clip is an ordinary range export;
`MovieStitcher` joins the pieces in an `AVMutableComposition` and writes them through a
passthrough export, so nothing is encoded twice. The **Coaching Debrief** template is the layout
the clips are meant to have. The CLI's `--debrief` does the same.

Still to come: the
reference line, gain/loss colouring and brake-point markers on the Track Map, all off by default
(#324); a choosable graph ghost (#325); per-corner comparison clips with the better lap's brake-point
frame held as a sight picture (#326); a Coaching Debrief template and export (#327); the spliced
optimal lap as a picture (#328); corners and the comparison on the scripting bridge (#329).

## Between sessions (v0.31.0)

A next-session plan of three experiments kept with the circuit's track definition (#330); a
printable one-page debrief with the map (#331); per-corner trends across visits (#332); position
alignment for two laps of one session that took different lines (#333); a line heat map (#334); a
spoken debrief (#335).

## Measurements

Filled in as each piece lands and is run against the reference Sonoma session (local only, never
committed).

- **The reference Sonoma session through `onboard coach`** (RaceChrono v3, 93 Hz, 8 complete
  laps, best 1:56.88): 12 corners, as the detector always found. The **fastest rolling lap is
  1:55.81**, spliced from laps 3 and 2 across the line — 1.07 s quicker than the best timed lap,
  which the app had never shown. The optimal lap with four corner-aware sectors is 1:54.52
  (laps 2, 3, 3, 6). Lap 2 (1:56.90) against the best lap: 0.01 s behind over the lap but ±0.6 s
  by corner, the top three being Turn 12 (0.63 s, exit: braked 22 m earlier, coasted 0.49 s
  longer), Turn 7 (0.46 s, exit: 12 km/h slower at the minimum) and Turn 8 (0.43 s, braking:
  braked 12 m earlier). Across the five flying laps, brake points spread 2–8 m at Turns 1, 2, 3
  and 5 and 15–51 m at Turns 7, 8, 11 and 12. Analysis time is lost in the noise next to the
  import: a debug build takes 6.2 s to import the file alone and 5.7 s to import and analyse it.
- Corner metrics on the synthetic fixture (`Tests/TelemetryKitTests/CoachingFixture.swift`: 40 m/s
  straights, a 0.41 g stop to 15 m/s at the apex): brake point within 1 m of the construction from
  recorded pedals and within 3 m from the speed trace; minimum speed within 0.2 m/s; the time lost
  in the four phases sums to the corner's loss to 1 µs. The Sonoma numbers come with #320.

## Deliberately not doing

- **Real-time in-car coaching.** Audio cues or lights while driving need a live GPS feed and a
  different application; Garmin Catalyst, Apex Pro and the phone apps do this. Everything here is
  after the session.
- **A language model writing the debrief.** The notes are rules over measured numbers: the same
  answer every time, testable against fixtures, no network, no key, nothing leaves the Mac.
- **Treating two GPS lines as truth.** The offset between two lines is shown, with the caveat,
  because it is useful relatively; it is never turned into "you were 1.4 m off the apex".
- **An absolute grip score** (Apex Pro's). It needs a vehicle model the data cannot supply.

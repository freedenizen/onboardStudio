# Traffic

Design study: finding the stretches of a lap where another car held the driver up, and keeping
them out of the coaching, the consistency figures and the trends, written so the reasoning can be
re-checked. Issues: marks and their effect #571 and telemetry suggestions #572 (both built: *What
was built* below), the video #573, another car's log #574.

## The problem

The coaching pipeline (`docs/coaching.md`) assumes every difference between a lap and its
reference is the driver's. Traffic breaks that assumption, and nothing today separates it out:

- **Opportunities.** A corner where the driver queued behind a slower car is ranked by time lost
  like any other, and gets a note such as "braked 30 m earlier … coasted 0.8 s longer → try
  closing the gap between brake and throttle". The advice is wrong: the driver lifted because a
  car was there.
- **Consistency.** `ConsistencyStats` drops whole laps more than 10 % off the best
  (`CoachingOptions.flyingLapTolerance`). A lap that lost two seconds behind traffic in one corner
  is inside that limit and its delayed brake point widens the corner's spread. A lap spent behind
  one car is outside the limit and loses *all* its corners, including the clean ones.
- **Defaults and trends.** The Coaching window's default lap is the quickest lap that is not the
  reference. Corner trends across visits, goals and the Season read every flying lap the same
  way. *Skip slow laps* on export is the only traffic-aware control, and it works on whole laps by
  lap time.

**Evidence (local check of the reference Sonoma session against its GoPro clip, 2026-11-13; no
values from it are recorded here).** The session's two largest single-corner losses each have a
car close ahead in the video through that corner, and the best lap shows the same stretch empty.
The slowest complete lap followed one car from start to finish. Every stretch where a lap lifted
while all the others were flat out lines up with a car ahead in the video. The telemetry alone also
flags lifts the video does not explain.

## Signals

Ranked by how much they can be trusted on their own.

### 1. The driver says so (always wins)

Select a stretch of a lap and mark it as traffic, or dismiss a suggestion. Nothing else can tell
traffic from a yellow flag, a point-by, a spin ahead or a car in the pit lane. A flag is the same
thing to coaching, so the mark has a kind (*Traffic*, *Flag*, *Other*). Undoable ("Mark Traffic",
"Dismiss Traffic Suggestion"). This alone is enough to fix the coaching. Every other signal only
spares the driver from marking by hand.

### 2. Video: a car ahead in the picture

The forward camera sees exactly what matters: a car ahead and how fast the gap is closing.

- **Detector.** Apple's Vision framework has no vehicle detector. A COCO-trained detector (COCO
  has *car*, *truck*, *motorcycle*) converted to Core ML with `coremltools`, bundled, run through
  `VNCoreMLRequest` on the Neural Engine. **Licence matters:** the repo is MIT. YOLOX (Megvii)
  and RT-DETR from its original repository are Apache-2.0. Ultralytics' YOLO, and RT-DETR loaded
  through the Ultralytics package, are AGPL-3.0 and must not be used. Size ranges from a few MB
  (YOLOX-Nano/Tiny) to ~35 MB (YOLOX-S); the spike picks the smallest that holds up.
- **Frames.** `PictureMotion` already reads a clip through `AVAssetReader` at a reduced size with
  hardware decode. Traffic needs 4–5 frames a second, not 30. Decoding is the main cost; inference
  is small next to it.
- **Resolution.** Detect on the native-resolution crop of the windscreen, not the whole frame
  scaled to the model's input. On a 2.7K helmet camera a car close ahead is about 100 px wide.
  Scaled whole to 640 px it is a few dozen pixels and a car further away vanishes.
- **Which detections count.** A car ahead on the circuit, not one in the rear-view mirror, the
  pit lane or another part of the track in view. Rules: below the horizon, which comes from the
  camera's gravity vector where GPMF has `GRAV`/`CORI` (`docs/formats.md`, GoPro orientation) and from the
  picture otherwise; inside the band of the picture the road occupies; present for at least
  1.5 s; and a gap that changes with the speed difference, not the car's own speed.
- **Gap.** Range ≈ focal length × car width ÷ box width (a car is about 1.8 m wide; the focal
  length in pixels per radian comes from the lens metadata the CORI work already reads). With the
  car's speed, a gap in seconds. *Following within ~1.5 s* is the threshold that matters to
  coaching, and is a parameter.
- **Mounts.** A windscreen or roll-bar mount gives a steady frame. A helmet mount (the user's
  setup) moves with the head; the detector is per frame so that is fine, but the horizon and road
  band must move with it. A rear-facing camera would add *being caught*, out of scope for now.
- **Cost.** Analysed once per clip, in the background, with progress, and cached beside the clip
  as `PictureMotion` is.

#### The spike (#593)

Run locally on the reference session's two GoPro chapters (HERO13, 2.7K at 120 fps, helmet camera
in a closed car) on an Apple M4. YOLOX-Nano and YOLOX-Tiny (Megvii, Apache-2.0, COCO) were
converted to Core ML ML Programs in FP16 with `coremltools`; the network's raw head is the model's
output, and decoding and non-maximum suppression are a few lines after it. Stretches of a
few minutes were hand-labelled, one label every 4 s: a car close ahead on the circuit, clear
track, or the pit queue. They included the corners the telemetry and the video already showed
were traffic, the best lap, a lap spent behind one car, and the paddock. No value from that session
is recorded here.

- **Verdict: go, with YOLOX-Nano at 640 px on a crop.** Nano at a 640-px input, fed a
  native-resolution crop of the middle of the picture (about 70 % of its width, from an eighth to
  three-fifths of its height), found every labelled stretch with a car ahead. On the clear stretches
  its only hit was a car leaving the edge of the picture at the end of a labelled stretch. The
  Core ML model is **1.9 MB** (Tiny 9.8 MB); the size answers the open question below.
- **The input size and the crop matter more than the model.** Nano at 416 px missed many
  stretches on the crop, and more on the whole frame. Tiny holds up at 416 px and on the whole
  frame, for five times the size. Pixels on the car ahead are what count.
- **What counts as a car ahead.** COCO *car*, *truck*, *bus* or *motorcycle* at a score (class ×
  objectness) of 0.4 or more; a box 30 to 600 px wide in a 2,704-px frame; its centre in the middle
  three-fifths of the width; its bottom below the top 30 % of the height; seen on consecutive
  samples for 1.5 s. The **upper width limit is the rule that matters most**: COCO's *car* fires on
  the car's own cabin (the dashboard, the windscreen frame and the mirror as one huge box) on nearly
  every frame, and without the cut almost every clear stretch was a car ahead. Every number is a
  parameter.
- **The horizon cannot be fixed.** A helmet camera pans and tilts through every corner, and the
  horizon moves across a third of the picture's height. A generous fixed band worked better than
  any tighter guess; the gravity vector from `GRAV`/`CORI` remains the way to follow it, if a later
  version needs to.
- **What it cannot tell.** The pit queue and the paddock are cars directly ahead, and every
  setting detects them: the telemetry's speed and lap gate them out, as for another car's log
  (#574). The rear-view mirror shows the cars behind; one got through at Tiny's weakest margin
  and none at Nano's. Rejecting boxes that touch the crop's edge removes the stray single frames,
  mostly the mirror and the A-pillar. Box width puts a car ahead at very roughly 45 to 90 m: enough
  to say *a car ahead*, not to measure the gap the way another car's log does.
- **Decoding is the cost, and keyframes remove it.** At 120 fps every frame must be decoded to
  sample five a second: about 40 s for each minute of footage with VideoToolbox, two-thirds of real
  time, whichever decoder. Inference is small beside it: 12 ms a frame for Nano at 640 px on the
  Neural Engine (6 ms at 416, Tiny 7 and 15 ms). A GoPro writes a keyframe every second, and
  decoding only those costs under a second per minute of footage. Sampling the detections at one
  keyframe a second and asking for two in a row kept nearly every stretch, at every phase offset,
  for no more false positives. **One frame a second from keyframes** puts a whole session within a
  minute of work.
- **Per corner.** Like the telemetry's, a video suggestion belongs to a corner: the share of
  the corner's keyframes with a car ahead, half or more, is steadier than one run of hits.

Not measured: a 4K clip, a windscreen or roll-bar mount, night or rain, and other cameras.

### 3. Telemetry: candidates, not verdicts

Cheap, works for any logger, but cannot tell traffic from a mistake. It finds the stretches to
look at and corroborates the video:

- **A lift where the driver is normally flat out.** Throttle well below its value on most other
  laps at the same distance, for 20 m or more. Without a throttle channel, longitudinal
  acceleration negative where it is normally positive. This fires on every traffic stretch found
  in the local check and on some that were not traffic.
- **A corner far outside its own spread.** Time lost greater than a few times the corner's spread
  across the flying laps (`ConsistencyStats` already has the spread).
- **Off the line on a straight.** Position offset from the session's median line
  (`PositionMatcher` gives it). This is how a pass looks, or a point-by.
- **A run of corners all slow, ending in a pass.** Loss spread evenly over several corners, with
  earlier braking and lower minimum speeds, that stops where the car moves off line. This is
  following.

### 4. Another car's log

When the logbook holds another car's session at the same circuit and the same clock (the data
behind Car vs Car), the gap between the two GPS traces is measured, not inferred. Exact, but
rarely available. Worth doing once the model exists, because it is nearly free.

Not pursued: audio (the engine drowns another car), flag recognition in the picture (too rare and
too varied; the driver marks a flag).

## What was built (#571)

The driver's own marks and everything they change in the coaching; no detection yet.

- `TrafficSpan` (`Sources/TelemetryKit/Traffic.swift`): an id, a start and end in session time, and
  a kind, *traffic* or *flag*. A third *other* kind was left out: nothing yet reads it differently.
- Kept in `CoachingSettings.traffic` — on `Project.coaching` for a project and on
  `LogbookEntry.coaching` for a session coached from the Logbook — rather than on the data input's
  settings: a change there would re-import the file (`ProjectCompiler.isUnchanged` compares the
  input's kind), and the Logbook already keeps coaching settings per session. The marks apply to
  the input the settings name. The compile and the Logbook's source put them on
  `TelemetrySession.traffic`; the Coaching window applies the marks it holds before it reads, so
  a mark reads at once rather than after the compile.
- Marking by hand from the walkthrough's corner step (*Leave This Corner Out*), the table's
  context menu and the corner's detail; one undo step each. A mark covers the stretch the corner
  was read over on that lap (`CoachingAnalysis.sessionTimes(of:)`); marking a stretch splits or
  replaces what was there (`[TrafficSpan].marking`).
- The effects listed under *What the coaching does with it*, except the clean-lap estimate, the
  trends across visits, shading on the track map and *Skip laps with traffic*: the headline names
  the loss in marked corners instead of estimating a clean lap time, and the rest waits for #554
  (whole laps that should not count) and the detection issues.
- No schema step: with only explicit marks, a project without marks reads as it did. The pin
  described under *Compatibility* comes with the first suggestion that applies itself (#573).

## What was built (#572)

Telemetry suggestions, read on demand and never applied on their own.

- `TrafficSuggestions.find` (`Sources/TelemetryKit/TrafficSuggestions.swift`) reads one suggestion per
  lap and corner. A corner owns the lap from the quickest lap's brake point for it to the brake point
  for the next, the way the corner table divides the lap, so a slow run out behind a car counts
  towards the corner whose time it cost. Two signals: a *lift* where most other laps are flat out
  (throttle as a fraction of its own range; the speed trace without one), and a *slow corner*,
  judged against the quicker half of the laps. On the reference Sonoma session the median of all
  the laps missed a corner the video shows was traffic, because half the laps were held up there.
- Off the line on a straight and the run of slow corners ending in a pass are not built: GPS
  scatter on a phone or a GoPro is about the width of the move a pass makes, and both need the
  video to be worth showing.
- The Coaching window and `onboard coach --suggest-traffic` ask for them
  (`CoachingOptions.suggestsTraffic`); the compile and the renders never do, so no saved project
  renders differently and nothing is pinned. A suggestion hangs on its corner
  (`CornerComparison.suggestion`) and the corner is coached as before until the driver marks it.
- **Not Traffic** keeps the stretch in `CoachingSettings.dismissedTraffic`, data the driver made;
  the suggestions themselves are read again each time, so a better detector replaces them freely.
- No `source`, `confidence` or `state` on `TrafficSpan` yet: a suggestion is a separate type until a
  detector can apply itself (#573), and a confirmed suggestion is a mark like any other.

## What was built (#574)

Another car's log, read whenever the Coaching window reads a session.

- `CarsAhead.following` (`Sources/TelemetryKit/CarsAhead.swift`) puts both GPS traces on one plane
  and, every 0.2 s, asks how long ago the other car passed this one's position, searching its last
  1.5 s for the nearest point. Nearest point rather than distance along a lap, so it needs no shared
  start line, counts a lapped car, and ignores a car on the other side of the circuit or in the pit
  lane. Under 0.2 s is alongside (or the same file read twice); under 8 m/s is a queue.
- Runs of 2 s or more become `TelemetrySession.carsAhead`, and feed the same per-corner suggestions
  as the telemetry, as their first piece of evidence. Following a friend can be deliberate, so it
  is still a suggestion, but it needs no three laps to say what is usual.
- The window finds the other sessions in the Logbook: the same circuit key, begun within the half
  day before this session ended, not this session's own file
  (`LogbookReferences.sharingTheTrack`). `onboard coach --other-car file[=name]` does the same from
  a file. Nothing is saved: the gaps are read again each time, like the other suggestions.

## What was built (#573)

The video, read on request and kept per file.

- `VideoTraffic` (`Sources/MediaKit/VideoTraffic.swift`) reads the keyframe nearest each second
  with `AVAssetImageGenerator`, so a 120-fps GoPro clip costs one decoded frame a second, crops it
  and runs the bundled YOLOX-Nano. The rule is the spike's, in fractions of the picture so any
  resolution works. The spike's per-file timing held up: in a release build a 2.7K chapter reads at
  about 1.4 s per minute of footage on an M4; a debug build is five times slower.
- The model is committed compiled (`TrafficDetector.mlmodelc`, 2 MB) with its Apache-2.0 licence
  beside it, because SwiftPM does not compile Core ML models. `Scripts/make-traffic-detector.py`
  rebuilds it from Megvii's weights (byte-identical weights when checked).
- `VideoTraffic+Placing` puts the readings on the session's clock: through the project's syncs
  for a project, through the recording time for the Logbook's clips. They become
  `TelemetrySession.pictureSamples`, and a corner with a car ahead in half its pictures and two in
  a row gets `.inPicture` evidence on the same per-corner suggestions as the telemetry and another
  car's log. They wait for the driver.
- The Coaching window offers **Find Traffic in Video** in a bar under the coaching while any of the
  session's video is unread, with progress and Stop; the reading runs in `TrafficVideoJobs`, apart
  from the window. `onboard traffic` reads clips on their own; `onboard coach --detect-traffic`
  reads a project's.
- Checked locally against the reference session: the stretches the spike labelled come out the
  same, and the corners already known to be traffic are suggested from the video. Not built: the
  gap from the box width, the horizon from `GRAV`/`CORI`, the edge test for the mirror, and video
  in the track map or the Corner Callout.

## The model

A `TrafficSpan` in `TelemetryKit`: a stretch of session time, with

- `kind`: following, passing, being passed, flag, other;
- `source`: driver, video, telemetry, other car;
- `confidence` and, from the video, the closest gap (metres and seconds);
- `state`: suggested, confirmed, dismissed. Only confirmed spans, and suggestions at or above a
  confidence the driver can set, take effect.

Stored per data input in the project (a new optional field; see compatibility) and on the logbook
entry, so the logbook's Coach… and Trends read the same marks. Detection results are a cache and
can be thrown away; the driver's own marks and dismissals are data.

## What the coaching does with it

The span is projected onto each lap's distance and, through the corners' phase windows
(`CornerComparison`), onto corners.

- **Opportunities.** A corner impeded on the lap read, or on the reference, is not an
  opportunity. It stays in the corner table with *Traffic* in place of a phase, and gets no
  suggestion. The headline names the time behind traffic separately: "Lap 7: 2.4 s behind your
  best lap, 1.8 s of it behind traffic" (invented figures).
- **Consistency.** Per corner, not per lap. An impeded corner reading is left out, and the rest of
  that lap still counts. `flyingLapTolerance` stays as the filter for out and in laps.
- **Default lap.** The quickest lap with no impeded corner, falling back to today's rule.
- **References.** The best, rolling and optimal laps are rarely impeded, because traffic makes
  them slow. An impeded reference corner is warned about (a new `CoachingWarning`), as a seam is.
- **A clean-lap estimate.** A lap's time with each impeded corner replaced by that corner's median
  clean reading: "1:42.6, about 1:41.8 without traffic". Always labelled an estimate, never a lap
  time.
- **Across visits.** Corner trends, consistency goals and the Season read only clean corner
  readings.
- **In the video.** The Corner Callout shows a *Traffic* card instead of a misleading note. The
  Debrief and *Compare Corners → only opportunities* skip impeded corners. The track map can shade
  traffic stretches. Export gains *Skip laps with traffic* beside *Skip slow laps*.
- **CLI.** `onboard coach` gains `--traffic <file>` (marks as JSON) and `--detect-traffic <clip>`,
  so every piece is checked against real sessions before it reaches the window, as the coaching
  was.

## Compatibility

Opening a saved project never changes how it renders. The Corner Callout's words and the Debrief's
corners would change once traffic is excluded, so a project saved before this feature keeps
`excludeTraffic = false`, pinned in `Project.migrateIfNeeded()` with a schema step; new projects
start with it on. The coaching window's reading is not a render and follows the setting too, so
an old project reads as it did until the driver turns it on.

## In the app

- **Suggestions, never silent.** Detected spans appear as suggestions on the lap strip and in the
  corner table ("Traffic? — from the video"), with Confirm and Dismiss, and a setting to take the
  video's suggestions without asking.
- **Mark by hand** from the corner table's context menu ("Mark Turn 7 as Traffic"), from a lap's
  range in the timeline, and in the Logbook's session detail.
- **Find Traffic** runs the video analysis for the session's clips, with progress in the activity
  log. Offered when a session has clips and none has been analysed.
- Undo names, VoiceOver labels and keyboard access as `.claude/rules/appui.md` requires.

## Order of work

1. **Marks and their effect** (#571, built). `TrafficSpan`, marking by hand, the coaching,
   consistency, default lap, callout and debrief changes, the CLI `--traffic`. Useful with no
   detection at all, and it is what every detector feeds.
2. **Telemetry candidates** as low-confidence suggestions, on synthetic fixtures with an invented
   car ahead (#572, built).
3. **Video spike** (#593, done): go, with YOLOX-Nano at 640 px on a crop, 1.9 MB, one keyframe a
   second. See *The spike* above.
4. **Video detection** in the app and the CLI, cached per clip (#573, built).
5. **Another car's log** from the logbook (#574, built).

## Open questions

- Should video suggestions apply without confirmation by default, or wait for the driver? They
  wait (#573): a car the driver chose to follow looks the same as one in the way.
- How large a bundled model is acceptable? Answered by the spike: the model that holds up is 1.9 MB.
- Should a flag count the same as traffic everywhere, or be shown differently in the Logbook?

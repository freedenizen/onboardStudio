# Testing Onboard Studio

Every milestone is verified in three layers. Run the first two yourself after any change; the
third exists once the app has a GUI (milestone M4).

## 1. Automated tests

```sh
swift test                                  # everything (unit + fixture + media tests)
swift test --filter ImportersTests          # one target
swift test --filter "RaceChrono"            # tests whose name matches
```

- **TelemetryKit / Importers**: pure-function tests against the synthetic fixtures in
  `Tests/Fixtures` (RaceRender CSV, RaceChrono v3 CSV, GPX). Add a fixture and a test for every
  new format or parsing rule.
- **RenderKit**: pixel-probe tests render small frames with `FrameCompositor` and assert colours
  at known coordinates. Golden-image tests join in M3 (`UPDATE_GOLDENS=1 swift test` regenerates).
- **MediaKit**: real AVFoundation round-trips on `Tests/Fixtures/test-3s.mp4`: probe, build a
  composition, export, then decode a frame of the *output* and check the overlay is there. When
  `ffprobe` is installed the output is cross-checked with it; otherwise that test is skipped.

CI runs the same suite on every pull request together with the two lint jobs, the XCUITest
journeys and the commit signature check; those are the required checks, and a PR cannot merge
until they pass. What a PR does not wait for runs afterwards: the push to `main` repeats the
suite with coverage and, when red, opens the issue labelled `main-red`; the **Nightly** workflow
runs the ffprobe-backed media tests (no PR runner has ffprobe, so they skip there), a headless
`onboard render` of the fixture project, an unsigned app bundle and the overlay benchmark
against a budget, and opens `nightly-red` when it fails. CodeQL's Swift analysis runs on every
PR but does not block it. Locally, `Scripts/test.sh quick` skips the two-hour session and the
fuzz suites; `Scripts/test.sh full` is what CI runs.

Fuzz suites mutate every fixture (byte flips, truncation, inserted garbage, digit storms) with a
fixed seed and feed them to every importer, the GPMF/MP4 readers, the expression parser and the
spherical-metadata reader; throwing is fine, crashing or hanging is the failure. Raise the
iteration counts locally when hunting a bug; CI runs the committed counts.

### UI tests (XCUITest)

`UITests/OnboardStudioUITests` drives the real app through its windows, menus, inspectors and sheets,
one class per user journey in [journeys/](journeys/) (see [user-journeys.md](user-journeys.md)). Run them with
`Scripts/ui-tests.sh` (or `Scripts/ui-tests.sh JourneyUITests` for one class); CI runs them in the
**UI tests** job and keeps the `.xcresult` on failure. The app is launched with `-uiTesting YES`,
which adds a **Testing** menu that adds the fixture files (open panels cannot be scripted) and with
`ONBOARD_TEST_EXPORT_DIR` so exports skip the save panel. Icon-only controls carry accessibility
identifiers (`toolbar.*`, `transport.*`, `object.<label>`, `input.<label>`, `tour.*`, `export.*`,
`sync.*`, `status.message`); text controls are found by their titles.

The Debug build the UI tests run is **`com.freedenizen.onboardstudio.dev`**, a different app to
macOS from the installed one (#293). Sharing the installed app's identifier, test runs filled its
**recent projects** with throwaway projects that were then deleted, emptying the list, and wrote
its preferences. Each launch also gets its own folder for the user's templates
(`ONBOARD_TEST_TEMPLATES_DIR`) and for picture-motion measurements (`ONBOARD_TEST_MOTION_DIR`, #288).

## 2. Headless checks with the CLI

The `onboard` tool exercises the same libraries the app uses, without the GUI:

```sh
swift run onboard probe path/to/session.csv            # what channels/laps were read?
swift run onboard probe session.csv --at 95.5          # interpolated values at a time
swift run onboard probe session.csv --json             # machine-readable

swift run onboard render --video clip.mp4 --out out.mp4 --range 0:10      # M2 pipeline check
swift run onboard render --video clip.mp4 --out out.mp4 --preset 720p --codec hevc --speed 2
swift run -c release onboard bench --project my.onboardproj --export --codec hevc --seconds 60   # M14 speed check
```

`render` re-encodes the clip through the AVFoundation composition and custom compositor with a
burned-in project-time stamp. Open the result in QuickTime Player: the clock in the corner should
start at 0:00.00 and advance smoothly, audio should be intact, and `--range`, `--start-position`
and `--speed` should shift/scale exactly as their values say. This is the quickest way to confirm
the pipeline on a file from *your* camera.

## 3. Manual QA scripts (from M4)

Each GUI milestone adds `docs/qa-mN.md`: a short numbered script of clicks and expected results
(import a video and data file, drag the sync slider, place a gauge, scrub, export). Run it once
before tagging a release.

## Per-milestone checklist

| Milestone | What to run | What to look for |
|---|---|---|
| M1 telemetry | `probe` on your own logs | Every channel you expect is listed with sensible min/max/Hz; laps match the logger app |
| M2 media | `render --range 0:10` on your own clip | Plays in QuickTime, timestamp visible, audio in sync, size/fps as requested |
| M3 objects | `render --project Tests/Fixtures/slice.onboardproj --out slice.mp4`, then your own project (`docs/project-format.md`) | Gauges move with the data, track map dot follows the car, lap timer resets at the line; golden images in `Tests/Fixtures/Goldens` show what each object should look like |
| M4 app | `docs/qa-m4.md` | Preview frame == exported frame at the same time |
| M5 inputs | `docs/qa-m5.md` | Rotation/mirror/crop/colour/chroma key change the preview immediately; volume, balance and channel selection are audible; MTS files import when ffmpeg is installed |
| M6 data | `docs/qa-m6.md`; `probe file --lap-line lat,lon,heading` on your own log | Detected lap times match your logger app; channel mapping fixes a mis-detected column; calculated field shows in Text Data |
| M7 gauges | `docs/qa-m7.md`; goldens in `Tests/Fixtures/Goldens` (`gauge-*`, `bar-*`, `graph-*`, `gear-*`, `lapcounter-*`, `timer-delta-*`) | Every designer option changes the preview live; a `.onboardstyle` round-trips; the delta timer reads 0.00 on the best lap |
| M8 timeline | `docs/qa-m8.md`; `TimelineMediaTests` exports a two-camera switch at 1.5 s and pixel-probes both sides | Segment badges show what is set where; a camera switch lands on the same frame in preview and export |
| M9 templates/export | `docs/qa-m9.md`; `ExportOptionsTests` (lap-range duration, key-colour and ProRes-alpha exports, missing media) | A lap export is exactly the lap long; a transparent export composites cleanly in another editor; templates rebind to new inputs |
| M10 GoPro/FIT/auto-sync | `docs/qa-m10.md`; `GPMFKitTests` build a synthetic MP4 with a `gpmd` track; `FITTests` encode a FIT file in-test; set `ONBOARD_SAMPLES_DIR` to also run against a real HERO13 clip | Use Embedded GPS gives a moving map from the video alone; adding a RaceChrono file next to the GoPro clip syncs to within a second without the wizard |
| M11 scripting | `docs/qa-m11.md`; `ScriptingTests` (data API, canvas pixels, error badge, examples, RaceRender-style names, frame budget) | An example script draws live; a typo shows a badge and an inspector message, never a crash; the busy-script test stays under 4 ms/frame |
| M12 lens/360/maps | `docs/qa-m12.md`; `LensUnwrapTests` (synthetic equirectangular and fisheye sources on both kernel backends, golden), `SphericalMetadataTests` (uuid box present, file still decodes, ffprobe reports a spherical mapping when installed), `TrackMapExtrasTests` (two-vehicle and map-background goldens) | A 360° clip shows a flat, pannable view; a tagged export plays as a panorama in QuickTime Player; a second data input appears as a second dot; a map background lines up with the outline |
| M13 motion sync / YouTube / sidecars | `docs/qa-m13.md`; `SignalCorrelationTests`, `MotionSyncTests` (a synthetic clip with motion bursts is written with AVAssetWriter and matched against a shifted speed log), `YouTubeKitTests` (device flow, token refresh and a resumable upload with a dropped chunk against a mock Google served by a `URLProtocol`), `DJISRTTests`, `CompanionTelemetryTests` | Auto-Sync by Motion lands within a second of the manual sync on the real project; `onboard sync` prints a convincing match; a DJI clip's SRT is offered as sidecar data; an upload reaches YouTube after the device-code sign-in |
| M14 performance/hardening | `onboard bench [--export]`; `LongSessionTests` (two-hour 20 Hz session, memory flat, frames quick), fuzz suites (`ImporterFuzzTests`, `GPMFFuzzTests`, `ExpressionFuzzTests`, `SphericalFuzzTests`) with fixed seeds; `docs/parity.md` | 4K HEVC export faster than real time on Apple silicon; resident memory flat over a long export; no importer crashes on mutated files |
| M15 guided experience / video editing | `docs/qa-m15.md`; `VideoEditingModelTests` (crop composition, zoom window, decoding defaults, chapter naming), `ClipSequenceTests` (clips play back to back in one track; trim and speed cover the sequence) | A new project explains itself; GoPro chapters join as one video; the video lane moves and chains clips; camera framing reframes every video at once |
| 0.18 see-through overlays | `GlassCockpitModelTests` (wheel scale/sign/limit, channel binding for degrees/radians/normalised, template binds when data arrives, old files decode), `steeringWheelMarkerTurnsWithTheAngle` (golden + marker position), `gradientShapeFadesAndTheOverlayLayerCanFade` | The Glass Cockpit template renders a turning translucent wheel over real footage; `onboard render --template "Glass Cockpit"` applies a built-in template by name |
| 0.17 native lap deltas | `LapDeltaChannelTests` (every lap against the session best, zero on the best lap, short fragments cannot be best), `LapDeltaReferenceTests` (sample-by-sample against the user's `racechrono_add_deltas.py` output, gated on `ONBOARD_SAMPLES_DIR` + `ONBOARD_DELTA_REFERENCE_CSV`), `deltaBarGrowsEitherSideOfZero`, `deltaSettingsKeepOldFilesUnchanged` | Delta bars, graphs and readouts work from a plain RaceChrono export with no external script |
| 0.16.2 adding videos | `InputPlanningTests` (first recording opens a lane, duplicates skipped, a second recording opens its own lane, later chapters join the recording they continue, template objects bind to the inputs that arrive), `RecordingGapsTests` (no clock = no gap; real GoPro chapters butt together and recordings are minutes apart, gated on `ONBOARD_SAMPLES_DIR`) | New from Template shows its gauges, they bind to the video and data added afterwards; two recordings play in sequence on their own lanes instead of stacking |
| M16 timeline editing | `docs/qa-m16.md`; `ClipModelTests` (both clip forms decode, chapter grouping, snapping), `ClipEditingTests` (per-clip trim and gap shape the track and render black gaps; a rotated chapter keeps its orientation end to end) | Dragging a bar's edge trims it; the magnet snaps to edges and the playhead; ⌘= zooms the timeline; dropped GoPro chapters become one input |
| M17 viewer pan / clip speed / overview | `docs/qa-m17.md`; `ClipSpeedTests` (a double-speed clip takes half the sequence and shows the right frame; speed decodes) | Dragging the zoomed picture pans it; a clip's Speed field shortens the bar; the overview strip scrolls the zoomed timeline |
| 0.19 launcher, CAN bus, steering auto-detect | `TurnDirectionTests` (yaw rate from GPS heading, correlated with the steering channel, picks the sign), `LauncherUITests` | A RaceChrono CAN export files channels as `canbus:`; the steering wheel turns the way the car does without being told |
| 0.20 the timeline works like an editor | `docs/qa-m16.md` and `qa-m17.md` are superseded by the XCUITest journeys J3a–J3e and J8 (`MarkerUITests`, `TrimUITests`, `SplitUITests`, `DataEditingUITests`, `TimelineUITests`, `SyncUITests`); model: `MarkerTests`, `VideoSplitTests`, `SessionTrimTests`, `LapNavigationTests` | A split makes a trimmed first half, a second input, a hidden second object and a segment that swaps them; the sync panel stays under the preview |
| 0.21 knowing the track | `SectorsTests`, `CornerDetectorTests` (12 corners on Sonoma), `CircuitCatalogTests`, `StartFinishFinderTests`, `TrackExtentTests`, `TrackMapDisplayTests` goldens, `SectorPanelTests`; `LapUITests`, the sector-panel journey in `ObjectEditingUITests`; `onboard probe` prints the circuit match, the sector table and `--corners` | The start/finish suggestion lands on the line the logger used; the pit lane drops off the map; sector deltas that round to 0.00 draw in the text colour |
| 0.21.x units | `SpeedUnitInheritanceTests`, `RecordedSpeedUnitTests` (a kph file through `SessionBuilder` answers kph, not the canonical m/s), `GraphSeriesScaleTests` | A new object shows "Automatic" and says what that resolves to; throttle and brake pressure share one graph legibly |
| 0.22 attributes and units | `AttributeMappingTests`, `DisplayUnitTests`, `SpeedUnitInheritanceTests`, `ScaleFittingTests`, `GraphSeriesScaleTests`, `RCZTests`, `VBOUnitTests`, `ImportReportTests`; `AttributeMappingUITests`, `ImportReportUITests` | A channel mapped once is read that way in every file afterwards; units convert for display only |
| 0.23 mapping scope | `AttributeMappingScopeTests`, `AttributeFilterTests`, `ChannelPickerTitleTests`, `GlobalMappingReloadTests`, `MappedChannelAliasTests` | A global mapping reaches an open project without reopening it |
| 0.24 your own details, and the editor | `ProjectDetailsTests`, `SessionDetailsTests`, `TemplateLibraryTests`, `TemplateThumbnailTests`, `TypefaceTests`, `TypefaceModelTests`, `LockAndGroupTests`, `BarOrientationTests`, `DiagnosticsTests`; `DetailsUITests`, `FontUITests`, `TemplateLibraryUITests`, `GroupLockUITests`, `ActivityUITests`, `DiagnosticsUITests`, `AccessibilityUITests` | A title card fills in from the data file; a locked object lets clicks through; a template shows its picture |
| 0.25 sharing the result | `LapExportsTests`, `VerticalClipTests`, `StatCardTests`, `SessionStatsTests`; `ExportLapsUITests`, `VerticalClipUITests`, `UndoUITests` | Every lap writes its own file; a lap exports as a 1080 × 1920 clip with the stat card |
| 0.26 analysis | `LapTimeWarpTests`, `ComparedLapTrackTests` (AVFoundation's own time mapping of the retimed track), `CompareLapsLayoutTests`, `GraphPlayheadMigrationTests`, the graph goldens (`graph-*-middle-*`, `graph-gg-8s`); `CompareLapsUITests` | Two laps reach every corner together; old graphs still draw at the right edge |
| Stabilisation (#140) | `OrientationTests` (synthetic MP4 with CORI/IORI and a settings block), `StabilisationTests` (a shake is cancelled while a turn is followed; the compositor moves the frame the right way), `PictureMotionTests` (a jittering video is measured and its steadied frames stand still), `GyroflowTests`, `StabilisationSettingsTests`; `StabilisationUITests`. Local only: `StabilisationSampleTests` with `ONBOARD_SAMPLES_DIR` (the real helmet clip must shake under 70 % as much), `gyroflowKeepsTheTimingOfTheRecording` with Gyroflow installed and `ONBOARD_GYROFLOW_CLIP` set to a short GoPro clip | A helmet clip steadies with each method; sync and telemetry are unchanged; a missing Gyroflow copy shows the recording |
| M18 native RaceRender objects | `docs/qa-m18.md`; `IndicatorPanelTests` (ABS light off/on goldens, hold time, timing panel golden, text-data zones), `SpeedDeltaTests`, `IndicatorParamsTests` (channel/threshold suggestions, template adaptation, panel decode defaults), `ReferenceLapTests` (best vs previous lap) | The ABS light lights amber when the channel crosses its level; the timing panel shows best/previous/current and both delta lanes; water/oil readouts turn amber/red at their thresholds |

## Release smoke test

Before tagging: check the nightly is green (it built the bundle and ran the render), then
`Scripts/release.sh`, install the DMG, launch the app, check "Check for Updates…" opens the
Sparkle dialog, and run the current milestone's QA script.

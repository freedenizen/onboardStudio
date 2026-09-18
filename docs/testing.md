# Testing OverlayGen

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

CI runs the same suite on every pull request together with lint, an app build and the commit
signature check; a PR cannot merge until all four pass.

## 2. Headless checks with the CLI

The `overlaygen` tool exercises the same libraries the app uses, without the GUI:

```sh
swift run overlaygen probe path/to/session.csv            # what channels/laps were read?
swift run overlaygen probe session.csv --at 95.5          # interpolated values at a time
swift run overlaygen probe session.csv --json             # machine-readable

swift run overlaygen render --video clip.mp4 --out out.mp4 --range 0:10      # M2 pipeline check
swift run overlaygen render --video clip.mp4 --out out.mp4 --preset 720p --codec hevc --speed 2
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
| M3 objects | `render --project Tests/Fixtures/slice.overlayproj --out slice.mp4`, then your own project (`docs/project-format.md`) | Gauges move with the data, track map dot follows the car, lap timer resets at the line; golden images in `Tests/Fixtures/Goldens` show what each object should look like |
| M4 app | `docs/qa-m4.md` | Preview frame == exported frame at the same time |
| M5 inputs | `docs/qa-m5.md` | Rotation/mirror/crop/colour/chroma key change the preview immediately; volume, balance and channel selection are audible; MTS files import when ffmpeg is installed |
| M6 data | `docs/qa-m6.md`; `probe file --lap-line lat,lon,heading` on your own log | Detected lap times match your logger app; channel mapping fixes a mis-detected column; calculated field shows in Text Data |
| M7 gauges | `docs/qa-m7.md`; goldens in `Tests/Fixtures/Goldens` (`gauge-*`, `bar-*`, `graph-*`, `gear-*`, `lapcounter-*`, `timer-delta-*`) | Every designer option changes the preview live; a `.overlaystyle` round-trips; the delta timer reads 0.00 on the best lap |
| M8 timeline | `docs/qa-m8.md`; `TimelineMediaTests` exports a two-camera switch at 1.5 s and pixel-probes both sides | Segment badges show what is set where; a camera switch lands on the same frame in preview and export |
| M9 templates/export | `docs/qa-m9.md`; `ExportOptionsTests` (lap-range duration, key-colour and ProRes-alpha exports, missing media) | A lap export is exactly the lap long; a transparent export composites cleanly in another editor; templates rebind to new inputs |
| M10 GoPro/FIT/auto-sync | `docs/qa-m10.md`; `GPMFKitTests` build a synthetic MP4 with a `gpmd` track; `FITTests` encode a FIT file in-test; set `OVERLAYGEN_SAMPLES_DIR` to also run against a real HERO13 clip | Use Embedded GPS gives a moving map from the video alone; adding a RaceChrono file next to the GoPro clip syncs to within a second without the wizard |
| M11 scripting | `docs/qa-m11.md`; `ScriptingTests` (data API, canvas pixels, error badge, examples, RaceRender-style names, frame budget) | An example script draws live; a typo shows a badge and an inspector message, never a crash; the busy-script test stays under 4 ms/frame |
| M12 lens/360/maps | `docs/qa-m12.md`; `LensUnwrapTests` (synthetic equirectangular and fisheye sources on both kernel backends, golden), `SphericalMetadataTests` (uuid box present, file still decodes, ffprobe reports a spherical mapping when installed), `TrackMapExtrasTests` (two-vehicle and map-background goldens) | A 360° clip shows a flat, pannable view; a tagged export plays as a panorama in QuickTime Player; a second data input appears as a second dot; a map background lines up with the outline |
| M13+ | milestone QA script + `swift test` | Listed in each PR |

## Release smoke test

Before tagging: `Scripts/release.sh`, install the DMG, launch the app, check "Check for Updates…"
opens the Sparkle dialog, and run the current milestone's QA script.

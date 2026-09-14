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
| M5+ | milestone QA script + `swift test` | Listed in each PR |

## Release smoke test

Before tagging: `Scripts/release.sh`, install the DMG, launch the app, check "Check for Updates…"
opens the Sparkle dialog, and run the current milestone's QA script.

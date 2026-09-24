# J27 Stabilise with Gyroflow
*Source: #263 (from #140) — Gyroflow steadies GoPro footage best, but its copies lose the GPS and
timing a project's sync reads, and nothing said how to install it.*

1. Without Gyroflow: **Stabilisation ▸ Steady ▸ With Gyroflow** says it is not installed and how to
   install it (`brew install --cask gyroflow`, or gyroflow.xyz); the user guide has the steps.
2. With it: **Stabilise with Gyroflow**. A progress bar follows the render; **Cancel** stops it.
3. When it finishes the preview shows the steadied copy, written beside the recording. Sync, the
   embedded GPS and telemetry, and the chapters are exactly as before. **Undo** returns to the
   recording's picture; the copy stays on disk.
4. A missing copy shows the recording again until **Stabilise Again**.

Tests: `StabilisationUITests.testEachWayToSteadySaysWhatItNeeds` (CI has no Gyroflow). Model:
`GyroflowTests`; with Gyroflow installed, `gyroflowKeepsTheTimingOfTheRecording`
(`ONBOARD_GYROFLOW_CLIP`, local).

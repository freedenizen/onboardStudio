# J26 Steady a shaky helmet video
*Source: #262 (from #140) — helmet-mounted footage shakes considerably even with HyperSmooth, and
GoPro Player's stabilised export drops the GPS and timing that sync depends on.*

1. Select the video in the sidebar. In the inspector, **Stabilisation ▸ Steady ▸ From camera motion
   data**. The preview steadies at once; the file is not changed, so sync and embedded telemetry
   stay as they were.
2. **Smoothing** from *Follow* to *Float* sets how much of the movement stays; **Zoom** hides the
   edges the moves bring into view.
3. A video with no motion record keeps **Steady** disabled and says why; one recorded with
   HyperSmooth says it cannot yet be steadied further here and points to Gyroflow.
4. Export as usual: the steadied picture is what is written.

Tests: `StabilisationUITests.testAVideoWithoutMotionDataSaysSo` (the fixture video has no motion
record). Model: `StabilisationTests`, `OrientationTests`, `StabilisationSettingsTests`; on real
footage, `StabilisationSampleTests` (local, `ONBOARD_SAMPLES_DIR`).

# Test fixtures

All fixtures are small and synthetic; none are copied from third-party files.

| File | Format | Notes |
|---|---|---|
| `test-3s.mp4` | H.264/AAC video | 3 s, 640×360, 30 fps `testsrc2` + 440 Hz sine. Regenerate with `Scripts/make-fixture-video.sh`. |
| `racerender-basic.csv` | RaceRender CSV | `# RaceRender Data` header, two `# Lap N:` tags, `hh:mm:ss.nn` times, MPH speed, `*OBD` column with `OBD_Update`, one row with a missing field. |
| `racechrono-v3.csv` | RaceChrono Pro CSV v3 | Metadata preamble, units + source rows, duplicate `speed` columns from gps/calc/obd, one duplicated timestamp row, blank OBD cells, lap_number 8→9→10. |
| `track.gpx` | GPX 1.1 | Six timed track points with elevation and Garmin `hr` extension, one untimed point, fractional-second timestamps. |
| `slice.overlayproj/` | OverlayGen project | Video on the left half, speedometer, track map, g-force, lap timer and RPM readout on the right, fed by `racerender-basic.csv` with a 1 s sync offset. |
| `Goldens/*.png` | golden images | Reference renders for `RenderKitTests`; regenerate with `UPDATE_GOLDENS=1 swift test --filter Golden`. |
| `test-1s.mts` | MPEG transport stream | 1 s, 320×180, 25 fps, no audio. AVFoundation cannot open it; exercises the ffmpeg remux fallback. |
| `stereo-1s.mp4` | H.264/AAC | 1 s, 160×90; 440 Hz tone on the left channel only, 880 Hz on the right. Used to verify volume/balance/channel processing. |
| `arrow.png` | PNG | 32×32 red up-arrow on transparency for image-object tests. |
| `test-rot180.mp4` | H.264 | 1 s, 320×180 test pattern whose display matrix says rotate 180°, as an upside-down mounted camera records. Guards that the compositor honours the track's preferred transform. |

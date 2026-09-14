# Test fixtures

All fixtures are small and synthetic; none are copied from third-party files.

| File | Format | Notes |
|---|---|---|
| `test-3s.mp4` | H.264/AAC video | 3 s, 640×360, 30 fps `testsrc2` + 440 Hz sine. Regenerate with `Scripts/make-fixture-video.sh`. |
| `racerender-basic.csv` | RaceRender CSV | `# RaceRender Data` header, two `# Lap N:` tags, `hh:mm:ss.nn` times, MPH speed, `*OBD` column with `OBD_Update`, one row with a missing field. |
| `racechrono-v3.csv` | RaceChrono Pro CSV v3 | Metadata preamble, units + source rows, duplicate `speed` columns from gps/calc/obd, one duplicated timestamp row, blank OBD cells, lap_number 8→9→10. |
| `track.gpx` | GPX 1.1 | Six timed track points with elevation and Garmin `hr` extension, one untimed point, fractional-second timestamps. |

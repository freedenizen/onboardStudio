# QA script — M10 GoPro telemetry, FIT and timestamp auto-sync

| # | Step | Expected |
|---|---|---|
| 1 | Add a GoPro clip (HERO11 or later) as the video | The video inspector shows **Use Embedded GPS** with a note about GPS / accelerometer / gyro |
| 2 | Click **Use Embedded GPS** | A data input "<video> GPS" appears with the same sync as the video; the track map, speed and G objects work from it without any wizard |
| 3 | Select the GPS data input | Format "GoPro GPMF", ~10 GPS rows per second, `aux:accel_*` and `aux:gyro_*` channels in the list |
| 4 | Add a RaceChrono CSV recorded alongside | The status line reports "Synced … from timestamps using the GoPro GPS clock"; lap timer and the GoPro map agree with the video within a second |
| 5 | Move the video's start position by 10 s, then **Auto-Sync from Timestamps** on the data input | The data start position moves by 10 s too |
| 6 | Add a data file with no clock (RaceRender CSV with relative time) | No auto-sync; the button is hidden; the wizard still works |
| 7 | Use a non-GoPro video with a RaceChrono file | Auto-sync uses the file creation time (status line says so) |
| 8 | Add a Garmin `.fit` activity | Position, speed, altitude, distance and heart rate channels; laps from the file |
| 9 | `overlaygen probe GX010037.MP4` | Channel table with latitude/longitude/speed and the accelerometer axes |

## Results (0.8.0, HERO13 clip + RaceChrono v3 export)

- **Use Embedded GPS** on the GoPro input adds "GoPro GPS" (GoPro GPMF, 15 channels, 0.02–768.78 s, sync identical to the video); `overlaygen probe` on the clip lists position, speed, DOP/fix and the six accelerometer/gyro axes at 10 Hz / 200 Hz, parsed in about 2 s.
- **Auto-Sync from Timestamps** on the RaceChrono input reports the GoPro GPS clock and sets the start position to 1 787 528 146.8 s. Cross-checking GoPro GPS against RaceChrono GPS by epoch gives a median position disagreement of 6 m at that alignment; the creation-time-based value used since M4 (1 787 528 178.6) was 32 s off and puts the two logs hundreds of metres apart.
- GPS rows with DOP above 10 (the camera reports 99.99 while searching) are dropped; before that filter the latitude range spanned five degrees.
- The open panel cannot be scripted, so adding a FIT file through the UI was not exercised; the importer and its detection are covered by the in-test FIT encoder.

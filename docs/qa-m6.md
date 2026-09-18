# QA script — M6 data processing

Open a project with a video and a real data file (RaceChrono CSV works best).

| # | Step | Expected |
|---|---|---|
| 1 | Select the data input | Inspector shows **Channels** (name, samples, unit, role and unit pickers), **Processing**, **Calculated Fields**, **Laps** |
| 2 | Change a channel's role picker (e.g. an `aux:` channel to `throttle`) | Objects bound to that role pick it up after a moment; undo reverts |
| 3 | Set a unit override on a bare speed column (e.g. `km/h`) | Speedometer readout rescales |
| 4 | Set Resample 25 Hz and Smoothing 0.5 s | Needles move more smoothly during playback; readouts unchanged in magnitude |
| 5 | Add a calculated field `kph = speed * 3.6`, then add a Text Data object with channel `aux:kph` | Readout shows km/h; an invalid expression turns red and is ignored |
| 6 | Scrub the preview to the moment the car crosses start/finish, enable **Detect laps from a start/finish line**, click **Use Current Preview Position** | Laps list refreshes with lap times; compare with your logger app's laps |
| 7 | Set **Ignore first crossings** to 1 | Lap 1 now starts at the second crossing |
| 8 | Widen/narrow **Line half-width** and change **Heading** | Laps appear/disappear accordingly; heading blank (−1) accepts both directions |
| 9 | Import a TCX, NMEA, VBO or generic CSV via **Add Data** | Channels and laps appear as documented in `docs/formats.md` |
| 10 | ⌘S, reopen | All mapping, processing, calculated fields and lap settings restored |

## Results (0.4.0, real Sonoma session + GoPro HERO13)

Scripted run against a RaceChrono Pro v3 export (131k rows, 42 channels) and the matching GoPro clip:

- Data inspector loads with the channel list collapsed (`Channels (42)`), so Processing and Laps are reachable without scrolling.
- Enabling lap detection seeds the line from the preview position; typing `38.16155 / -122.45467 / 308° / 30 m` reproduces RaceChrono's laps (out-lap, 2:04.15, 1:56.89, 1:59.14, 1:56.88, …). Ignore-first 1 folds the first crossing into lap 0.
- Latitude/longitude fields show six decimals (three was ~111 m of rounding).
- Rapid successive edits (bad longitude immediately corrected) end in the correct lap list: compiles are now serialised and stale results dropped.
- Six consecutive data edits kept the GoPro preview upright; the composition track no longer carries the source rotation, so only the compositor applies it.

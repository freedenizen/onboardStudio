# Supported data formats

Importers live in `Sources/Importers`. Each implements `TelemetryImporter`, reports a confidence
for a file from a cheap sniff of its first 8 KB, and produces a `RawTable` whose columns carry
suggested channel roles. `SessionBuilder` turns that into a `TelemetrySession` (canonical units,
derived speed/heading/distance from GPS when absent, laps).

Run `onboard probe <file>` to see how a file is interpreted.

## RaceRender CSV (`racerender-csv`)

RaceRender's native format, also written by TrackAddict and several loggers.

- Optional first line `# RaceRender Data` (detection is *certain* when present). Other `#` lines
  are comments.
- `# Lap N: hh:mm:ss.nn` tags mark the **end** of lap N. Lap 0 starts at the beginning of the file.
- `Time` column required, in seconds or `hh:mm:ss.nn`. Rows must be chronological; duplicate or
  backwards times are dropped.
- Recognised columns: `Latitude`, `Longitude`, `Altitude`, `GPS_Update`, `GPS_Delay`, `X`
  (longitudinal G), `Y` (lateral G), `MPH` / `KPH` / `Speed` (m/s), `Heading`, `Lap`, `RPM`,
  `Gear` (0 = neutral, -1 = reverse, -99 = park), `Accuracy`, `Throttle`, `Brake`, `OBD_Update`.
- A ` *OBD` suffix marks OBD-sourced columns (role `obd:<name>`); any other column becomes
  `aux:<name>`.
- Comma, semicolon or tab delimited; UTF-8 BOM and European decimal commas tolerated.

## RaceChrono / RaceChrono Pro CSV (`racechrono-csv`)

CSV v3 as exported by RaceChrono Pro 7.3+ (v2 files are read on a best-effort basis).

```
This file is created using RaceChrono Pro v9.1.3 ( http://racechrono.com/ ).
Format,3
Session title,"…"
Session type,Lap timing
Track name,"…"
Driver name,…
Created,31/12/2025,02:54
Note,…

timestamp,fragment_id,lap_number,elapsed_time,distance_traveled,altitude,bearing,…,speed,…,rpm,…
unix time,,,s,m,m,deg,…,m/s,…,rpm,…
,,,,,100: gps,100: gps,100: gps,…,calc,…,200: obd,…
1767150797.44,0,8,1149.08,17834.748,1.1,322.56,…
```

- Preamble `Key,Value` lines become session metadata (title, track, driver, created date, note).
- The header row starts with `timestamp`; a units row and a data-source row follow.
- Times are unix seconds and are kept as-is. Duplicate rows (RaceChrono emits them) are dropped.
- Column names repeat across sources (`speed` from GPS, calc and the vehicle). The first
  occurrence keeps the role; later ones become `aux:<name> (<source>)`, except vehicle columns,
  which become `canbus:<name>` for a `200: canbus` source and `obd:<name>` for `200: obd`. The
  two are kept apart because a CAN log carries far more than OBD-II exposes. Projects saved
  before CAN had its own role name those channels `obd:`; that name still resolves.
- `lap_number` transitions define laps. The first run is marked partial when it does not start
  at lap 0, and the last run is always partial.
- Blank cells (common for vehicle channels) are skipped, so channels may have fewer samples than rows.

## GPX (`gpx`)

GPX 1.0/1.1 tracks.

- `trkpt` elements give latitude/longitude; `ele` and `time` are optional. Points without a
  timestamp are dropped; times are seconds relative to the first timestamped point.
- Numeric leaves inside `<extensions>` become channels. `speed` → speed, `course`/`heading`/
  `bearing` → heading, `hr` → heart rate, `cad` → cadence, `power`, `atemp`/`temp` → temperature.
- Speed, heading and cumulative distance are derived from position when the file has none.
- When the session has laps and distance, two more channels are derived for every object to use:
  `lapDelta` (seconds behind (+) or ahead of (−) the session's best lap at the same distance into
  the lap) and `speedDelta` (speed minus the best lap's speed at that spot, shown in the object's
  speed unit). The best lap is the quickest *full* lap: a lap shorter than 90 % of the longest
  complete lap (an out, in or pit-lane fragment) is treated as partial everywhere.
- The first `<trk><name>` is used as the session title.

## TCX (`tcx`)

Garmin Training Center XML. Trackpoints give position, altitude, distance, heart rate, cadence
and the `Speed`/`Watts` extensions; each `<Lap StartTime>` becomes a lap boundary. Times are
relative to the first trackpoint.

## NMEA 0183 (`nmea`)

Plain sentence logs (`$GPRMC`, `$GPGGA`, `$GPGLL`, also `$GN…`/`$GL…`). Fixes are merged by
their UTC time; RMC supplies speed (knots → m/s), course and the date; GGA supplies altitude, fix
quality, satellites and HDOP; void (`V`) sentences are skipped; midnight rollover is handled.

## Racelogic VBO (`vbo`)

`[header]` (or `[column names]`) lists the channels; `[data]` rows are space separated. Time is
`hhmmss.ss`; `lat`/`long` are in minutes with west positive (VBO convention) and are converted to
signed degrees. Known channels: sats, heading, height, lapnumber, rpm, throttle, brake, gear,
distance, latacc/longacc.

A file states its units in two places, and both are easy to get wrong:

- **`[channel units]` is right-aligned with `[header]`.** It carries one line per *extra* channel
  and none for the leading GPS ones, so a 35-channel VBVDHD2 log lists 25 units and they belong to
  the last 25. Aligning from the top gives every CAN channel its neighbour's unit — bar for a
  temperature, rpm for a pressure — which is worse than no unit at all, because it looks right.
  Verified against two unrelated real files (35 channels/25 units and 15/4). The section may also
  be present and empty.
- **The `[header]` name carries the unit where `[column names]` does not**: `velocity kmh`,
  `velocity knots`, `vertical velocity m/s`, `yaw rate deg/s` all collapse to one word in
  `[column names]`. `velocity` alone still means km/h, the VBO default, but reading a knots file
  as km/h is wrong by a factor of 1.852 and silent.

`(null)` is how the format writes "no unit": it means the file declares nothing, so the importer's
own reading of the name stands. A declared unit otherwise beats the name-based guess — a Video
VBOX `Brake` channel is often a pressure in psi, not the percentage the name suggests.

Sections the importer does not read yet: `[laptiming]` (start/split/finish gates, each two
lat/long pairs and a label after a `¬`; #71), `[avi]` (the video file this log accompanies) and
`[comments]` (device type, serial, firmware, log rate).

Real logger files are not committed — provenance is third-party. `Tests/Fixtures/vbox-canbus.vbo`
is synthetic and reproduces the shapes above; the tests in `VBOSampleTests` run against real files
when `ONBOARD_SAMPLES_DIR` points at a folder containing `vbo/`, and skip otherwise.

## RaceChrono archive (`racechrono-rcz`)

A zip. `session.json` carries the track name, RaceChrono's own track id, the best and optimal lap
times, and a lap list with each lap's `isInvalid` flag; `sessionfragment.json` says which device
produced which streams (type 1 GPS, 2 accelerometer, 3 gyro, 12 CAN bus).

Channel members are named `channel_<deviceType>_<deviceId>_<canId>_<channelId>_<kind>`.

- **GPS and IMU devices** write one file per channel, all with the same record count. Channel 1 is
  that device's time axis as `int64` milliseconds; channel 2 is distance travelled in millimetres
  (also `int64` — reading it as `int32` truncates it and makes every lap delta nonsense); channel
  3 is position, an `int32` pair over **6,000,000** — degrees × 60 × 10⁵, minutes rather than the
  1e7 most formats use. Everything else is an `int32` scalar over a fixed power of ten: speed,
  altitude, heading, accuracy and battery over 1000, accelerometer over 10 000, gyro over 1000,
  satellites and fix type unscaled.
- **CAN channels** are logged at their own rates, so each has three members: `…_1_1` its
  timestamps, `…_2_1` the distance at each sample, and `channel2_…_3` the values as `float64`.
  The distance member only repeats the GPS device's and is ignored.

The archive carries **no names** for CAN channels, so one imports as `canbus:<id>` and the user
says what it is in the attribute table. Every device samples on its own clock, so the table's time
axis is the union of all of them and each channel keeps the times it was really recorded at.

Scales were derived by importing one session both ways and matching the archive against the CSV
export; `RCZReferenceTests` keeps that comparison as a test.

## Generic CSV (`generic-csv`)

For apps without a dedicated importer. The header is the first row with at least three fields and a
time-like column; a units row after it is skipped. Time may be unix seconds, relative seconds or
`hh:mm:ss.nn`. Column names are matched against app profiles when a signature is present (Harry's
LapTimer, AIM, MoTeC i2) and otherwise fuzzily (`lat`, `lon`, `speed`/`mph`/`kph`, `heading`/
`course`, `alt`, `lap`, `rpm`, `gear`, `throttle`, `brake`, `lateral g`, `long g`, `dist`), with a
trailing `(unit)` respected. Everything unmatched becomes an aux channel. Fix mistakes with the
channel mapping in the inspector (`roleOverrides` / `unitOverrides` in the project file).

## Processing options

Every data input can be post-processed (`docs/project-format.md`, `DataInputSettings`):

- **Channel mapping**: `roleOverrides` (column → role) and `unitOverrides` (column → unit text).
- **Resampling** to a fixed rate and **smoothing** (centred moving average; headings are averaged
  as unit vectors; step channels such as gear and lap are left alone).
- **Calculated fields**: `name = expression`, e.g. `kph = speed * 3.6`,
  `hard_brake = if(brake > 50, 1, 0)`, `delta = [aux:Oil temp] - obd:Coolant`. Operators
  `+ - * / %`, comparisons, `&& || !`, functions `abs sqrt floor ceil round min max pow clamp if`.
- **Lap detection** from a start/finish line (latitude, longitude, optional heading, half-width,
  heading tolerance, warm-up crossings to ignore) with sub-sample crossing times. On a real
  RaceChrono session this reproduces the app's own lap times to within about 10 ms.

## Planned

FIT (Garmin SDK), RaceChrono `.rcz` archives, and GoPro GPMF metadata tracks. See
`docs/architecture.md`.

## GoPro GPMF (embedded telemetry)

GoPro recordings carry a `gpmd` metadata track (GPMF) with GPS, accelerometer, gyroscope and
camera sensor streams. AVFoundation does not expose it, so `GPMFKit` reads the MP4 sample tables
directly and parses the KLV payloads. HERO11 and later write `GPS9` (position, altitude, 2D/3D
speed, UTC days and seconds, DOP, fix) at 10 Hz; samples without a fix keep their time but carry no
position. The accelerometer and gyro (`ACCL`, `GYRO`, 200 Hz) become `aux:accel_x/y/z` in G and
`aux:gyro_x/y/z` in rad/s, axes re-ordered by the stream's `ORIN` string.

Times are seconds from the start of the video, so a data input made from the video itself needs
no sync (the app's **Use Embedded GPS** button creates one with the video's sync). The first GPS
fix gives the recording's wall-clock start (`createdAt`), which other loggers can be synced to.
CLI: `onboard probe GX010037.MP4`; importer id `gopro-gpmf`.

## Garmin FIT

`record` messages supply position (semicircles → degrees), altitude, speed (enhanced when
present), distance, heart rate, cadence, power and temperature; `lap` messages become lap markers.
Both byte orders, compressed-timestamp headers and developer fields (skipped) are handled. Times
are seconds from the first record and `createdAt` is the absolute start (FIT epoch 1989-12-31).
Importer id `fit`.

## Timestamp auto-sync

When a data file has a clock (epoch timestamps such as RaceChrono's, or a recorded start date such
as GPX, TCX, FIT, VBO and NMEA files) and the video has one too (the GoPro GPS clock when the file
has GPMF, otherwise the container's creation time), the app aligns them automatically when the
data file is added, and **Auto-Sync from Timestamps** in the data inspector re-applies it. The
video's own trim, offset and speed are honoured. Cameras whose clocks drift can still be nudged
with the sync wizard afterwards.

The GPS clock is preferred because container creation times are unreliable: on a HERO13 the
`creation_time` of a clip was 32 s later than the GPS clock at its first frame, and only the GPS
clock lines the clip up with a RaceChrono log recorded in the same car (median position
disagreement about 6 m, versus hundreds of metres with the creation time).

## DJI SRT (`dji-srt`)

DJI drones, the Osmo Action and Avata write a `.SRT` subtitle file next to each video with one cue
per frame. Both layouts are read: `[latitude: …] [longitude: …] [rel_alt: … abs_alt: …]` blocks
(with `iso`, `shutter`, `fnum`) and the one-line `GPS (lon, lat, alt), D 12.3m, H 20.0m, H.S
5.2m/s` form. Times are the cue times (seconds from the first frame); the date stamped in the
first cue anchors the log to the clock, so timestamp auto-sync works and, because the log starts
with the video, the video's own recording start is taken from it ("DJI SRT clock"). Channels:
latitude, longitude, altitude, speed (horizontal, or derived from position), and `Height`,
`Home distance`, `ISO`, `Shutter`, `Aperture` as aux channels.

## Sidecar telemetry

When a video is added, Onboard Studio looks for a telemetry file with the same name next to it
(`.srt`, `.fit`, `.gpx`, `.csv`, either case) and offers **Use Sidecar Data** in the video
input's inspector; the new data input shares the video's sync since such logs start with the
recording. Garmin VIRB cameras write a FIT file this way; DJI cameras an SRT. Sony cameras write a
`C0001M01.XML` sidecar whose `CreationDate` is used as the video's clock for timestamp auto-sync.

## Motion auto-sync

**Auto-Sync by Motion** (data input inspector) and `onboard sync --video a.mp4 --data b.csv`
need no clocks at all. The video's audio loudness (engine and wind noise, sampled at 10 Hz over
the whole clip; it decodes in seconds) is correlated against the log's speed, or its g-force
magnitude when there is no speed channel. When the clip is silent or the match is weak, the change
between video frames (the fraction of a 64-pixel-wide thumbnail that moved, over the first three
minutes after the video's start position) is tried as well and the better match wins. The best
correlation gives the data start position; the status line reports which signals matched, the
correlation and whether the match stands out clearly ("good match") or should be checked in the
sync wizard. On the HERO13 + RaceChrono reference session the audio match lands within 2 s of the
GPS-verified offset with a correlation of 0.9, whereas picture motion alone is unreliable on
dash-cam footage (people walking past a parked car change as many pixels as driving does), which is
why it is only the fallback. `onboard sync --dump signals.csv` writes the signals for inspection.

# Supported data formats

Importers live in `Sources/Importers`. Each implements `TelemetryImporter`, reports a confidence
for a file from a cheap sniff of its first 8 KB, and produces a `RawTable` whose columns carry
suggested channel roles. `SessionBuilder` turns that into a `TelemetrySession` (canonical units,
derived speed/heading/distance from GPS when absent, laps).

Run `overlaygen probe <file>` to see how a file is interpreted.

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
- Column names repeat across sources (`speed` from GPS, calc and OBD). The first occurrence keeps
  the role; later ones become `aux:<name> (<source>)`, except OBD columns which become
  `obd:<name>`.
- `lap_number` transitions define laps. The first run is marked partial when it does not start
  at lap 0, and the last run is always partial.
- Blank cells (common for OBD channels) are skipped, so channels may have fewer samples than rows.

## GPX (`gpx`)

GPX 1.0/1.1 tracks.

- `trkpt` elements give latitude/longitude; `ele` and `time` are optional. Points without a
  timestamp are dropped; times are seconds relative to the first timestamped point.
- Numeric leaves inside `<extensions>` become channels. `speed` → speed, `course`/`heading`/
  `bearing` → heading, `hr` → heart rate, `cad` → cadence, `power`, `atemp`/`temp` → temperature.
- Speed, heading and cumulative distance are derived from position when the file has none.
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
signed degrees; `velocity` is km/h. Known channels: sats, heading, height, lapnumber, rpm,
throttle, brake, gear, distance, latacc/longacc.

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

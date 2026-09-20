# Tracks and sectors

Design for circuit identification, the start/finish line, sector timing and what the track map
draws. Written from measurements against a real RaceChrono session at Sonoma and from a licensing
survey, both recorded below so the reasoning can be re-checked rather than taken on trust.

Issues: #64 sectors, #65 circuit identification, #66 start/finish editing, #67 map display,
#68 `.rcz` import, #71 VBO `[laptiming]`.

## The constraint that shapes everything

**No open data source can supply sector definitions.** Checked:

| Source | Licence | Gives |
| --- | --- | --- |
| Wikidata | CC0 | Circuit name, one coordinate, country. No geometry. |
| OpenStreetMap | ODbL | `highway=raceway` geometry; *sometimes* a `raceway=start-finish` node. **No sector tag exists** — only an unfinished relation proposal. |
| `lovely-track-data` (via track-atlas) | CC **BY-NC-SA** | Real sector geometry — but NonCommercial, so unusable in a public MIT repo regardless of whether OverlayGen is ever sold. |
| RaceChrono / VBOX / TrackAddict / AiM | Closed | No published API or licensing route found for any of them. |

Nor does the logger have them. A `.rcz` archive was unpacked: `session.json` carries `trackName`,
`trackId`, `bestLaptime`, `optimalLaptime` and per-lap timestamps with an `isInvalid` flag — and
**no sector or start/finish geometry**, even though RaceChrono plainly computes an optimal lap
internally.

So sectors are derived or drawn. There is nothing to fetch.

## Circuit identification: Wikidata, not OpenStreetMap

**Wikidata**, queried for `wdt:P31/wdt:P279* wd:Q2338524` (motorsport racing track), returns
**1,330 circuits in 133 KB of CSV** with name, coordinate and country, under **CC0** — no
attribution obligation, no share-alike, no dual-licensing. Matching the reference session's
centroid against it:

```
session centroid 38.16237, -122.45739
   0.27 km  Sonoma Raceway
  91.52 km  Altamont Raceway Park
```

A 340× margin to the runner-up. Nearest-centroid identification is unambiguous and the list is
small enough to bundle without thought.

**OpenStreetMap geometry was evaluated and rejected.** Sonoma Raceway is **21 fragmented ways**,
mostly unnamed, only one closed, mixing the dragstrip, pit road and alternate layouts
("Sonoma Raceway 2020", "PWC lower hairpin"). Assembling an outline would mean stitching fragments
and guessing which configuration was driven. The public Overpass instance also timed out repeatedly
during evaluation, and two mirrors disagreed on counts. It would cost the full ODbL compliance split
— an ODbL-licensed data file shipped separately from the MIT code, attribution wherever it appears,
and an unresolved question about whether caching tips a client into holding a Derivative Database —
for a worse result than the driver's own laps already give.

**The file often already knows.** `SessionInfo.trackName` is parsed from the RaceChrono CSV preamble
(`Track name,"Sonoma"`) and from GPX, but today it is used only by `overlaygen probe` — the app
discards it. Use it directly, and let the coordinate match confirm or correct it.

## The outline comes from the driver's own laps

Already true, and measured to be good. On the reference session: 108k points over nine laps, but
lap-to-lap spread is **0.9 m median** on a ~4 km lap (90th percentile 2.2 m), and the session
bounding box is **96% circuit**. At overlay size the nine-lap overdraw is under a pixel and the
framing is already right.

**The outline does not need fixing.** #67 is display options, not repair.

## Sectors

A sector time is the difference between two distances into the lap. That is already implemented:
`Sources/TelemetryKit/LapComparison.swift` has `distanceIntoLap(at:lap:distance:)` and
`time(atDistance:in:between:and:)`, which drive the existing lap and speed deltas. `LapDetector`'s
`FinishLine` already documents itself as working for "a start/finish (or sector) line"; what is
missing is storing more than one line per input.

Four modes, user-selectable, because no single one suits every venue:

| Mode | Behaviour | Best for |
| --- | --- | --- |
| **Equal distance** (default) | Split the reference lap's distance into N parts, 3 by convention | Anything, with zero setup. Sector times only need to be *consistent* lap-to-lap to answer "where did I lose time" |
| **Corner-aware** | Boundaries on the straights between corner groups detected from curvature | A sector never splits a corner, so the times are more diagnostic |
| **Manual** | Lines the driver places | Matching an official timing split, or a venue with an unusual layout |
| **From a track definition** | Whatever was saved or shared | The second visit to a circuit, and the community route |

Equal-distance is the default because it is the only one guaranteed to work — on an autocross, a
point-to-point stage, or a circuit nobody has mapped.

## Start/finish

More exists than it appears. `DataInputInspector` already has a "Detect laps from a start/finish
line" toggle, a **"Use Current Preview Position as Start/Finish"** button, and fields for latitude,
longitude, heading, half-width, heading tolerance and warm-up crossings to ignore.

What #66 adds:

- **Place and rotate it on the track map**, rather than typing coordinates. The map already
  projects the trace, so the geometry is there.
- **A first guess from the data** — the trace shows where laps repeat, so a session opens with
  something workable and the driver corrects rather than authors.
- **Remember it per circuit**, which is what identification unlocks: set once per venue, not once
  per session.
- **Export and import track definitions** — line, sectors and circuit name in one file. Since no
  licence can give us sector data, a definition drivers pass around is the only route to a shared
  library, and being contributor-owned it carries no licensing problem at all.

## What the formats carry

Surveyed because if a logger already records the start/finish line, reading it beats asking the
driver to redraw it.

| Format | Session / track metadata | Laps | Start/finish or sector **line** geometry |
| --- | --- | --- | --- |
| **Racelogic VBO** | `[comments]` free text, device and firmware info | Yes | **Yes — the only one.** A `[laptiming]` section holds `Start` / `Split` / `Finish` entries, each a pair of lat/long endpoints defining a gate across the track, plus a label |
| RaceChrono `.rcz` | `trackName`, `trackId`, `optimalLaptime`, `bestLaptime` | Yes, with an `isInvalid` flag per lap | No |
| RaceChrono CSV | `Track name`, session title, created date | Via `lap_number` | No |
| Garmin FIT | `sport` / `sub_sport`, a bounding box; **no free-text venue name** | `lap` messages with start/end *positions* and a `lap_trigger` enum | No — single points only, never a gate |
| TCX | `Course/Name` (a route name, not a venue) | Yes, native `Lap` and `CourseLap` | No — begin/end points per lap only |
| GPX | `metadata/name`, `trk/name` | **No native concept**; `trkseg` is sometimes misused for it | No |
| MoTeC `.ld` / `.ldx` | venue, vehicle, driver, event, comment (reverse-engineered) | `.ldx` holds lap time markers | Not found — markers appear to be times, not coordinates |
| AiM `.xrk` | Closed; reachable only through AiM's own DLL | Yes, from a beacon or derived from GPS | Not found |
| TrackAddict CSV | A separate free-text notes file | Needs GPS; the line is set downstream in RaceRender | No |
| Harry's LapTimer CSV | A lap-summary file with **sector split times** | Yes | No — times, not geometry |
| NMEA | None | None | None |

Three things follow.

**VBO `[laptiming]` is the only real interchange for circuit geometry.** Racelogic's Circuit Tools
and Harry's LapTimer both read and write it for exactly this purpose, which makes it the closest
thing to a de facto standard. Worth parsing (#69) — `VBOImporter` currently reads `[header]`,
`[column names]` and `[data]` and silently ignores every other section.

**But it will not help a RaceChrono user.** RaceChrono's own manual states the start/finish line is
*not* exported when writing VBO, so even that route leaves the reference session without a line.
This is why deriving a first guess from the trace (#66) matters more than any import path.

**Caveat on the VBO detail.** Racelogic's specification page could not be fetched directly — it
returns 403 — so the exact field order and sign convention within `[laptiming]` come from cached
secondary text, not a read of the spec. Validate against a real VBOX file before trusting a parser.
There is no real VBO in `Tests/Fixtures`; `session.vbo` is synthetic and has no `[laptiming]`
section. The longitude convention itself is confirmed and already handled: VBO stores minutes with
**west positive**, and `VBOImporter.mapping` already negates it.

## Deliberately not doing

- **Bundling OpenStreetMap geometry** — see above.
- **Querying Overpass at runtime** — it is documented as a low-volume manual-use service, and a
  widely installed desktop app polling it is exactly the pattern its operators ask people not to
  build.
- **Shipping a circuit database with sectors** — none exists under a compatible licence.

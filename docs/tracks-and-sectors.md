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
| `lovely-track-data` (via track-atlas) | CC **BY-NC-SA** | Real sector geometry — but NonCommercial, so unusable in a public MIT repo regardless of whether Onboard Studio is ever sold. |
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

### What was built

`Sources/TelemetryKit/CircuitCatalog.swift`, with the list at
`Sources/TelemetryKit/Resources/circuits.csv` — **1,290 circuits in 67 KB**, refreshed by
`Scripts/update-circuits.sh` (which holds the SPARQL query, so the file has provenance rather
than being a mystery blob). Nothing queries the network at run time; the list ships with the app.

Three things the data forced:

- **Ask for labels in one language and ~130 circuits arrive as `Q12345`.** The query falls back
  through nineteen languages, which leaves twelve with no usable name at all; those are dropped.
- **Names are not identities.** Wikidata lists *three* Brazilian circuits called "Autódromo
  Internacional Ayrton Senna", and nine other names are duplicated. The Wikidata id is what a
  saved reference stores, and the refresh script sorts by name *then id* or the file is not
  reproducible between runs.
- **Some venues share a coordinate exactly.** The Isle of Man's Clypse, Four Inch and Highroads
  courses sit on one point. A nearest-point match between those is a coin toss, so `Match` carries
  the runner-up distance and an `isConfident` flag: confident when the file's own track name
  agrees, or when the runner-up is at least ten times further away. Sonoma passes on both counts;
  the Isle of Man passes on neither, and the app should ask rather than assert.

The file's track name only ever *confirms* a coordinate — except that a named candidate inside the
radius beats a nearer unnamed one, which is how a venue listed once per layout resolves to the
layout the driver says they drove.

### Remembering a circuit

`TrackDefinition` (ProjectModel) is what was worked out about a venue once: its start/finish line,
its sector settings, a name and a coordinate. `TrackLibrary` keeps them in
`~/Library/Application Support/OnboardStudio/Tracks`, **one `.onboardtrack` JSON file each** —
deliberately separate files rather than a database, because a definition is meant to be handed to
another driver and a file you can attach to a message is the whole point.

A definition is filed under its Wikidata id where there is one, and under a slug of its name where
there is not (a club circuit, a car park, an airfield). The id is preferred because circuits get
renamed by sponsors — Laguna Seca twice — and a definition should outlive that.

**When it is applied, and when it is emphatically not.** `EditorModel.applyPendingTrackDefinition`
runs after a compile, and only for a data file the user has just *added*: it names the circuit and,
if that circuit has a saved definition, fills in the start/finish line and sectors. Opening a saved
project does none of this and never will. A definition saved last week must not change how a
project made last month renders — a project-wide rule, and the reason
`DataInputSettings.circuitID` is left as it was found rather than recomputed on open.

The inspector shows the match with its distance and its runner-up, says so when the match is not
confident, and offers *Not This Circuit* and a search box. Nothing is insisted on.

`onboard probe` prints the match:

```
Track:     Sonoma
Circuit:   Sonoma Raceway (US) [Q112563]  (0.27 km from the session centre, next 92 km, name agrees)
```

**OpenStreetMap geometry was evaluated and rejected.** Sonoma Raceway is **21 fragmented ways**,
mostly unnamed, only one closed, mixing the dragstrip, pit road and alternate layouts
("Sonoma Raceway 2020", "PWC lower hairpin"). Assembling an outline would mean stitching fragments
and guessing which configuration was driven. The public Overpass instance also timed out repeatedly
during evaluation, and two mirrors disagreed on counts. It would cost the full ODbL compliance split
— an ODbL-licensed data file shipped separately from the MIT code, attribution wherever it appears,
and an unresolved question about whether caching tips a client into holding a Derivative Database —
for a worse result than the driver's own laps already give.

**The file often already knows.** `SessionInfo.trackName` is parsed from the RaceChrono CSV preamble
(`Track name,"Sonoma"`) and from GPX, but today it is used only by `onboard probe` — the app
discards it. Use it directly, and let the coordinate match confirm or correct it.

## The outline comes from the driver's own laps

Already true, and measured to be good. On the reference session: 108k points over nine laps, but
lap-to-lap spread is **0.9 m median** on a ~4 km lap (90th percentile 2.2 m), and the session
bounding box is **96% circuit**. At overlay size the nine-lap overdraw is under a pixel and the
framing is already right.

**The outline does not need fixing.** #67 is display options, not repair.

### What was built

Four options on `TrackMapParams`, each independently switchable and **all off by default**, so a
project saved before them draws the outline it always drew:

- **`colorBySector`** paints each sector of the trace its own colour. The outline is stroked once
  per run of same-sector points rather than once per point, and consecutive runs overlap by a
  point so the colours meet instead of leaving a gap.
- **`showSectorTicks`** draws a line across the track at each boundary, square to the direction of
  travel there, numbered. There is no `S1` tick: the first sector begins at the start/finish line,
  which is not a sector boundary. The number goes on the side of the tick facing the middle of the
  map — the map is framed to the trace, so a label on the outside falls off the object, while the
  middle of a circuit is the one place reliably empty.
- **`trace = .referenceLap`** draws only the lap sectors and deltas are measured against, and
  frames the map to that lap. It is much crisper, and it leaves the pit lane and the paddock out
  for free, because the reference lap never went there.
- **`trace = .trackOnly`** is the default for a new map, and is #95. See below.
- **`showCornerNumbers`** numbers the corners from the reference lap's curvature.

### Finding the track in the trace (#95)

A session is not only laps. The car leaves the pits, comes back in, is driven to the paddock and
parked, and every metre of it is in the file. On a map that is worse than clutter, because the map
is framed to fit the whole trace: **one trip across the paddock shrinks the circuit into a corner
of the object.** On the reference session the paddock run makes the drawn map about half the size
the circuit alone would be.

`.referenceLap` already avoided this, but it draws one lap and needs laps to have been detected.
`TelemetryKit/TrackExtent.swift` answers the question directly and needs no laps at all: **a
circuit is what gets driven over again and again, and a pit lane is not.** Each sample is asked how
many separate times the car came within 12 m of it, and the ones with far fewer visits than the
busy parts of the trace are not the track.

Four decisions in it are worth not re-deriving:

- **Visits are counted as unbroken runs of samples, not by a time gap.** A time threshold has to
  sit below the lap time and above the time spent crossing a 12 m circle, and no single value does
  both for a Nordschleife lap and a kart lap. Pick 20 s and a 20 s kart lap folds every lap into
  one visit, the answer collapses and nothing is excluded. After thinning, index distance *is*
  ground distance, so a run of consecutive samples is one pass with no constant to tune.
- **The threshold is `max(3, typical / 2)`, and the floor of 3 does the work.** A pit lane is
  driven **twice** however many laps follow it — out at the start, in at the end — so a purely
  proportional threshold lets it through on anything under six laps.
- **Answered on a trace thinned to one sample per 4 m.** The reference file records at about
  93 Hz, which asks the same question ten times per car length: 131,526 samples took **109 s**
  unthinned and **0.35 s** thinned, for the same answer. It is memoised on top, because a plan is
  built per timeline cut and the editor builds its own.
- **Stretches under 4 s are made to agree with what surrounds them.** Without it the pit exit
  merging alongside the track puts a half-second of "circuit" inside the out lap, and the out lap
  rejoining puts a three-second hole just after the start/finish line. Both drew as visible faults.

When too little was repeated to tell — a hillclimb, a single flying lap, a two-lap session where
the pit lane was also driven twice — **the answer is rejected and the whole trace is drawn.**
Drawing almost none of a session is a worse answer than drawing all of it.

On the reference session this leaves exactly **two** stretches out: everything before the first
complete lap, and everything after the last. Every complete lap survives whole. A lap with a hole
in it would draw as a broken circuit and is the real failure to guard against, so the tests assert
it directly.

**What it does not claim to solve:** a pit lane running *alongside* the pit straight, within the
12 m radius, is not distinguishable from the track by this or by any other means available here.
The last few metres of a pit road survive where it meets the circuit, and should.

Because the outline now has gaps in it, `TrackProjection` carries `segments` and the renderer
strokes each separately — joining two would rule a line straight across the circuit from where the
car left it to where it came back. The car's dot is also held inside the object: it is not part of
the cached trace image, so a car in the pit lane would otherwise draw loose over the video.

### Corner numbering is the circuit's, and it is not sequential

Numbering detected corners 1…N is wrong at most venues. **Sonoma runs 1, 2, 3, 3a, 4, 4a, …** and
letter suffixes are normal — Watkins Glen, Road America and most club circuits have at least one.
So a corner label is a **string**, and the count of official turns is not the count of corners a
curvature detector finds.

**Nothing publishes it.** Checked, not assumed:

| Source | Licence | Corner data |
|---|---|---|
| Wikidata | CC0 | **None.** `P361` / `P131` / `P527` against Sonoma, Suzuka, Silverstone, Laguna Seca, Road America and Watkins Glen returns 27 items — all circuit *layouts* ("Silverstone 1991 Grand Prix layout") and facilities ("Suzuka Circuit Onsen"). Not one corner, no coordinates. |
| OpenStreetMap | ODbL | **Effectively none.** Overpass over Sonoma returns 13 named elements: `Dragstrip`, `Pit Road`, `Sonoma Raceway`, `Sonoma Raceway 2020`, a karting centre and one informally-named way, `PWC lower hairpin`. No turn numbers — and ODbL is rejected here anyway. The public Overpass endpoint refused the request and a mirror was needed, the same fragility the earlier evaluation found. |

So corner numbering lands where sector geometry landed: **derived or drawn, never fetched.**

`TelemetrySession.cornerLabels` carries them, filled from `DataInputSettings.cornerLabels` the
same way sectors are, and `TrackDefinition.cornerLabels` remembers them per circuit — which is the
point of a shareable definition, since one driver working out that Sonoma goes 3, 3a, 4, 4a saves
everyone else doing it.

**Labels attach to the corners the detector found**, which are the ones numbered on the map. That
sidesteps the count mismatch entirely: the driver assigns `3a` to whichever corner it is, rather
than the app trying to reconcile twelve detected corners with fourteen official turns.

Until labels are set the map shows `1…N`, and the inspector says in as many words that this is a
count and not what the circuit calls them.

### The corner on the start/finish line

Numbering the corners of a square found three of four. The missing one sat on the start/finish
line, and the reason is worth recording: curvature is measured between consecutive samples *within
a lap*, so the turn between the lap's last step and its first is not between any two samples and
does not exist at all. Joining the two halves afterwards cannot recover a turn that was never
measured.

`CornerDetector` now closes the loop when the lap closes — the first and last points within a
couple of samples of each other — by computing that one wrap-around curvature and by running the
smoothing window round the ends. An open path (a point-to-point stage) is left alone. Corners come
back sorted by apex distance, which is the order they are met after the line and the order a
circuit numbers them.

Sonoma is unaffected: still exactly 12, because a circuit puts its start/finish on a straight.

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

### What was built

`Sources/TelemetryKit/Sectors.swift`. Every mode resolves to the same thing: **boundary distances
into the lap**, measured once on a reference lap (the session's quickest full lap) and then applied
to every lap by distance travelled. Manual gates are no exception — a gate becomes the distance at
which the reference lap crossed it.

Distance rather than geometry throughout, deliberately. A gate the car drove around on one wide lap
would otherwise lose that lap's sector entirely, and the two automatic modes have no gates to cross
in the first place. The cost is that a sector boundary is a distance, not a place, so a lap driven
appreciably longer than the reference has its boundaries fall slightly early — 0.9 m of lap-to-lap
spread on a 4 km lap makes that immaterial here.

Corner-aware snapping has one rule worth keeping: **a boundary never moves more than half a
sector**. A circuit whose straights all bunch in one place would otherwise give one enormous sector
and two tiny ones, which says less about the driving than an equal split does.

Sector times give the **theoretical best lap** for free: every sector's best added together, the lap
the driver has already shown they can do. On the reference Sonoma session it is 1:54.54 against a
best lap of 1:56.88, the three best sectors coming from laps 2, 3 and 6.

### Seeing them

A **Sector Times** display object (`Sources/RenderKit/SectorPanelRenderer.swift`) draws the lap in
progress one cell per sector: finished sectors show what they took and how that compares, the
sector the car is in shows its running time in the highlight colour, and sectors still to come are
blank — the way a timing screen fills in across a lap. The theoretical lap sits on the end.

A delta that rounds away to `0.00` is drawn in the text colour rather than red. The lap holding a
best sector always shows exactly that, and painting the best lap red on the last digit of floating
point is the sort of thing a driver notices and stops trusting.

Where the sectors come from is set on the **data input**, not on the panel: one file, one set of
sectors, however many panels read them.

### Corner detection

`Sources/TelemetryKit/CornerDetector.swift`, shared by the corner-aware mode and (later) corner
numbering on the track map. The trace is resampled to a fixed 5 m spacing — which is what makes the
result independent of the logger's sample rate — then heading change per metre is smoothed over
25 m, and maximal same-signed runs above a curvature threshold become corners. Runs the same way
less than 40 m apart merge, so an esses is one corner and not four.

**Validated against the reference session: it finds exactly 12 corners on a lap of Sonoma Raceway,
which has 12 turns.** The two 180°-plus readings are the Carousel and the final hairpin.
`onboard probe <file> --corners` prints them.

## Start/finish

More exists than it appears. `DataInputInspector` already has a "Detect laps from a start/finish
line" toggle, a **"Use Current Preview Position as Start/Finish"** button, and fields for latitude,
longitude, heading, half-width, heading tolerance and warm-up crossings to ignore.

What #66 adds — all of it shipped:

- **Place and rotate it on the track map**, rather than typing coordinates. The map already
  projects the trace, so the geometry is there.

  The projection is the one thing both sides must agree on, so `TrackProjection` moved to
  `Sources/RenderKit/TrackProjection.swift`, became public, and gained the inverse
  (`coordinate(at:in:)`) the editor needs. A second copy of that arithmetic in the app would drift
  the first time either side changed its padding. `TrackMapEditing` holds the rest as pure
  functions — where the line's ends are, what a click grabbed, where a drag left it — so the
  geometry is tested without a window and `GizmoView` is left with nothing but mouse events.

  **The gizmo draws; the renderer does not.** Placing a line is an editing affordance and never
  reaches the exported video, so turning the mode on cannot change how a project renders.

  Distances use `LapDetector`'s own metres-per-degree constants, so the line drawn is exactly as
  wide as the line that detects the crossing. **The handles are the exception**: 25 m across a 4 km
  circuit is a few points on screen and both ends land under one click, so they move out to arm's
  length while the line keeps its true width.
- **A first guess from the data** — the trace shows where laps repeat, so a session opens with
  something workable and the driver corrects rather than authors.

  Offered as a button, and applied automatically **only** to a data file just added that brought no
  laps of its own. A file with lap numbers already knows better, and overruling it would be worse
  than saying nothing.

  `Sources/TelemetryKit/StartFinishFinder.swift`. Two routes, in order of how much they know:

  1. **The file's own laps.** A logger that records a lap number already knows where the line is —
     it is wherever the first complete lap began. Nothing needs deriving. On the reference
     RaceChrono session this reproduces the hand-found line **exactly**: 38.16155, −122.45467,
     heading 308°, giving 8 laps whose lengths agree to 0.5%.
  2. **The trace.** Otherwise try forty points around the circuit, skipping any where the car was
     below 40% of its top speed — which throws out the pit lane, the paddock and the moments it
     was parked — and keep the one whose laps come out most consistent.

  Consistency is measured on lap **distances**, not times, as a fraction of the median. And a
  candidate that finds *more* laps only wins when it is at least as consistent, so a line the car
  crosses twice a lap cannot buy its way in on count alone.

  A derived line is not the same place as the hand-found one — any point on the circuit is a valid
  start/finish — and it does not need to be. It needs to give the same laps, which on the
  reference session (lap numbers stripped) it does: 7+ laps within 5%.
- **Remember it per circuit**, which is what identification unlocks: set once per venue, not once
  per session.
- **Export and import track definitions** — line, sectors and circuit name in one file. Since no
  licence can give us sector data, a definition drivers pass around is the only route to a shared
  library, and being contributor-owned it carries no licensing problem at all.

  `.onboardtrack`, declared as `com.freedenizen.onboardstudio.track`. The library was already a
  directory of separate files precisely so one could be attached to a message, so export and import
  are the existing `TrackLibrary.write(_:to:)` and `read(from:)` behind a panel. A venue the
  bundled list has never heard of — a club circuit, an airfield, a car park — exports under the
  input's own name and its recorded position, because such a definition is exactly as worth sharing
  as one for Silverstone.

  **Importing applies on the spot**, where `applyPendingTrackDefinition` deliberately does not:
  choosing a file from a panel is the driver asking for this project to change, and merely opening
  a saved project is not.

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

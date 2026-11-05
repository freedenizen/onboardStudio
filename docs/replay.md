# Replay: laps in 3D

*Milestone v0.35.0 (GitHub milestone #15). Issues #413–#416.*

## The gap

Every lap the app knows is a line on a flat map and a row of numbers. A driver with three laps
of their own and one of a friend's has the Coaching window's corner table and the track map's
dot, but nothing that lets them *watch* the laps race each other round the circuit. The
reference that prompted this is [race.ngoansx.com](https://race.ngoansx.com/): a three.js replay
in a browser that draws the circuit as a road with kerbs over its elevation, paints every lap's
line on the tarmac in its car's colour, moves simple cars with name labels along their laps in
one replay clock (all laps start together; the standings show each car's lap time and gap),
and offers chase, trackside, above and in-car cameras, a scrubber and "go to turn N". Its
per-track data file says what it is built from: one reference lap's GPS resampled every 4 m
into local metres, elevation, a half-width per sample, kerb flags and a turn table — nothing
from a map. Everything it needs the app already had, except the 3D drawing.

Decisions (2026-11-04): a window first and a video object later; any laps from any logbook
sessions; SceneKit; a road from the session's own GPS over a plain ground, no tiles, no network.

## The track as a road (#413)

`TrackModel` (`Sources/TelemetryKit/Replay/TrackModel.swift`) is built from one lap's
`LapProfile` — the home session's best lap — and the other laps that will be shown on it:

- **The plane.** Metres east and north of the track's centre (the mean of the reference's
  positions), with the constants `PositionMatcher` and `LapDetector` already use, so a gate, a
  line and a road agree; `coordinate(at:)` goes back.
- **The centreline.** The reference lap's position every `stepMeters` (4 m) round the loop,
  with its heading, as a closed loop whose last sample is one step short of the first.
- **Elevation.** The reference's altitude channel (`ChannelRole.altitude`, which RaceChrono,
  RCZ, GPX, FIT, GoPro GPMF, VBO, TCX and NMEA all fill and nothing read before) smoothed over
  80 m round the loop — GPS altitude wanders by metres — then levelled so the lap closes on
  itself and lifted so the lowest point reads as 0. `hasElevation` says whether up means
  anything; a logger without altitude gets a flat road, not a guess.
- **Width.** For every other lap, `PositionMatcher.match` gives how far right or left of the
  reference's line it ran at each point; the road's half-width is the widest excursion plus a
  2 m margin, clamped to 5–12 m and smoothed over 40 m, and never wider than 0.8 of the bend's
  radius (a ribbon wider than that folds over itself on the inside). One lap alone gets 6 m.
- **Kerbs.** From `CornerDetector`'s corners on the reference: the inside edge from entry to
  apex, the outside edge from apex to exit, which is where circuits put them.
- `sample(atDistance:)` interpolates (wrapping) and `nearest(to:)` finds the piece of road a
  point is on — distance round the lap and metres right or left of the centreline — through a
  20 m cell grid, so lifting a whole lap onto the road costs nothing much.

`ReplayLap` (`ReplayLap.swift`) is a lap as a car on that road: its line in the plane's metres
with up taken from the road where each point is (plus 5 cm), so a line sits on the tarmac
whatever its own altitude says; `position(atElapsed:)` says where the car is so many seconds
after it started, pointing the way it was going, and waits at the line once home.
`ReplayField` is laps started together: `standings(at:)` orders them by distance (the quicker
lap first among those home) with each car's gap to the leader — how long ago the leader was
where this car is now; once both are home, the difference of their lap times — and
`time(toCorner:following:)` is the replay time a jump to a turn lands on, three seconds before
the followed car's apex so the braking shows.

Tested on the synthetic stadium circuit (`TrackModelTests`): the loop closes at the lap's length,
kerbs appear only inside the two bends and on the right side of each phase of a right-hander, a
second line driven 4 m to the north widens the road, a noisy 10 m hill comes out smooth and
closed, `nearest` tells right from left, and two laps at 30 and 25 m/s stand 50 m apart after ten
seconds with the gap the leader's speed says.

## The scene (#414)

`Sources/RenderKit/Replay/` has two layers. **Mesh builders with no SceneKit in them**
(`MeshArrays.swift`): `RoadMesh` walks the centreline and emits each sample's left and right
edge (a pair per sample and a seam pair, so the loop closes), normals tilted by the climb,
texture coordinates along the strip; `KerbMesh` the same strip just outside whichever edge the
model flags, lifted 2 cm, its v coordinate in stripes so a two-pixel red-and-white texture
repeats every 2 m; `LapRibbon` a lap's points as a 25 cm quad strip 5 cm above the road, since
SceneKit on Metal ignores line width. Quads are wound counter-clockwise seen from above —
SceneKit's front face — which `ReplayMeshTests` checks with a cross product, along with vertex
counts, widths, lifts and the coordinate mapping: east is x, up is y, north is −z, so the world
stays right-handed, and a heading clockwise from north becomes a yaw of −θ for a node whose own
forward is −z. **The SceneKit side** (`SceneGeometry.swift`, `TrackScene.swift`) turns the
arrays into `SCNGeometry` through the raw-data sources (no `SCNVector3` copies), and builds the
scene: a 20 km ground plane just under the lowest sample in the sky's fog, the road in lambert
grey, the kerbs, a post and a billboard label at each corner's apex on the outside of the bend,
each lap's ribbon in its palette colour with depth writes off and a higher rendering order (a
5 cm lift alone z-fights at distance), and a car per lap — a wedge of boxes on four cylinders,
flattened into one draw — with its name on a billboard that scales with distance so it reads the
same size near and far. Labels are Core Text drawn into a `CGImage` on a plane; `SCNText` is
slow to make and awkward to centre.

Everything runs on the main actor: `apply(time:dt:)` puts every car where its lap says and then
the camera. The cameras are per-frame updates, not constraints, so the easing is in seconds:
**Chase** sits 14 m behind and 5 m above the watched car, easing with a 0.25 s time constant;
**Trackside** is the nearest of fixed posts every 150 m, 25 m to the left of the road, with a
narrower lens; **Above** is orthographic straight down (a hair to the south of vertical, since
exactly vertical has no up) over the followed car, or over the whole circuit when nobody is
followed; **In Car** sits in the driver's seat looking along the heading; **Free** is an orbit
about the followed car or the circuit's centre at the view's yaw, pitch and distance. A change
of mode blends from the old pose over 0.6 s. The watched car is the followed lap, else the
leader. `TrackSceneTests` build the scene without a GPU (node names and counts, the road's
sources and primitive count) and drive it: cars move with time and sit on the road's elevation,
each camera ends up where it should. There are no golden images of the 3D view: GPU snapshots
differ across machines, and GitHub's macOS runners may have no Metal device at all.

## What comes next

#415 the Replay window, #416 the release; then, as a
milestone of its own, the same scene rendered into the exported video as a display object.

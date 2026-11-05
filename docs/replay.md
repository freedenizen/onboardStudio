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

## What comes next

#414 the scene (RenderKit, SceneKit), #415 the Replay window, #416 the release; then, as a
milestone of its own, the same scene rendered into the exported video as a display object.

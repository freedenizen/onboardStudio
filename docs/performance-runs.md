# Performance runs: 0–60, the quarter mile and stops (#553) — design

**Status:** step 1 (measuring, `PerformanceRuns`, and `onboard probe --performance`) is built;
steps 2 and 3 are to come.

Draft of 2026-11-13. The user decided four things that day:

- **Which sessions are measured.** A straight-line log is measured on its own. Any other session is
  measured when the driver asks.
- **Rollout.** Distance times use a timeslip's 1-ft rollout. Speed times use none.
- **Where results go.** The Logbook, Trends and the Stat Card.
- **Stops.** Braking is measured alongside the launches.

What this adds: the numbers every GPS performance meter gives without being asked. These are
0–60 mph or 0–100 km/h, 60 ft, ⅛ and ¼ mile with trap speed, and 60–0 or 100–0 braking distance.
They are measured from data the app already loads, so a driver can tell whether a change made the
car quicker in a straight line.

## What the driver sees

1. **Which sessions.** A session with no laps and no runs (#552) is measured as soon as it is read.
   That covers a drag strip, a test road and an airfield. Any other session gets **Performance
   runs** on request, with a switch in two places:
   - the data file's inspector, under *Laps*, beside Timing;
   - the session's detail in the Logbook.

   A circuit's pit exit is a standing start too, but it is never measured unless asked, so a track
   day does not list a slow 0–60 for every session.
2. **Attempts.** Every launch from a standstill is an attempt. Every stop from above the braking
   speed to a standstill is a stop. The session's detail in the Logbook gets a **Performance**
   section:
   - a table with one row per attempt and one column per measure;
   - the best of each measure marked;
   - a stop's distance and time in a table of their own.

   A measure an attempt never reached is left blank. A launch that lifted before 60 mph has a 0–30
   and nothing more.
3. **The measures** follow the speed unit in Settings. Both sets are always computed, so switching
   units never needs a re-read.

   | | Speed times (no rollout) | Distance times (1-ft rollout) | Stops |
   |---|---|---|---|
   | mph | 0–30, 0–60, 0–100, 60–130 mph | 60 ft, 330 ft, ⅛ mile + trap, 1,000 ft, ¼ mile + trap | 60–0 mph, distance and time |
   | km/h | 0–50, 0–100, 0–200, 100–200 km/h | the same marks, named 18 m, 101 m, 201 m, 305 m, 402 m | 100–0 km/h, distance and time |

   A drag strip's marks are the same distances everywhere, so the distance times are one set,
   named in metres for a driver who reads km/h.

   Every result says how it was timed. The distance times read *"(1-ft rollout, as a timeslip)"*.
4. **Can it be trusted?** Each attempt gets two flags, shown as a note beside it, never by hiding
   it:
   - **Slope.** A height change of more than 1 % of the distance, from altitude. *"1.8 % downhill:
     quicker than on the level."*
   - **Data rate.** A rate under 10 Hz. *"5 Hz: times ±0.1 s."*
5. **Trends.** For a circuit, Trends draws lap times. For a session with performance runs, it gets
   a **Performance** chart: the best 0–60 (or 0–100) and ¼ mile of every session, one line per
   car. A tyre, a tune or a launch technique then shows as a step.
6. **In a video.** The **Stat Card** gets *0–60*, *¼ mile* and *60–0* rows. With *Scope ▸ Session*
   they show the session's best. With the lap at the playhead, they show the attempt at the
   playhead. A live drag-tree readout is out of scope for now.
7. **The command line.** `onboard probe <file> --performance` prints every attempt and stop.

## How it works

### Measuring (`TelemetryKit`, `PerformanceRuns`)

- **A launch** is the car standing still, under 0.5 m/s, then moving off. Speed times start where
  speed crosses 0.5 m/s, taken back to zero speed along the acceleration there. The attempt lasts until
  speed first falls by more than 3 m/s below its highest so far: the driver lifted. It also ends
  at the next standstill. Unlike #552's launch rule, it does not ask for a quick start. A gentle
  launch is still an attempt, and its times are simply slow. Only sessions the driver asked for, or
  straight-line logs, are measured.
- **Time zero.**
  - *Speed times* start where speed first passes 0.5 m/s, interpolated between samples.
  - *Distance times* start where the car has rolled 0.3048 m (1 ft) from where it stood. This is a
    timeslip's rollout, and it makes the ¼ mile about 0.2–0.3 s quicker than timing from the first
    movement.
- **Every crossing is interpolated** between samples: a speed reached, or a distance travelled.
  Without that, a 10 Hz log quantises every result to 0.1 s.
- **Distance is interpolated along the speed curve.** Between two samples the car goes from one
  speed to the other, so distance is a curve, not a line. With the speed at both ends the curve is
  solved, which is exact under a constant acceleration. A straight line put the rollout, crossed at
  walking pace, 3 ms out at 10 Hz, and every distance time with it.
- **Distance** is measured from the logger's distance channel, else from GPS (`DerivedChannels`).
- **Trap speed** is the mean speed over the last 66 ft (20.1 m) before the ⅛ or ¼ mile mark, as a
  drag strip's trap measures it. It is not the speed at the line.
- **A stop** runs from speed falling through the braking speed (60 mph or 100 km/h) to a standstill,
  with no rise of more than 1 m/s on the way. Its result is the distance and the time.
- **Slope** is the altitude change over the attempt's distance, from the altitude channel where
  there is one. Without one, it is not stated.

### In the Logbook (`ProjectModel`)

- `LogbookEntry.performance` holds the attempts and stops as numbers: each measure's seconds or
  metres, trap speeds, slope and data rate. It is written when the session is read, as laps are,
  and read again with it.
- `LogbookEntry.measuresPerformance: Bool?` holds the switch. `nil` is automatic: on for a session
  with no laps and no runs.
- Personal bests per measure are kept per car, not per circuit. A straight line is the car's, not
  the venue's.
- Trends adds a performance chart keyed on the car, beside the circuit's lap charts.

### In a project

- `DataInputSettings.measuresPerformance: Bool?` holds the inspector's switch. A project saved
  before has none, decodes as `nil`, and renders exactly as before, because nothing drew these
  numbers.
- `StatCardParams` gains `showLaunch`, `showQuarterMile` and `showStop`. All are `false` when
  absent, so a saved Stat Card is unchanged.

## Build order

One PR each, with its tests and its docs:

1. **Measuring.** `PerformanceRuns` and `onboard probe --performance`.
2. **The Logbook and the project.** The switch in both places, the Performance section, the
   entry's numbers, and the Stat Card rows.
3. **Trends.** The performance chart per car.

**Tests.** Synthetic fixtures only, with answers known from arithmetic:

- A constant acceleration *a* reaches *v* at *t = v / a* and covers *d = a t² / 2*. So 0–60,
  every distance time, rollout and trap speed can be asserted to milliseconds at 10 Hz and at 1 Hz.
- A lift before 60 mph gives an attempt with only a 0–30.
- A stop at constant deceleration gives its distance and time.
- A 2 % slope is flagged.
- A circuit session with a pit exit measures nothing until switched on.

**Docs.**

- A user-guide section, *Performance runs*.
- A journey, *J69 Time a 0–60*, with its XCUITest.
- `docs/formats.md`: nothing; no format changes.
- `docs/project-format.md` and `docs/logbook.md`.
- `parity.md`: TrackAddict's Drag mode and Dragy.

## Not in this design

- A live drag-tree readout in the video.
- Reaction time against a tree. A GPS log has no light to react to.
- Two-way averaging of a run up and back a road.
- Weather correction (SAE J1349).
- Importing a timeslip.

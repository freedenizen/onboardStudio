# Competitive landscape

`docs/parity.md` answers "did we reimplement RaceRender 3". This answers a different question:
what do the tools people actually use offer, where is Onboard Studio ahead, and what is worth building
next.

Surveyed 2026-09-19. Claims carry sources; anything that could not be confirmed says so. The
"Onboard Studio" column and the candidate list were brought up to date on 2026-09-23, at v0.24.0
(#242). On 2026-11-13, at v0.36.0, TrackAddict and the analysis side of its peers were surveyed again,
with trackdayanalysis.com and a wider search for what track-day drivers ask for. That survey is in
[Analysis tools and drivers' asks](#analysis-tools-and-drivers-asks-2026-11-13), and the gaps it
found are filed as #552–#563.

## 3D replay sites

**race.ngoansx.com** (surveyed 2026-11-04) — a browser replay (three.js) of uploaded laps
(Garmin Catalyst, AiM, Exotherm, Porsche Track Precision): the circuit as a road with kerbs
over its elevation, every lap's line on the tarmac, cars with name labels racing in one clock,
chase / trackside / above / in-car cameras, a scrubber, "go to turn N", a mini-map and share
links. Its per-track file is one reference lap's GPS resampled every 4 m with elevation, a
half-width and kerb flags — no map tiles. Onboard Studio's Replay window (v0.35.0,
`docs/replay.md`) does the same offline from any logger the app reads, with the logbook's
sessions across days and cars as the field.

## Where Onboard Studio is already ahead

The most useful result of the survey. Each row is a need that users of other tools are **still
asking for**, in public, and that Onboard Studio already meets.

| Unmet need elsewhere | Evidence | Onboard Studio |
| --- | --- | --- |
| **Alpha / matte overlay export** — render the data over a transparent or key-colour background so it can be composited in another editor | An explicit, unfulfilled request on the Harry's LapTimer forum; not confirmed in any of the eight tools surveyed | `ExportSettings.Background.transparent` and `.keyColor`, with ProRes 4444 and HEVC-with-alpha |
| **Reliable video/data sync** | The single most recurring complaint in the field: Harry's LapTimer users report drift from 1–2 s to 5–6 s across a session | `MediaKit/MotionSync` correlates video motion against logged speed and G-force — the same approach as the open-source OpenLap, which the survey identified as the technically right answer — plus timestamp sync from camera and sidecar clocks |
| **Steering-angle overlay** | Not found in any surveyed tool | `SteeringWheelParams` + `SteeringWheelRenderer` |
| **One portable file for layout and channel mapping** | An explicit RaceChrono forum request from users who lost their setup changing phones; VBOX's `.VVHSN` scene file is the model others are measured against | `.onboardproj`, plus `.onboardtemplate` and `.onboardstyle` for reuse across projects |

Two things follow. These are the product's differentiators and should be said out loud in the
README and release notes. And they are worth protecting: a regression in sync or alpha export costs
more than a missing gauge.

## The tools

**RaceRender 3** (HP Tuners) — the direct reference. Track map, speedometer, tachometer, G-force
plot, gear, lap counter, timer, text data, generic gauge, bar/level, 2D graph, embedded image,
shape, text, video, audio-only, and scriptable "Enhanced" objects; up to 256 display objects and 64
timeline segments; PiP/split/quad; 360°. Broad file compatibility rather than one hardware
ecosystem. Criticised for developer-ish UX. ([Features](https://racerender.com/RR3/Features.html),
[Display Object Toolbox](https://racerender.com/RR3/docs/DispObjToolbox.html))

**RaceChrono Pro** (iOS/Android) — the de facto mobile standard, 100k+ users; its CSV v3 export is
an interchange format other tools target. Gauges, map gauge, predictive lap timer, sector timing,
2,600+ track library, a reworked overlay editor in 2024–25. GPS, OBD-II, CAN with compatible
hardware, phone IMU. Known asks: overlay/CAN-mapping backup, multi-GoPro control, cloud sync; 360°
needs external conversion first. ([racechrono.com](https://racechrono.com/),
[forum](https://racechrono.com/forum/discussion/2217/exporting-video-overlay-gauge-layouts-settings-and-currently-selected-gps-can-bus-channels))

**Dragy** — GPS-only acceleration meter for straight-line testing, not circuit work. Its headline
feature is a fully automatic overlay of performance numbers on a phone clip; near-zero setup.
`dragy·Lap` adds circuit use with dual-camera, G-force and 3D map overlays.
([DSPORT](https://dsportmag.com/the-tech/education/dragy-gps-based-performance-meter/))

**TrackAddict** (HP Tuners) — phone capture designed to hand off to RaceRender. Speed/RPM/G-force
gauges, track map, driving-line analysis, run comparison, predictive timing, sector splits,
theoretical lap. Five track modes: *Circuit* (one start/finish), *Segment* (separate start and
finish, used for autocross, rally and drift, results listed as runs), *Drag Race* (run time, splits,
trap speed), *4x4 Trail* (pitch and roll) and *Raw Data*. A 0–60 / 0–100 time appears whenever a
session starts from a stop. The lap list puts sector times under each lap with the fastest in bold.
A missed split reads 0.000. Shares data as CSV, GPX, KML or VBO. Reviews complain about export and
lap detection (a lost start/finish marker), and ask for overlay-only export, play all laps in
sequence, and a brake-pressure channel. Onboard Studio already has all three of those asks.
([Features](https://racerender.com/TrackAddict/Features.html),
[Getting Started](https://racerender.com/TrackAddict/docs/GettingStarted.html),
[App Store](https://apps.apple.com/us/app/trackaddict/id632355692))

**Harry's LapTimer** — overlay rendered as a separate export step; multi-lap ranges, intro/extro.
Source of two of the clearest validated gaps above: matte export and sync drift. Reviewed as
settings-heavy. ([forum](http://forum.gps-laptimer.de/viewtopic.php?t=3135))

**VBOX Video HD2 / Circuit Tools** (Racelogic) — the professional end, and the best architectural
reference here. Ships a working default scene (speed, G-ball, lap timing, track map) for any
circuit in its database; speedo, rev meter, brake and throttle gauges, tyre-temperature heat maps,
PiP, bar graphs, custom image gauges. 10 Hz GPS, up to 80 CAN channels, dual 1080p. Delta timing
computed from GPS **position** rather than distance, which it presents as more accurate than
distance-based predictive timers. ([VBOX Video](https://www.vboxmotorsport.co.uk/en/vbox-video))

**AiM Race Studio / SmartyCam** — a renderer on top of a serious CAN acquisition stack. RPM, gear,
speed and track map out of the box with a compatible logger; throttle, brake, lambda, temperatures
and pressures once channels are mapped. Setup complexity is the recurring criticism.
([manual](https://www.aim-sportline.com/download/doc/eng/smartycam/SmartyCam_122_eng.pdf))

**Garmin Catalyst** — coaching-first. Track map, speed, delta, G-G traction circle; "True Optimal
Lap" splices the best sectors into a hypothetical lap; real-time audio coaching; paid cloud vault.
([Garmin](https://www.garmin.com/en-US/newsroom/press-release/automotive/optimize-time-on-the-track-with-the-cutting-edge-garmin-catalyst-2/))

**Apex Pro** — real-time LED coaching in peripheral vision, an "APEX Score", and post-session
overlay of data onto GoPro/phone video. ([apextrackcoach.com](https://apextrackcoach.com/))

**RaceBox** — 25 Hz GPS logger with no first-party video overlay; a third-party ecosystem fills the
gap (RaceBuddy Overlay with vertical/story export and stat cards, StintBox with 46 widgets,
OpenLap with motion-correlation auto-sync). ([RaceBox](https://www.racebox.pro/products/mobile-app),
[OpenLap](https://github.com/adamisbk/OpenLap))

**Track Titan** — **not a peer.** It is a sim-racing (iRacing/ACC/LMU) live coaching overlay.
Recorded here only so it is not mistaken for a comparable product. Its "root-cause" coaching — a
slow exit attributed to a braking error two corners earlier — is an interesting UX pattern, nothing
more. ([tracktitan.io](https://www.tracktitan.io/overlay))

## Analysis tools and drivers' asks (2026-11-13)

A second pass, at v0.36.0, looking at how other tools let a driver *review* a session rather than
render one. Sources are web pages and forum threads. Reddit returned nothing to the search, so
forum evidence is from Rennlist, Miata.net and Grassroots Motorsports.

**trackdayanalysis.com** — the closest competitor found to the Logbook and Coaching half of the
app. A free web app built by an HPDE driver and SCCA chief instructor. You drop a file (AiM XRK and
CSV, MoTeC, RaceChrono, Harry's VBO, Catalyst CSV) and see it with no account. It finds corners and
reads brake point, minimum speed, throttle pick-up, trail braking and combined-G use per corner. It
has sectors with a theoretical best, a friction circle, and linked panels where hovering a corner
on the map highlights it everywhere. *Track Difference* is a ribbon on the circuit showing who is
ahead. Its 3D replay takes up to four laps, and *Head-to-Head* compares up to four drivers corner by
corner. A Progress page tracks best lap, consistency, grip used, smoothness and coasting over time,
filtered by car and by conditions. It fills in each session's weather and merges an ECU CSV by
cross-correlating RPM. With an account it adds sharing, comments pinned to a corner, a leaderboard,
a virtual dyno and a car-health check.
([analysis](https://trackdayanalysis.com/analysis.html),
[progress](https://trackdayanalysis.com/progress.html), [FAQ](https://trackdayanalysis.com/faq.html))

**Peers' review screens.** Racelogic Circuit Tools opens on the fastest lap and adds a second, with
side-by-side video bordered green and red. Its v3.2 *Insights* reads grip used corner by corner
against a target, which comes closest to the Coaching window. AiM Race Studio 3 has Split, Channels
and Track reports, scatter and histograms. MoTeC i2 has overlaid laps with a variance trace, a
time report, and a Track Report that puts statistics on the map. RaceChrono's 2025 analysis screen
has an X/Y graph and the map line coloured by any channel. Harry's LapTimer has histograms, a G-G
chart with two-cursor sections, and a live overlay player. Garmin Catalyst gives three
opportunities on a segmented map with clips of the same corner across laps. Its *True Optimal Lap*
is criticised for hiding which laps it spliced and for letting no lap be left out.

**Newer tools.** Laptura (stacks sessions to show which corners got faster), Laptica (AI coach with
setup management), LapSmart (sends your data for a human review), SoloStorm, AutoX Data Logger and
ConeMaster (autocross run comparison and cone maps), and OpenLap (a GPL desktop overlay app with a
reference lap and live delta, the nearest open-source rival to the editor). AimMac is a native Mac
reader of AiM data with maths channels; it was not examined.

**What drivers ask for**, by how often it came up:

1. Video first, with a few numbers on it, rather than raw graphs. The editor and the Coaching
   window's *Watch* already lead with this.
2. One thing to work on, not every channel. Novices are told to pick one focus for the next
   session. The walkthrough and the plan already do this.
3. Whether phone GPS can be trusted. Opinion swings from "garbage" to "within 0.01 s of the
   transponder" because nothing tells the driver which case they are in (#555).
4. Comparison with a reference: their best, earlier against later in the day, a friend's or an
   instructor's lap. Covered by Coaching, Compare Laps and Trends.
5. Whether a tyre, pressure or setup change helped (#559).
6. Autocross runs, cone penalties and run against run (#552).

**Not found anywhere surveyed:** a logbook of days, sessions and cars; per-circuit goals; a season
summary; a next-session plan carried to the circuit. These remain Onboard Studio's own.

**Looked at and not filed:**

- `Homan13/hpde-analytics-cli` turned out to be a MotorsportsReg registration-report tool, with no
  telemetry, so it offers nothing here.
- Comments, leaderboards, following other drivers, and send-for-review need a backend (see
  [Out of scope](#out-of-scope)). A file to hand to a friend is #563.
- Live tools (RaceVoice, Runtime Racing, Apex Pro's lights, TrackAddict's live telemetry and
  auto-start) are out of scope.
- The virtual dyno, car-health rules on engine channels, and a brake-balance worksheet are
  engineering tools, not driver coaching.
- TrackAddict's 4x4 Trail mode is off-road pitch and roll, outside the track-day audience.

## Overlay elements by how widely supported they are

| Support | Element | Onboard Studio |
| --- | --- | --- |
| Near-universal | Speedometer | Yes |
| Near-universal | Track map with position | Yes, plus Apple Maps imagery and a second vehicle |
| Near-universal | Lap timer / lap counter | Yes, seven timer modes |
| Very common | G-force circle / plot | Yes, with a fading trail and per-axis channels |
| Very common | Predictive lap timer / live delta | Yes — native lap and speed delta, and the projected lap time, against the session best, the best so far or the previous lap (#155) |
| Very common | Sector / split times | Yes — Sector Times panel: equal-distance or corner-aware sectors, compared with the best and previous lap |
| Common (needs CAN/OBD) | Tachometer | Yes |
| Common (needs CAN/OBD) | Gear indicator | Yes |
| Common (needs CAN/OBD) | Throttle / brake bars | Yes, Bar object with segments and zones |
| Moderate | 2D data graphs | Yes — time, distance, lap or another channel (X-Y) axis, multi-series, best-lap ghost, and what is coming as well as what has been (#156) |
| Moderate | Lap / run comparison | Yes — two laps' video side by side or stacked, the second retimed to stay level by distance, from one session or two, with the delta between; plus the ghost trace on the graph (#154) |
| Moderate | Picture-in-picture / multi-camera | Yes, with layout presets and segment-based switching |
| Niche | Shift lights | Covered by Indicator lights and segmented Bars |
| Niche | Steering-angle indicator | **Yes — not found in any other surveyed tool** |
| Niche | Tyre-temperature heat map | No (VBOX only, among those surveyed) |
| Common | Track line coloured by any channel (speed, brake, throttle, G) | No — by sector or delta only (#561) |
| Moderate | Friction-circle / combined-G use read per corner | No — the G-force object draws it, nothing reads it (#558) |
| Moderate | Point-to-point runs (autocross, hill climb, stage) | No — laps need one start/finish line (#552) |
| Moderate | Performance runs: 0–60, ¼ mile, braking distance | No (#553) |
| Niche | Theoretical / optimal lap | Yes — *Optimal* on the Sector Times panel, and in the data inspector |
| Emerging | Video stabilisation of helmet or chest footage | Yes — from GoPro's motion data, from the picture's own movement, or with a user-installed Gyroflow, keeping telemetry and sync (#140) |
| Emerging | After-session coaching: corners ranked by time lost, with what to change | Yes — the Coaching window and `onboard coach` (#321, #320): phases, brake point, minimum speed, throttle, consistency, against the best lap, the fastest rolling lap, the spliced optimal lap or another driver's lap; see `docs/coaching.md` |
| Emerging | Vertical / social export with stat cards | Yes — a Stat Card object, a Social (9:16) template, and one lap or marker exported as a vertical clip in one action (#151) |

## Candidate work

Originally ranked by breadth of evidence, not by effort. Where each item stands now:

**Shipped**

1. **Sector / split times** — the Sector Times panel, sectors at equal distances or on the straights
   between corners (v0.21.0).
2. **Theoretical / optimal lap** — best sectors spliced into one lap, shown as *Optimal* (v0.21.0).
3. **Sector deltas as an overlay object** — the Sector Times panel's comparison with the best and
   previous lap (v0.21.0).
4. **Track database** — taken the way this document suggested: rather than shipping start/finish
   lines, the circuit is recognised from the log (about 1,290 circuits, by position and name), the
   start/finish line is suggested from the lap geometry already in the data, and a line the user
   places is saved as a track definition for next time (v0.21.0).
5. **Batch export, one file per lap** — *Every lap, one file each* in the Export sheet and
   `onboard render --laps each` (#150, v0.25.0).
6. **Lap-vs-lap video comparison** — Project ▸ Compare Laps: two laps' pictures side by side, the
   compared one retimed by the fraction of the lap so corners arrive together, across sessions too
   (#154, v0.26.0).
7. **Projected lap time** — the Timer's *Projected lap* and the `projectedLap` channel: the compared
   lap's time plus the position-based delta (#155, v0.26.0).
8. **Social export: stat cards and clip extraction** — the Stat Card object, the Social (9:16)
   template, and Export Lap as Vertical Clip (#151, v0.25.0).
9. **Graph X-Y axis against an arbitrary channel** — *Another channel (X-Y)* on the graph, and the
   playhead moved off the right edge of time and distance graphs so the future shows (#156, v0.26.0).

**Filed and under way**

10. **Coaching** — the step none of the surveyed overlay tools takes and every coaching product
    does: rank the corners by time lost, say which phase and what to try. Milestones v0.29.0,
    v0.30.0 and v0.31.0 (#315–#335); design in `docs/coaching.md`.

**Filed 2026-11-13, from the analysis survey below** (none started; most need a design first)

- #552 point-to-point runs: autocross, hill climb, rally stage, with penalties and a course that
  changes every event
- #553 performance runs from a standstill: 0–60, ¼ mile, trap speed, braking distance
- #554 a lap that should not count (traffic, a flag, an off), and which laps an optimal lap came from
- #555 how good the GPS data is, and how far its brake points can be trusted
- #556 laps as data without building a video: linked traces, delta-T, map and picture
- #557 a session's lap table: sector splits per lap, best sectors, speeds
- #558 grip use: combined braking and turning, time near the limit, and its trend
- #559 judging a tyre, pressure or setup change: structured pressures, Trends split by conditions
- #560 weather filled in from the session's time and place (the first network read for analysis)
- #561 the track line coloured by any channel
- #562 a second logger (an ECU CSV) lined up with the first by a shared channel
- #563 a lap or session's telemetry exported as CSV, GPX, KML or VBO

**Not filed**

11. **Bézier curves in the script canvas** — the remaining scripting gap.

Also recorded in `parity.md` and not filed: no heading-offset field, no `.rrp` import, no Sony
`rtmd` embedded GPS. (`.rcz` import shipped in v0.22.0.)

## Out of scope

Recorded so it stops being re-proposed.

- **Live / in-car use** — real-time overlay on a connected device, live coaching cues, predictive
  timing during the session. This is RaceChrono, Garmin Catalyst and Apex Pro territory, and it
  implies a fundamentally different application. Coaching *after* the session is in scope and
  under way — see `docs/coaching.md`.
- **Cloud and sharing** — accounts, cloud project sync, a shared template gallery. Implies a
  backend and ongoing cost.

Lap comparison (v0.26.0) and social / vertical export (v0.25.0) have shipped. **Telemetry analysis
for its own sake** is now the Coaching milestones (v0.29.0–v0.31.0): any two laps aligned by
distance or position, the fastest rolling lap and the spliced optimal lap as references, per-corner
metrics with the time lost in each phase, ranked opportunities with plain-language notes, then the
same in the video and across sessions. The survey behind it is in `docs/coaching.md`.

## Unverified

- No surveyed tool was found to offer a steering-angle overlay. Absence of evidence — it may exist
  somewhere unsearched.
- The depth of RaceRender 3's 360° support: the marketing lists it, the documentation does not
  describe it.
- Whether RaceChrono has since shipped its promised overlay/channel-mapping backup.
- AiM's exact gauge and template catalogue size.
- RaceRender's internal channel typing and unit-normalisation model — the user-facing workflow is
  documented, the internals are not.

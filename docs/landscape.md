# Competitive landscape

`docs/parity.md` answers "did we reimplement RaceRender 3". This answers a different question:
what do the tools people actually use offer, where is OverlayGen ahead, and what is worth building
next.

Surveyed 2026-09-19. Claims carry sources; anything that could not be confirmed says so.

## Where OverlayGen is already ahead

The most useful result of the survey. Each row is a need that users of other tools are **still
asking for**, in public, and that OverlayGen already meets.

| Unmet need elsewhere | Evidence | OverlayGen |
| --- | --- | --- |
| **Alpha / matte overlay export** — render the data over a transparent or key-colour background so it can be composited in another editor | An explicit, unfulfilled request on the Harry's LapTimer forum; not confirmed in any of the eight tools surveyed | `ExportSettings.Background.transparent` and `.keyColor`, with ProRes 4444 and HEVC-with-alpha |
| **Reliable video/data sync** | The single most recurring complaint in the field: Harry's LapTimer users report drift from 1–2 s to 5–6 s across a session | `MediaKit/MotionSync` correlates video motion against logged speed and G-force — the same approach as the open-source OpenLap, which the survey identified as the technically right answer — plus timestamp sync from camera and sidecar clocks |
| **Steering-angle overlay** | Not found in any surveyed tool | `SteeringWheelParams` + `SteeringWheelRenderer` |
| **One portable file for layout and channel mapping** | An explicit RaceChrono forum request from users who lost their setup changing phones; VBOX's `.VVHSN` scene file is the model others are measured against | `.overlayproj`, plus `.overlaytemplate` and `.overlaystyle` for reuse across projects |

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
theoretical lap. Autocross, rally, drift and drag modes besides circuit.
([Features](https://racerender.com/TrackAddict/Features.html))

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

## Overlay elements by how widely supported they are

| Support | Element | OverlayGen |
| --- | --- | --- |
| Near-universal | Speedometer | Yes |
| Near-universal | Track map with position | Yes, plus Apple Maps imagery and a second vehicle |
| Near-universal | Lap timer / lap counter | Yes, seven timer modes |
| Very common | G-force circle / plot | Yes, with a fading trail and per-axis channels |
| Very common | Predictive lap timer / live delta | Partial — native lap and speed delta to the session best; no *projected* final lap time |
| Very common | Sector / split times | **No** |
| Common (needs CAN/OBD) | Tachometer | Yes |
| Common (needs CAN/OBD) | Gear indicator | Yes |
| Common (needs CAN/OBD) | Throttle / brake bars | Yes, Bar object with segments and zones |
| Moderate | 2D data graphs | Yes — time, distance or lap axis, multi-series, best-lap ghost |
| Moderate | Lap / run comparison | Partial — ghost trace on the graph; no side-by-side video |
| Moderate | Picture-in-picture / multi-camera | Yes, with layout presets and segment-based switching |
| Niche | Shift lights | Covered by Indicator lights and segmented Bars |
| Niche | Steering-angle indicator | **Yes — not found in any other surveyed tool** |
| Niche | Tyre-temperature heat map | No (VBOX only, among those surveyed) |
| Niche | Theoretical / optimal lap | **No** — depends on sectors |
| Emerging | Vertical / social export with stat cards | Partial — a 1080×1920 preset exists; no stat cards or clip extraction |

## Candidate work, ranked

For review before any of these is filed as an issue. Ranked by breadth of evidence, not by effort.

1. **Sector / split times** — `enhancement`. Near-universal elsewhere (RaceChrono, TrackAddict,
   VBOX, Garmin, RaceBox) and entirely absent here. Cheaper than it looks: `TelemetryKit`'s
   `FinishLine` crossing detection already documents itself as working for "a start/finish (or
   sector) line"; what is missing is storing more than one line per input and timing between them.
   Unlocks items 2 and 3.
2. **Theoretical / optimal lap** — `enhancement`. Best sector times spliced into one hypothetical
   lap. VBOX and Garmin both make a headline of it. Depends on 1.
3. **Sector deltas as an overlay object** — `enhancement`. Depends on 1.
4. **Track database** — `enhancement`. Others ship 2,600+ circuits with start/finish and sectors
   pre-set; OverlayGen has a manual `LapLineSpec`. This is the "works out of the box" gap, and it
   matters: low setup friction is praised by name in reviews of VBOX and TrackAddict, while
   RaceRender, Harry's and AiM are all criticised for the opposite. Consider deriving a line from
   the data instead of shipping a database — the lap geometry is already in the log.
5. **Batch export, one file per lap** — `enhancement`. A repeated ask against Harry's LapTimer.
   `ExportRange.laps(first:last:)` already exists; this is iteration plus naming.
6. **Lap-vs-lap video comparison** — `enhancement`. Frame-locked side-by-side of two laps. Widely
   wanted, and nobody does it well for *video* rather than data traces.
7. **Projected lap time** — `enhancement`. Completes the predictive timer. Note the survey's
   finding that GPS-position-based delta is materially more accurate than distance-based.
8. **Social export: stat cards and clip extraction** — `enhancement`. Emerging elsewhere and absent
   from all four established tools; the vertical preset is the groundwork.
9. **Graph X-Y axis against an arbitrary channel** — `enhancement`. Already in `parity.md` as the
   one partial display object.
10. **Bézier curves in the script canvas** — `enhancement`. The remaining scripting gap.

Also already recorded in `parity.md`: no heading-offset field, no `.rcz` or `.rrp` import, no Sony
`rtmd` embedded GPS.

## Out of scope

Recorded so it stops being re-proposed.

- **Live / in-car use** — real-time overlay on a connected device, live coaching cues, predictive
  timing during the session. This is RaceChrono, Garmin Catalyst and Apex Pro territory, and it
  implies a fundamentally different application.
- **Cloud and sharing** — accounts, cloud project sync, a shared template gallery. Implies a
  backend and ongoing cost.

In scope but not started: **telemetry analysis** (lap comparison, sector analysis, channel maths
for their own sake, not only as overlay) and **social / vertical export**.

## Unverified

- No surveyed tool was found to offer a steering-angle overlay. Absence of evidence — it may exist
  somewhere unsearched.
- The depth of RaceRender 3's 360° support: the marketing lists it, the documentation does not
  describe it.
- Whether RaceChrono has since shipped its promised overlay/channel-mapping backup.
- AiM's exact gauge and template catalogue size.
- RaceRender's internal channel typing and unit-normalisation model — the user-facing workflow is
  documented, the internals are not.

# Competitive landscape

`docs/parity.md` answers "did we reimplement RaceRender 3". This answers a different question:
what do the tools people actually use offer, where is Onboard Studio ahead, and what is worth building
next.

Surveyed 2026-09-19. Claims carry sources; anything that could not be confirmed says so. The
"Onboard Studio" column and the candidate list were brought up to date on 2026-09-23, at v0.24.0
(#242); the survey itself was not repeated.

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
| Moderate | Lap / run comparison | Partial — ghost trace on the graph; no side-by-side video (#154) |
| Moderate | Picture-in-picture / multi-camera | Yes, with layout presets and segment-based switching |
| Niche | Shift lights | Covered by Indicator lights and segmented Bars |
| Niche | Steering-angle indicator | **Yes — not found in any other surveyed tool** |
| Niche | Tyre-temperature heat map | No (VBOX only, among those surveyed) |
| Niche | Theoretical / optimal lap | Yes — *Optimal* on the Sector Times panel, and in the data inspector |
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
7. **Projected lap time** — the Timer's *Projected lap* and the `projectedLap` channel: the compared
   lap's time plus the position-based delta (#155, v0.26.0).
8. **Social export: stat cards and clip extraction** — the Stat Card object, the Social (9:16)
   template, and Export Lap as Vertical Clip (#151, v0.25.0).
9. **Graph X-Y axis against an arbitrary channel** — *Another channel (X-Y)* on the graph, and the
   playhead moved off the right edge of time and distance graphs so the future shows (#156, v0.26.0).

**Filed**

6. **Lap-vs-lap video comparison** — #154, v0.26.0 *Analysis*.

**Not filed**

10. **Bézier curves in the script canvas** — the remaining scripting gap.

Also recorded in `parity.md` and not filed: no heading-offset field, no `.rrp` import, no Sony
`rtmd` embedded GPS. (`.rcz` import shipped in v0.22.0.)

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

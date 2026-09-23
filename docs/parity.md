# RaceRender 3 parity audit

Status of every RaceRender 3 feature (from its documentation) in Onboard Studio 0.12, ticked after
the M14 audit. ✅ done, ◐ partial, ❌ not implemented.

## Inputs

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Video / audio / image / data files | ✅ | One input feeds many objects |
| Trim, rotation, mirror H/V, crop per edge | ✅ | Rotation is 0/90/180/270 in the UI; any angle in the file |
| Brightness / contrast / saturation / hue / sharpness | ✅ | |
| Chroma key (colour + tolerance) | ✅ | Plus softness |
| Fisheye / 360 unwrap (FOV, pan) | ✅ | Fisheye and equirectangular, yaw/pitch/roll, runtime Metal kernel |
| Audio volume / balance / channel select | ✅ | |
| Play speed, start position, offset in project | ✅ | `SyncSettings` |
| Containers AVFoundation cannot open (MTS, AVI, MKV) | ✅ | Converted with ffmpeg when installed |

## Data input

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Column → channel mapping with fallbacks, unit factors | ✅ | Attribute-first mapping: one row per attribute, set globally / per project / per input |
| Unit conversion for display | ✅ | Source unit and display unit per attribute, overridable per object; pressure, temperature, speed, length and angle families |
| Sample-rate boost with GPS-aware interpolation | ✅ | Resample + GPS-update-aware policy |
| Smoothing | ✅ | |
| Speed / heading from position, heading offset | ◐ | Derived speed/heading/distance; no heading offset field |
| Calculated fields | ✅ | Expression language |
| Lap detection (line by lat/lon or "position at this time", tolerances, ignore first N, sub-sample precision) | ✅ | Map pick, heading tolerance, half width, ignore-first-N, interpolated crossing |
| Data Sync Wizard | ✅ | Plus timestamp auto-sync and motion (audio) auto-sync, which RaceRender lacks |

## Display objects

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Common: label, input, X/Y/W/H %, aspect lock, transparency, mirror, RGB mask, volume/pan | ✅ | |
| Project details (track, car, driver, date) in text | ✅ | Beyond RaceRender: `{track}`-style keys in any Text object, filled in from the data file, plus the owner's own details; **Title Card** object |
| Font per object | ✅ | Font, typeface and text size on every object that draws text, plus a project-wide font objects follow until they choose their own |
| Video, Audio Only | ◐ | Video ✅; audio-only inputs mix without an object (an `.audio` input) |
| Shape, Text, Embedded Image (data-driven rotation/opacity/flash) | ✅ | |
| Track Map (+ map background, two-vehicle) | ✅ | Apple Maps imagery (map/satellite/hybrid), second vehicle |
| Speedometer, Tachometer, Gauge (Gauge Designer) | ✅ | |
| Bar / Level, 2D Graph (vs time/distance/channel), G-Force Plot | ◐ | Graph vs time, distance and lap; no "vs arbitrary channel" x-axis |
| Gear, Lap Counter, Timer (all modes), Text Data (formatting) | ✅ | Timer: current/last/best/session/project/time-of-day/delta-to-best |
| Enhanced (scripted) object | ✅ | JavaScript instead of RaceRender's C-like language; RaceRender-style names shimmed |
| Warning lights (brake / ABS / DSC "Enhanced Display" styles) | ✅ | Native **Indicator** object: ISO ABS and traction glyphs, warning triangle, round light or text; any channel + condition + threshold (templates bind to the logger's channel by name, with a suggested threshold from its range), hold time, flash, glow |
| Translucent steering wheel and glass instruments (manufacturer track-app look) | ✅ | Native **Steering Wheel** object, gradient-filled shapes, project-wide overlay opacity, **Glass Cockpit** template |
| Delta columns added by an external script (`speed_delta_vs_best`, `time_delta_vs_best`) | ✅ | Derived natively as `lapDelta` / `speedDelta` channels for every object, against the session's best full lap; ± **Delta Bar** templates; verified sample by sample against the user's Python script |
| "Timing and deltas" strip (script in the user's project) | ✅ | Native **Timing Panel**: best/previous/current with editable headings and optional lap numbers, speed and time lanes against the best or the previous lap |
| Threshold colours on readouts (water/oil script) | ✅ | Text Data warning zones |

## Gauge Designer

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Needle / dual-needle / graph styles | ✅ | needle, dualNeedle, arc |
| Sweep ≤ 360°, rotation, CCW | ✅ | |
| Needle length / tail / width / hub / taper / colours | ✅ | |
| Large/small ticks + labels, declutter | ✅ | |
| Threshold colours with gradients on needle/marks/face | ✅ | Zones with targets |
| Custom face image, needle smoothing | ✅ | |

## Scripting (Enhanced objects)

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Background (once) + foreground (per frame) scripts | ✅ | `background(canvas)` / `frame(canvas, data)` |
| Text / number / time, dot, line, rect, rrect, circle, poly, gradients | ✅ | |
| Bezier curves | ❌ | Not in the canvas API yet |
| Data accessors, lap timing functions, math/string utilities | ✅ | JavaScript's own Math/String plus helpers |

## Timeline and multi-camera

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| Segments at project times, inherit/override per property | ✅ | Visibility, frame, opacity per object |
| Shifting a segment moves later ones | ✅ | |
| Camera switching, PIP, split, quad | ✅ | Layout presets |

## Output

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| H.264 / HEVC MP4 up to 4K, size presets, fps, bitrates, audio settings | ✅ | Plus ProRes 4444 and HEVC-with-alpha overlay-only exports |
| Range: whole / time span / laps | ✅ | |
| 360° spherical metadata | ✅ | |
| YouTube upload | ✅ | Device-code sign-in, resumable upload (needs the user's own OAuth client) |
| Templates, object style import/export | ✅ | `.onboardtemplate`, `.onboardstyle` |
| RaceRender `.rrt` / `.rrp` files | ❌ | Undocumented binary format; not reverse-engineered |

## Data formats

| RaceRender | Onboard Studio | Notes |
|---|---|---|
| RaceRender CSV, GPX, TCX, FIT, NMEA, VBO, generic CSV/TSV (TrackAddict, Harry's, RaceChrono, AIM, MoTeC…) | ✅ | Own FIT decoder; header profiles for common apps |
| RaceChrono `.rcz` archives | ✅ | Imports on its own, with the logger's own lap list |
| GoPro GPMF embedded GPS | ✅ | Own MP4/GPMF reader (AVFoundation hides the track) |
| Sony / DJI / Garmin camera metadata | ◐ | DJI SRT and Garmin FIT sidecars, Sony XML clock; Sony `rtmd` embedded GPS not read |

## Performance (M14 measurements, M2 MacBook-class Apple silicon, HERO13 4K source)

| Case | Result |
|---|---|
| Overlay drawing, 11 objects, 1080p | 4–6 ms/frame (≈ 180 fps) |
| Overlay drawing, 11 objects, 4K | 18 ms/frame (≈ 55 fps) |
| Full export, 1080p HEVC | 3.7× real time (111 fps) |
| Full export, 4K HEVC | 1.9× real time (58 fps) |
| Memory | Flat: +13 MB over 300 frames; the two-hour synthetic session test allows +200 MB |

`onboard bench [--project X] [--size WxH] [--export --codec hevc --seconds 60]` reproduces these.

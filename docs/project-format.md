# Project file format

A project is a package directory `Name.onboardproj/` containing `project.json`. Media and data
files are referenced by path; relative paths resolve against the package directory. A bare
`project.json` elsewhere works too (paths resolve against its directory).

`project.json` is the `Project` type from `Sources/ProjectModel` encoded with `JSONEncoder`
(sorted keys, pretty printed). `schemaVersion` is checked on load; older versions are migrated in
`Project.migrateIfNeeded()`, newer ones are rejected.

```json
{
  "schemaVersion": 1,
  "settings": { "outputWidth": 1920, "outputHeight": 1080, "frameRate": 30, "duration": null,
                "framing": { "zoom": 1, "centerX": 0.5, "centerY": 0.5, "crop": { "top": 0, "left": 0, "bottom": 0, "right": 0 } },
                "overlayOpacity": 1 },
  "export": { "codec": "h264", "width": 1920, "height": 1080, "frameRate": 30, "videoBitrate": 16000000,
              "audioBitrate": 192000, "audioSampleRate": 48000, "audioChannels": 2 },
  "inputs": [ … ],
  "displayObjects": [ … ]
}
```

`settings.overlayOpacity` (0…1, default 1) fades the whole overlay layer (everything but the videos) over the picture, on top of each object's own `opacity`.

## Inputs

| Field | Meaning |
|---|---|
| `id` | UUID, referenced by display objects |
| `source.path` | file path, relative to the package or absolute |
| `kind` | `{ "video": { "_0": { "trim": {…}, "includeAudio": true } } }`, `{ "audio": {} }`, `{ "image": {} }`, or `{ "data": { "_0": { "importerID": null, "roleOverrides": {}, … } } }` |
| `sync` | `startPositionInInput`, `offsetInProject`, `playSpeed` — `inputTime = (t − offsetInProject) × playSpeed + startPositionInInput` |

Data input settings (all optional):

| Field | Meaning |
|---|---|
| `importerID` | force an importer (`racechrono-csv`, `gpx`, …) instead of auto-detection |
| `roleOverrides` | column name → channel role identifier (`speed`, `rpm`, `canbus:Coolant`, `obd:Coolant`, `aux:Oil temp`) |
| `unitOverrides` | column name → unit text (`km/h`, `mph`, `ft`, …) |
| `deriveSpeedFromPosition`, `deriveHeadingFromPosition` | derive from GPS when the file lacks the channel |
| `resampleHertz` | resample linear channels to this rate (`null` = as recorded) |
| `smoothingSeconds` | moving-average window (0 = off) |
| `calculatedFields` | `[{ "name", "expression", "unit" }]` (see `docs/formats.md`) |
| `lapLine` | `{ "latitude", "longitude", "headingDegrees" (or null), "halfWidthMeters", "headingToleranceDegrees", "ignoreFirstCrossings" }`; when present, laps come from line crossings instead of the file |
| `sectors` | `{ "mode": "equalDistance" / "cornerAware" / "manual", "count": 3, "lines": [ … ] }`: how each lap is split for sector times. `count` applies to the two automatic modes; `lines` holds `lapLine`-shaped gates for `manual`. Absent in files saved before sectors existed, and read as three equal sectors — safe as a decode default only because nothing in such a project draws a sector time, so measuring them cannot change how it renders |

Video input settings (all optional; older files decode as neutral):

| Field | Meaning |
|---|---|
| `trim` | `start`/`end` seconds in the file |
| `includeAudio` | whether the file's audio is used |
| `rotation` | degrees clockwise (0/90/180/270) |
| `mirror` | `{ "horizontal": bool, "vertical": bool }` |
| `crop` | `top`/`left`/`bottom`/`right` as fractions of the picture (0…0.5) |
| `color` | `brightness`, `contrast`, `saturation`, `sharpness` (1 = unchanged), `hue` degrees |
| `chromaKey` | `{ "color": "#00FF00", "tolerance": 0.3, "softness": 0.1 }` or `null` |
| `audio` | `volume` (1 = unchanged), `balance` (−1…1), `channels` (`stereo`/`mono`/`left`/`right`), `isMuted` |
| `clips` | `[{ "source": { "path": "GX020037.MP4" }, "trim": { "start": null, "end": null }, "gapBefore": 0, "speed": 1 }, …]`: files played back to back after `source` as one continuous video, each with its own trim (seconds in that file), a black gap before it and its own speed; the input's trim, sync and picture settings cover the whole sequence and each file keeps its own orientation. The M15 short form `{ "path": … }` still decodes. |
| `lens` | `{ "mode": "none" / "fisheye" / "equirectangular", "fov": 180, "outputFov": 90, "yaw": 0, "pitch": 0, "roll": 0 }`: unwraps a fisheye (equidistant, `fov` across the picture width) or a 360° equirectangular source into a flat view. `outputFov` is the horizontal field of view of the result; `yaw` turns right, `pitch` looks up, `roll` tilts. A 360° source becomes a 16:9 picture half the source width. Applied on the GPU with a Metal kernel compiled at run time (CPU fallback when Core Image renders in software). |

Containers macOS cannot open (MTS/M2TS, MKV, some AVI) are converted with `ffmpeg` if it is
installed (`brew install ffmpeg`, or set `ONBOARD_FFMPEG`); the converted copy lives in
`~/Library/Caches/OnboardStudio/remux` and the project keeps the original path.

Image inputs: `{ "image": { "_0": {} } }` with `source.path` pointing at a PNG/JPEG/HEIC/TIFF.

## Display objects

Every object has `id`, `label`, `inputID`, `frame` (unit rectangle, top-left origin, 0…1 of the
output), `opacity`, `isVisible`, and a `kind`. Draw order is array order (first = bottom).

| kind | params |
|---|---|
| `video` | `mirror` (`horizontal`/`vertical`, combined with the input's mirror) and `channelMask` (`red`/`green`/`blue`); the layer is aspect-fitted into `frame` |
| `speedometer`, `tachometer`, `gauge` | `GaugeParams` (the Gauge Designer): `channel`, `title`, `minValue`, `maxValue`, `speedUnit` (`mph`/`kph`/`m/s`), `unitLabel`, `majorTick`, `minorTick`, `sweep` (≤ 360), `rotation`, `counterClockwise`, `style` (`needle`/`dualNeedle`/`arc`), `secondChannel` + `secondNeedleColor`, `needle` (`length`, `tailLength`, `width`, `hubRadius`, `tapered`, `smoothingSeconds`; fractions of the radius), `ticks` (`showMajor`, `showMinor`, `showLabels`, `majorLength`, `minorLength`, `outerRadius`, `labelRadius`, `labelDecimals`, `labelScale`, `declutter`), `zones` (`[{ "from", "to" (or null = to max), "color" }]`), `zoneTargets` (`face`, `marks`, `needle`, `gradient`), `arcWidth`, `arcTrackColor`, `showFace`, `faceImageInputID` (an image input drawn as the face), `valueDivisor`, `showValue`, `decimals`, colours. Pre-0.5 files with `redlineFrom`/`redlineColor` load as a single zone. |
| `bar` | `channel`, `label`, `minValue`, `maxValue`, `fillFromZero` (± bar: fills from zero towards the value; for `lapDelta`, `speedDelta`, steering…), `orientation` (`horizontal`/`vertical`), `fillColor`, `trackColor`, `textColor`, `zones`, `zoneColorsFill` (zone colours the fill, otherwise paints the track), `segments` (0 = continuous), `showValue`, `decimals`, `speedUnit`, `unitLabel`, `cornerRadius` |
| `graph` | `series` (`[{ "channel", "color", "lineWidth" }]`, up to 4), `axis` (`time` = last `window` seconds, `distance` = last `window` metres, `lap` = distance into the current lap), `window`, `minValue`/`maxValue` (null = fit the data), `speedUnit`, `label`, `backgroundColor`, `gridColor`, `textColor`, `gridLines`, `fillUnderLine`, `showCursor`, `showLabels`, `compareBestLap` + `ghostColor` (lap axis: the best lap's trace) |
| `gear` | `channel` (0 = neutral, −1 = reverse, −99 = park), `label`, `showLabel`, `neutralText`, `reverseText`, `parkText`, `fontScale`, colours |
| `lapCounter` | `label`, `showTotal`, `numberOffset`, colours |
| `scripted` | `source`: JavaScript defining `background(canvas)` and/or `frame(canvas, data)`; see `docs/scripting.md` |
| `trackMap` | `lineColor`, `lineWidth`, `dotColor`, `dotRadius`, `rotation` (degrees clockwise), `backgroundColor`; `background` (`none`/`standard`/`satellite`/`hybrid`: Apple Maps imagery behind the outline, fetched once for the session's area and cached in `~/Library/Caches/OnboardStudio/maps`); `secondInputID` + `secondDotColor` (another data input drawn as a second dot, positioned through that input's own sync) |
| `gForce` | `maxG`, `ringStep`, `trailSeconds`, `dotColor`, `gridColor`, `faceColor`, `showValues` |
| `timer` | `mode` (`currentLap`/`lastLap`/`bestLap`/`session`/`projectTime`/`timeOfDay`/`deltaToBest`), `showLapNumber`, `label`, `decimals` (1–3), colours, `aheadColor`/`behindColor` for the delta. `deltaToBest` compares the lap in progress with the best completed lap at the same distance into the lap (needs a distance channel; GPS files get one automatically). `timeOfDay` needs epoch timestamps (RaceChrono) or a recorded start time.; `deltaReference` (`sessionBest` / `bestLap` = best so far / `previousLap`; files without the key use `bestLap`) |
| `textData` | `channel`, `label`, `decimals`, `speedUnit`, `unitLabel`, `alignment`, colours; formatting: `multiplier`, `offset` (shown = value × multiplier + offset), `prefix`, `thousandsSeparator`, `showPlusSign`, `minimumIntegerDigits`, `absoluteValue`, `fontScale`, `labelScale`, `fontName` (empty = monospaced); `zones` (`[{ "from", "to", "color" }]`, recolour the shown value) |
| `indicator` | `channel` (empty = not bound yet; the ABS/Traction templates fill it from the data input when a channel name mentions ABS, DSC, TCS, ESC, ESP, traction or stability), `condition` (`atLeast`/`atMost`/`equal`/`notEqual`), `threshold`, `glyph` (`abs`/`traction`/`warning`/`light`/`text`), `label`, `onColor`, `offColor`, `showWhenOff`, `glow`, `holdSeconds`, `flashHertz`, `outline` |
| `lapPanel` | `showBest`, `showPrevious`, `showCurrent`, `bestLabel`, `previousLabel`, `currentLabel` (headings), `showLapNumbers`, `reference` (`sessionBest` (default) / `bestLap` = best so far / `previousLap`, what the lanes compare with), `showSpeedDelta`, `showTimeDelta`, `speedDeltaRange` (± display units), `timeDeltaRange` (± s), `speedUnit`, `decimals`, `textColor`, `labelColor`, `aheadColor`, `behindColor`, `backgroundColor`, `outline` |
| `steeringWheel` | `channel` (empty = bound to the logger's steering channel when data loads), `degreesPerUnit` (1 = degrees, 57.3 = radians, the lock angle for a −1…1 channel), `invert`, `maxDegrees` (0 = no limit), `rimColor`, `edgeColor`, `rimWidth`, `markerColor`, `markerWidth`, `showSpokes`, `spokeColor`. The frame may extend past the picture so only the upper arc shows |
| `shape` | `shape` (`rectangle`/`roundedRectangle`/`ellipse`), `fillColor`, `gradientEndColor` (optional: fades from `fillColor` at the top/left to this colour at the bottom/right), `gradientHorizontal`, `strokeColor`, `strokeWidth` (fraction of output height), `cornerRadius` |
| `text` | `text`, `fontScale` (fraction of object height), `fontName`, `bold`, `color`, `backgroundColor`, `alignment`, `outlineWidth`, `outlineColor` |
| `image` | `inputID` → an image input; `rotation`, `keepAspect`; data-driven: `rotationChannel` + `degreesPerUnit`, `opacityChannel` + `opacityScale`, `flashChannel` + `flashThreshold` + `flashHertz` (data comes from the first data input) |

Colours are `#RRGGBB` or `#RRGGBBAA`. Speed channels are stored in m/s and converted for display
by `speedUnit`; other channels are shown as stored.

See `Tests/Fixtures/slice.onboardproj/project.json` for a complete example, and render it with:

```sh
swift run onboard render --project Tests/Fixtures/slice.onboardproj --out slice.mp4
```

## Export settings

`export` holds the last export configuration and is what `onboard render --project` uses:

| Field | Meaning |
|---|---|
| `codec` | `h264`, `hevc` (MP4), `hevcAlpha`, `proRes4444` (QuickTime `.mov`, with alpha) |
| `width`, `height`, `frameRate`, `videoBitrate` | output size and rate; ProRes ignores the bitrate |
| `audioBitrate` (null = no audio), `audioSampleRate`, `audioChannels` | AAC audio |
| `background` | `{ "video": {} }` (normal), `{ "keyColor": { "_0": "#0000FF" } }` (overlays over a flat colour, no video) or `{ "transparent": {} }` (overlays over alpha; needs an alpha codec) |
| `spherical` | `true` tags the file as a 360° equirectangular video (Google Spherical Video V1 `uuid` box in the video track, written after encoding) so players and YouTube show a panorama; use with a full equirectangular frame and the lens unwrap off |
| `range` | `{ "whole": {} }`, `{ "span": { "start": 90, "end": 240 } }` (project seconds) or `{ "laps": { "first": 2, "last": 4 } }` (lap numbers of the first data input with laps, mapped through its sync) |

Presets (`--preset` on the CLI, the Preset menu in the app): `720p`, `1080p`, `1440p`, `4k`, `vertical` (1080 × 1920),
`overlay-alpha` (transparent ProRes 4444) and `overlay-key` (blue key, H.264). The CLI also takes
`--laps first:last`, `--background video|transparent|key:#RRGGBB`, `--spherical` and `--template file.onboardtemplate`.

## Templates

A `.onboardtemplate` file is a project without its inputs: `settings`, `export`, `displayObjects`
(with `inputID` cleared), `timeline`, and `videoOrdinals` (which video input, by order, each video
object used). Applying a template keeps the project's inputs and rebinds: video objects to the
video inputs in order (extra ones are dropped), data-driven objects to the first data input. Three
templates are built in (Classic Dash, Minimal, Data Wall); user templates live in
`~/Library/Application Support/OnboardStudio/Templates/`. **File ▸ New from Template**, **Project ▸
Apply Template** and **Save as Template…** use them.

## Missing media

Inputs whose files cannot be found or read are reported per input (a warning in the sidebar, the
reason and a **Relink…** button in the inspector; a `warning:` line from the CLI) and the rest of
the project still loads and renders.

## Timeline

`timeline.segments` is a list of points in project time from which some object properties change:

```json
"timeline": { "segments": [
  { "id": "…", "start": 92.5, "label": "Chase cam",
    "overrides": { "<object id>": { "isVisible": false },
                   "<object id>": { "isVisible": true, "frame": { "x": 0, "y": 0, "width": 1, "height": 1 } } } },
  { "id": "…", "start": 130, "label": "Fade gauges",
    "overrides": { "<object id>": { "opacity": 0.4 } } }
] }
```

Each override may set `isVisible`, `frame` and/or `opacity`; anything not set is inherited from the
previous segment, and before the first segment the objects' own values apply. Camera switching and
picture-in-picture are therefore visibility and frame overrides on the video objects. Moving a
segment shifts every later segment by the same amount. Projects without `timeline` load with none.

At render time each segment becomes its own video-composition instruction, so switches land on
exact frames in both the preview and the export.

## Object styles

**Project ▸ Export Object Style…** writes the selected object's `kind`, `opacity`, `width` and `height` to a
`.onboardstyle` JSON file (`{ "formatVersion": 1, "kind": …, "opacity": 1, "width": 0.22, "height": 0.38 }`).
**Import Object Style…** applies a file to the selected object (keeping its position, label and data source)
or adds a new object when nothing is selected. **Copy / Paste Object Style** (⌥⌘C / ⌥⌘V) do the same through
the clipboard.

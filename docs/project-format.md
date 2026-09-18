# Project file format

A project is a package directory `Name.overlayproj/` containing `project.json`. Media and data
files are referenced by path; relative paths resolve against the package directory. A bare
`project.json` elsewhere works too (paths resolve against its directory).

`project.json` is the `Project` type from `Sources/ProjectModel` encoded with `JSONEncoder`
(sorted keys, pretty printed). `schemaVersion` is checked on load; older versions are migrated in
`Project.migrateIfNeeded()`, newer ones are rejected.

```json
{
  "schemaVersion": 1,
  "settings": { "outputWidth": 1920, "outputHeight": 1080, "frameRate": 30, "duration": null },
  "export": { "codec": "h264", "width": 1920, "height": 1080, "frameRate": 30, "videoBitrate": 16000000,
              "audioBitrate": 192000, "audioSampleRate": 48000, "audioChannels": 2 },
  "inputs": [ … ],
  "displayObjects": [ … ]
}
```

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
| `roleOverrides` | column name → channel role identifier (`speed`, `rpm`, `obd:Coolant`, `aux:Oil temp`) |
| `unitOverrides` | column name → unit text (`km/h`, `mph`, `ft`, …) |
| `deriveSpeedFromPosition`, `deriveHeadingFromPosition` | derive from GPS when the file lacks the channel |
| `resampleHertz` | resample linear channels to this rate (`null` = as recorded) |
| `smoothingSeconds` | moving-average window (0 = off) |
| `calculatedFields` | `[{ "name", "expression", "unit" }]` (see `docs/formats.md`) |
| `lapLine` | `{ "latitude", "longitude", "headingDegrees" (or null), "halfWidthMeters", "headingToleranceDegrees", "ignoreFirstCrossings" }`; when present, laps come from line crossings instead of the file |

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

Containers macOS cannot open (MTS/M2TS, MKV, some AVI) are converted with `ffmpeg` if it is
installed (`brew install ffmpeg`, or set `OVERLAYGEN_FFMPEG`); the converted copy lives in
`~/Library/Caches/OverlayGen/remux` and the project keeps the original path.

Image inputs: `{ "image": { "_0": {} } }` with `source.path` pointing at a PNG/JPEG/HEIC/TIFF.

## Display objects

Every object has `id`, `label`, `inputID`, `frame` (unit rectangle, top-left origin, 0…1 of the
output), `opacity`, `isVisible`, and a `kind`. Draw order is array order (first = bottom).

| kind | params |
|---|---|
| `video` | `mirror` (`horizontal`/`vertical`, combined with the input's mirror) and `channelMask` (`red`/`green`/`blue`); the layer is aspect-fitted into `frame` |
| `speedometer`, `tachometer`, `gauge` | `GaugeParams` (the Gauge Designer): `channel`, `title`, `minValue`, `maxValue`, `speedUnit` (`mph`/`kph`/`m/s`), `unitLabel`, `majorTick`, `minorTick`, `sweep` (≤ 360), `rotation`, `counterClockwise`, `style` (`needle`/`dualNeedle`/`arc`), `secondChannel` + `secondNeedleColor`, `needle` (`length`, `tailLength`, `width`, `hubRadius`, `tapered`, `smoothingSeconds`; fractions of the radius), `ticks` (`showMajor`, `showMinor`, `showLabels`, `majorLength`, `minorLength`, `outerRadius`, `labelRadius`, `labelDecimals`, `labelScale`, `declutter`), `zones` (`[{ "from", "to" (or null = to max), "color" }]`), `zoneTargets` (`face`, `marks`, `needle`, `gradient`), `arcWidth`, `arcTrackColor`, `showFace`, `faceImageInputID` (an image input drawn as the face), `valueDivisor`, `showValue`, `decimals`, colours. Pre-0.5 files with `redlineFrom`/`redlineColor` load as a single zone. |
| `bar` | `channel`, `label`, `minValue`, `maxValue`, `orientation` (`horizontal`/`vertical`), `fillColor`, `trackColor`, `textColor`, `zones`, `zoneColorsFill` (zone colours the fill, otherwise paints the track), `segments` (0 = continuous), `showValue`, `decimals`, `speedUnit`, `unitLabel`, `cornerRadius` |
| `graph` | `series` (`[{ "channel", "color", "lineWidth" }]`, up to 4), `axis` (`time` = last `window` seconds, `distance` = last `window` metres, `lap` = distance into the current lap), `window`, `minValue`/`maxValue` (null = fit the data), `speedUnit`, `label`, `backgroundColor`, `gridColor`, `textColor`, `gridLines`, `fillUnderLine`, `showCursor`, `showLabels`, `compareBestLap` + `ghostColor` (lap axis: the best lap's trace) |
| `gear` | `channel` (0 = neutral, −1 = reverse, −99 = park), `label`, `showLabel`, `neutralText`, `reverseText`, `parkText`, `fontScale`, colours |
| `lapCounter` | `label`, `showTotal`, `numberOffset`, colours |
| `trackMap` | `lineColor`, `lineWidth`, `dotColor`, `dotRadius`, `rotation`, `backgroundColor` |
| `gForce` | `maxG`, `ringStep`, `trailSeconds`, `dotColor`, `gridColor`, `faceColor`, `showValues` |
| `timer` | `mode` (`currentLap`/`lastLap`/`bestLap`/`session`/`projectTime`/`timeOfDay`/`deltaToBest`), `showLapNumber`, `label`, `decimals` (1–3), colours, `aheadColor`/`behindColor` for the delta. `deltaToBest` compares the lap in progress with the best completed lap at the same distance into the lap (needs a distance channel; GPS files get one automatically). `timeOfDay` needs epoch timestamps (RaceChrono) or a recorded start time. |
| `textData` | `channel`, `label`, `decimals`, `speedUnit`, `unitLabel`, `alignment`, colours; formatting: `multiplier`, `offset` (shown = value × multiplier + offset), `prefix`, `thousandsSeparator`, `showPlusSign`, `minimumIntegerDigits`, `absoluteValue`, `fontScale`, `labelScale`, `fontName` (empty = monospaced) |
| `shape` | `shape` (`rectangle`/`roundedRectangle`/`ellipse`), `fillColor`, `strokeColor`, `strokeWidth` (fraction of output height), `cornerRadius` |
| `text` | `text`, `fontScale` (fraction of object height), `fontName`, `bold`, `color`, `backgroundColor`, `alignment`, `outlineWidth`, `outlineColor` |
| `image` | `inputID` → an image input; `rotation`, `keepAspect`; data-driven: `rotationChannel` + `degreesPerUnit`, `opacityChannel` + `opacityScale`, `flashChannel` + `flashThreshold` + `flashHertz` (data comes from the first data input) |

Colours are `#RRGGBB` or `#RRGGBBAA`. Speed channels are stored in m/s and converted for display
by `speedUnit`; other channels are shown as stored.

See `Tests/Fixtures/slice.overlayproj/project.json` for a complete example, and render it with:

```sh
swift run overlaygen render --project Tests/Fixtures/slice.overlayproj --out slice.mp4
```

## Object styles

**Project ▸ Export Object Style…** writes the selected object's `kind`, `opacity`, `width` and `height` to a
`.overlaystyle` JSON file (`{ "formatVersion": 1, "kind": …, "opacity": 1, "width": 0.22, "height": 0.38 }`).
**Import Object Style…** applies a file to the selected object (keeping its position, label and data source)
or adds a new object when nothing is selected. **Copy / Paste Object Style** (⌥⌘C / ⌥⌘V) do the same through
the clipboard.

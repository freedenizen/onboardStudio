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

`roleOverrides` maps a column name to a channel role identifier (`speed`, `rpm`, `obd:Coolant`,
`aux:Oil temp`) when the importer's guess is wrong.

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
| `speedometer`, `tachometer`, `gauge` | `GaugeParams`: `channel`, `title`, `minValue`, `maxValue`, `speedUnit` (`mph`/`kph`/`m/s`), `unitLabel`, `majorTick`, `minorTick`, `sweep`, `rotation`, `redlineFrom`, `valueDivisor`, `showValue`, `decimals`, colours |
| `trackMap` | `lineColor`, `lineWidth`, `dotColor`, `dotRadius`, `rotation`, `backgroundColor` |
| `gForce` | `maxG`, `ringStep`, `trailSeconds`, `dotColor`, `gridColor`, `faceColor`, `showValues` |
| `timer` | `mode` (`currentLap`/`lastLap`/`bestLap`/`session`), `showLapNumber`, `label`, colours |
| `textData` | `channel`, `label`, `decimals`, `speedUnit`, `unitLabel`, `alignment`, colours |
| `shape` | `shape` (`rectangle`/`roundedRectangle`/`ellipse`), `fillColor`, `strokeColor`, `strokeWidth` (fraction of output height), `cornerRadius` |
| `text` | `text`, `fontScale` (fraction of object height), `fontName`, `bold`, `color`, `backgroundColor`, `alignment`, `outlineWidth`, `outlineColor` |
| `image` | `inputID` → an image input; `rotation`, `keepAspect`; data-driven: `rotationChannel` + `degreesPerUnit`, `opacityChannel` + `opacityScale`, `flashChannel` + `flashThreshold` + `flashHertz` (data comes from the first data input) |

Colours are `#RRGGBB` or `#RRGGBBAA`. Speed channels are stored in m/s and converted for display
by `speedUnit`; other channels are shown as stored.

See `Tests/Fixtures/slice.overlayproj/project.json` for a complete example, and render it with:

```sh
swift run overlaygen render --project Tests/Fixtures/slice.overlayproj --out slice.mp4
```

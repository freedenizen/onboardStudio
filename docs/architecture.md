# Onboard Studio architecture

Onboard Studio mixes video, audio and telemetry into a rendered video with data-driven overlays. It is
a native macOS app (Swift 6, SwiftUI, AVFoundation) organised as a Swift package of libraries plus
two thin executables.

## Targets

| Target | Purpose |
|---|---|
| `ProjectModel` | The project document schema: inputs, display objects, timeline segments, export settings. Pure `Codable`/`Sendable` value types; depends on `TelemetryKit` only to build a plan from an analysed lap. |
| `TelemetryKit` | Time-indexed channels, interpolation policies, resampling, smoothing, calculated fields, lap detection, laps as profiles by distance and the delta between any two (`docs/coaching.md`), a circuit as a road built from a lap's GPS (`docs/replay.md`). |
| `Importers` | File-format importers (RaceRender CSV, GPX, TCX, NMEA, VBO, FIT, generic CSV profiles) producing `TelemetrySession`s. |
| `GPMFKit` | GoPro GPMF metadata-track extraction from MP4/MOV via AVFoundation. |
| `RenderKit` | Overlay rendering with Core Graphics: one renderer per display-object kind, gauge engine, render cache, `FrameCompositor`. |
| `MediaKit` | AVFoundation composition building, the custom `AVVideoCompositing` shared by preview and export, video transforms (Core Image), audio mix, exporter, optional ffmpeg bridge. |
| `Scripting` | JavaScriptCore runtime for scripted display objects with a RaceRender-compatible API shim. |
| `onboard` (CLI) | Headless probe / render / bench / golden-update commands. Also the CI smoke test. |
| `OnboardStudioApp` | SwiftUI editor. Built by SwiftPM as a bare executable and by the XcodeGen project (`project.yml`) as `OnboardStudio.app` with Sparkle. |

## Core ideas

- **One pipeline for preview and export.** The project compiles to an `AVMutableComposition` plus an
  `AVVideoComposition` whose custom compositor draws every frame. `AVPlayer` plays that for preview;
  `AVAssetReader` + `AVAssetWriter` drive the same composition for export.
- **Immutable render plans.** Edits produce a new `RenderPlan` value which the compositor swaps in
  under a lock; nothing mutable is shared with AVFoundation's background queues.
- **Core Graphics for overlays, Core Image for video.** Vector drawing and text come from CG into a
  pooled `CVPixelBuffer`; video colour/crop/rotate/chroma-key use built-in CI filters on the GPU.
  No `.metal` files are compiled at build time; any custom kernel is compiled from source at runtime.
- **Single time mapping.** `SyncSettings` (start position in input, offset within project, play
  speed) converts project time to input time identically for video tracks and telemetry sampling.
- **Output time and project time (#442).** Everything placed on the timeline — segments, markers,
  in/out, export ranges, laps through sync — is in project time. Retimes (`Project.retimes`) make
  the finished video's clock differ: `TimeMap` maps output time to project time, piecewise linear
  and flat where a frame holds. `CompiledComposition.retimed(by:)` scales every composition track
  (the compared lap's too) and mutes the sound over retimed stretches; the instructions tile output
  time and carry the map, and `OverlayCompositor` hands each overlay the project time it maps to,
  so picture and data never part. `CompiledComposition.duration` stays project time
  (`outputDuration` is the video's), `Exporter` takes project ranges, and `PreviewController`
  translates at its edge, so the editor sees project time throughout; only frame steps are in
  output frames. With no retimes the map is the identity and nothing differs.
- **Frame-level video processing lives in the layer.** A `VideoLayer` carries everything done to its
  source frame, in order: stabilisation (`LayerStabilisation`, #262/#264 — a per-frame shift and roll
  from a `StabilisationPath`, applied to the recorded frame before its display rotation, because that
  is where the camera's motion was measured), the display rotation, then the input's picture settings.
  Paths are built per plan from what `ProjectCompiler.load` read: a GoPro's per-frame orientation
  (`GoProTelemetry.orientation`), or the picture's own movement measured once and kept
  (`PictureMotion`).
- **A retimed copy is just another track.** The compared lap of a lap comparison (#154) is a second
  composition track of its video, cut at a `LapTimeWarp`'s knots and each piece time-scaled, so the
  compositor, preview and export need nothing special; data objects that follow it sample through the
  same warp. Gyroflow's steadied copies (#263) likewise simply replace the file a video track reads.
- **Other programs stay other programs.** ffmpeg and Gyroflow are GPL and optional: when installed
  they are run as separate processes (`FFmpegBridge`, `Gyroflow`), never linked into the MIT app.
- **Timeline as overrides.** Segments hold JSON fragments per display object; a property is
  inherited unless its key is present. Resolution is a deep merge of all segments up to time *t*.

## Performance notes (M14)

- Every frame's Core Image and CoreVideo objects are autoreleased; `FrameCompositor.render` and
  the export pump drain a pool per frame so long exports and headless renders stay flat (without
  it a 1080p render grows by one 8 MB buffer per frame).
- Static parts of every object (gauge faces, ticks, track outlines, map imagery, script
  backgrounds) are drawn once into `RenderCache` keyed by parameters and size; only needles, dots
  and text are drawn per frame. Fonts are resolved once and cached under a lock.
- Telemetry lookups are binary searches over contiguous `[Double]` channels, so a two-hour 20 Hz
  session costs the same per frame as a two-minute one (`LongSessionTests`).
- `onboard bench` measures overlay drawing, export throughput against real time and resident
  memory; `docs/parity.md` records the current numbers. CI runs it on the fixture project.
- A data file is parsed once however many readers open it (#482). Reading a log is nearly all
  parsing — a synthetic 40 MB RaceChrono CSV of 330,000 rows takes 2.4 s to parse and 0.08 s to
  build into a session, in a release build — and the Logbook's import, a project's compile and
  the Coaching and Replay windows each read the file for themselves. `ParsedFileCache`
  (`Sources/Importers/ParsedFileCache.swift`) keeps the importer's `RawTable` for the file as it
  was, and `TelemetryImporter.importSession` — the one way every reader comes to a file — asks it
  before reading. What a reader reads *through* (channel mapping, units, resampling, the finish
  line, the trim) is applied by `SessionBuilder.build`, which each reader still runs for itself,
  so two readers with different settings share the parsing and nothing else. The file is checked
  with `stat` on every request — size, modification time, and which file it is on the volume — and
  read again when any of them differs (not through `URL` resource values, which a `URL` remembers).
  Readers that arrive together wait for one parse. Tables go least recently used first past eight
  files or 512 MB of samples, after ten minutes unused, and all at once under memory pressure; a
  table larger than the budget is never kept. A task can read through a cache of its own
  (`ParsedFileCache.$current.withValue`); tests that count readings do, because everything else
  importing in the process reads through the shared one and can push a file out of it.

## Build and release

- `swift build` / `swift test` build every library, the CLI and the app executable.
- `xcodegen generate` creates `OnboardStudio.xcodeproj` from `project.yml`; the app target compiles
  `Sources/OnboardStudioApp` and links the package libraries and Sparkle.
- `Scripts/bundle-app.sh` → `Scripts/make-dmg.sh` → `Scripts/notarize.sh` (optional) →
  `Scripts/make-appcast.sh` mirror `.github/workflows/release.yml`, which runs on every `v*` tag and
  publishes the DMG, `appcast.xml` and a CLI tarball as a GitHub Release. Sparkle's feed URL points
  at `releases/latest/download/appcast.xml`.

## Icons

The icons are vector sources in `Design/`, rasterised by `Scripts/make-icons.sh`:

| Source | Used for |
| --- | --- |
| `Design/AppIcon.svg` | the app icon at 128 px and above |
| `Design/AppIcon-small.svg` | the app icon at 16 and 32 px |
| `Design/DocumentIcon.svg` | the `.onboardproj` document icon |

Edit an SVG, run `Scripts/make-icons.sh`, and commit what it writes: the ten PNG slots and
`Contents.json` in `App/Assets.xcassets/AppIcon.appiconset`, plus `App/DocumentIcon.icns` (built
with `iconutil`, and pointed at by `CFBundleTypeIconFile` in `project.yml`). The script needs no
Homebrew tools — AppKit rasterises SVG natively through `_NSSVGImageRep`.

There are two app icon sources because the tick marks turn to mush and a thin needle disappears
below about 48 px, so the small slots use a simplified dial: no ticks, a fatter sweep and a blunt
needle. Apple's own icons split the same way.

`Scripts/check-icons.sh` (a step in the **Lint** job) checks every slot has a file of the right
pixel size and that the document icon is still wired up. It deliberately does *not* diff against a
fresh render — SVG rasterisation shifts between macOS releases, so a byte comparison would fail
whenever GitHub updates the runner image, with nothing actually wrong.

## Roadmap

| Milestone | Deliverable |
|---|---|
| M0 | Scaffolding, CI, DMG, Sparkle updates |
| M1 | Telemetry core, RaceRender CSV and GPX importers, `onboard probe` |
| M2 | AVFoundation pipeline and headless export |
| M3 | First display objects, project file, CLI end-to-end slice |
| M4 | App MVP: import, sync wizard, place gauges, preview, export |
| M5 | Per-input video/audio processing, shapes, text, images, ffmpeg remux |
| M6 | Data processing depth, lap detection editor, more formats |
| M7 | Full gauge set and Gauge Designer |
| M8 | Timeline segments and multi-camera layouts |
| M9 | Templates, export presets, polish |
| M10 | GoPro GPMF, FIT, timestamp auto-sync |
| M11 | Scripted display objects |
| M12 | 360/fisheye, two-vehicle map, map backgrounds |
| M13 | Motion auto-sync, YouTube upload, other camera metadata |
| M14 | Performance, hardening, parity audit |

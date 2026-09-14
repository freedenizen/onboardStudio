# OverlayGen architecture

OverlayGen mixes video, audio and telemetry into a rendered video with data-driven overlays. It is
a native macOS app (Swift 6, SwiftUI, AVFoundation) organised as a Swift package of libraries plus
two thin executables.

## Targets

| Target | Purpose |
|---|---|
| `ProjectModel` | The project document schema: inputs, display objects, timeline segments, export settings. Pure `Codable`/`Sendable` value types. |
| `TelemetryKit` | Time-indexed channels, interpolation policies, resampling, smoothing, calculated fields, lap detection. |
| `Importers` | File-format importers (RaceRender CSV, GPX, TCX, NMEA, VBO, FIT, generic CSV profiles) producing `TelemetrySession`s. |
| `GPMFKit` | GoPro GPMF metadata-track extraction from MP4/MOV via AVFoundation. |
| `RenderKit` | Overlay rendering with Core Graphics: one renderer per display-object kind, gauge engine, render cache, `FrameCompositor`. |
| `MediaKit` | AVFoundation composition building, the custom `AVVideoCompositing` shared by preview and export, video transforms (Core Image), audio mix, exporter, optional ffmpeg bridge. |
| `Scripting` | JavaScriptCore runtime for scripted display objects with a RaceRender-compatible API shim. |
| `overlaygen` (CLI) | Headless probe / render / bench / golden-update commands. Also the CI smoke test. |
| `OverlayGenApp` | SwiftUI editor. Built by SwiftPM as a bare executable and by the XcodeGen project (`project.yml`) as `OverlayGen.app` with Sparkle. |

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
- **Timeline as overrides.** Segments hold JSON fragments per display object; a property is
  inherited unless its key is present. Resolution is a deep merge of all segments up to time *t*.

## Build and release

- `swift build` / `swift test` build every library, the CLI and the app executable.
- `xcodegen generate` creates `OverlayGen.xcodeproj` from `project.yml`; the app target compiles
  `Sources/OverlayGenApp` and links the package libraries and Sparkle.
- `Scripts/bundle-app.sh` → `Scripts/make-dmg.sh` → `Scripts/notarize.sh` (optional) →
  `Scripts/make-appcast.sh` mirror `.github/workflows/release.yml`, which runs on every `v*` tag and
  publishes the DMG, `appcast.xml` and a CLI tarball as a GitHub Release. Sparkle's feed URL points
  at `releases/latest/download/appcast.xml`.

## Roadmap

| Milestone | Deliverable |
|---|---|
| M0 | Scaffolding, CI, DMG, Sparkle updates |
| M1 | Telemetry core, RaceRender CSV and GPX importers, `overlaygen probe` |
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

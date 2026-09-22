---
paths:
  - "Sources/RenderKit/**/*.swift"
  - "Sources/MediaKit/**/*.swift"
  - "Tests/RenderKitTests/**/*.swift"
  - "Tests/MediaKitTests/**/*.swift"
---

# Rendering and compositing

## Golden images
- `UPDATE_GOLDENS=1 swift test --filter RenderKitTests` regenerates goldens. **Look at the diff
  before committing** — a regenerated golden that hides a real regression is worse than a failure.
- A golden containing text can flake once under the parallel run; rerun before chasing it.
- Pixel-probe tests render small frames with `FrameCompositor` and assert colours at known
  coordinates; add one of those for a new drawing primitive before reaching for a golden.

## Pitfalls that have each cost a build cycle
- `CompiledComposition.sourceTransforms` (per track, independent of visibility) must feed **every**
  `VideoLayer` rebuild, or rotated GoPro footage flips. The HERO13 clip has a 180° preferred
  transform: the composition track stays identity and only the compositor rotates.
- One video-composition instruction per timeline segment, and **every instruction requires every
  track**.
- `CTFont` creation is cached under a lock in `TextDrawing`: parallel first-time lookups hang the
  `fontd` XPC connection. Symptom is `swift test` hanging while a serial run passes;
  `killall fontd` does not help. Do not remove that lock.
- Core Image processor kernels get Metal textures with **row 0 at the top** of the region but CPU
  `baseAddress` bitmaps with **row 0 at the bottom**. This is verified by tests and is the
  opposite of the intuitive guess.
- Overlay opacity goes through `CIColorMatrix` scaling **only the alpha vector** — Core Image
  applies colour matrices to unpremultiplied colour.
- Any headless render loop must wrap each frame in `autoreleasepool`; without it the
  exporter/compositor grew ~8 MB per frame.
- `RenderKit` must not import JavaScriptCore. Scripted objects render through
  `RenderPlanner.overlays(scriptRenderer:)`, supplied by MediaKit.
- Compiles are serialised in `EditorModel.scheduleCompile` (in-flight + pending flag). Do not
  reintroduce cancel-and-restart: detached imports cannot be cancelled.
- `swift test` sometimes links stale test objects after a signature change — `touch` the dependent
  test files.

## Fastest real-data check
`swift run onboard render --project X --range a:b --preset 1080p --fps 10`, then
`ffmpeg -ss 0.5 -frames:v 1` on the output. Same compositor as the preview.
`swift run onboard render --template "<built-in name>"` eyeballs a template.
`swift run onboard bench --export --codec hevc --seconds 60` for speed and memory.
Baseline on Apple silicon: 4K HEVC ≈ 1.9× real time, 1080p ≈ 3.7×, overlays ≈ 5 ms/frame at 1080p.
CI runs the script frame budget about 2× slower.

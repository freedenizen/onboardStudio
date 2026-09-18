# OverlayGen

A modern, native macOS app for combining onboard video with telemetry data — GPS, data loggers,
lap timers — into finished videos with data-driven overlays: gauges, track maps, g-force plots,
lap timers, graphs, and more. A reimplementation of the classic RaceRender 3 workflow using
Swift 6, SwiftUI, and AVFoundation.

**Status:** early development (milestone M9: templates and export options). The app opens `.overlayproj` documents with a live preview, sync wizard and export (presets up to 4K and vertical, H.264/HEVC, ProRes 4444 or HEVC with alpha for overlay-only output over a key colour or transparency, whole/time-span/lap-range export); projects can be saved as and created from templates; missing media is reported per input and relinked in place; a timeline strip holds segments in which objects can be shown, hidden, moved or faded (camera switching, picture-in-picture, split and quad layouts from presets), with per-property inherit/override badges; the Gauge Designer covers needle/dual-needle/arc styles, sweep and direction, needle geometry, ticks and labels, colour zones with gradients, face images and needle smoothing; Bar, Graph (time/distance/lap-vs-best), Gear, Lap Counter, seven timer modes and formatted Text Data join the object set, and object styles can be copied, pasted, imported and exported; video inputs support rotation, mirror, crop, colour adjustments, chroma key and audio mixing; data inputs support channel mapping, resampling, smoothing, calculated fields and a start/finish-line lap editor. `overlaygen probe` reads RaceRender CSV, RaceChrono Pro CSV and GPX files (`docs/formats.md`); `overlaygen render --project` renders a project with speedometer, track map, g-force, lap timer and text readouts (`docs/project-format.md`). See `docs/testing.md` for how to verify each milestone. See `docs/architecture.md` for the
design and roadmap.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel Mac
- Optional: `ffmpeg` (`brew install ffmpeg`) for importing containers macOS can't open natively

## Building

Libraries, tests, and the command-line tool build with Swift Package Manager alone:

```sh
swift build
swift test
swift run overlaygen --help
```

The app bundle is built from an Xcode project generated with XcodeGen:

```sh
brew install xcodegen
xcodegen generate
open OverlayGen.xcodeproj
```

Or from the command line:

```sh
Scripts/bundle-app.sh        # builds dist/OverlayGen.app
Scripts/make-dmg.sh          # builds dist/OverlayGen-<version>.dmg
```

## Installing

Download the latest `OverlayGen-<version>.dmg` from the
[Releases page](https://github.com/freedenizen/overlayGen/releases), open it and drag OverlayGen
to Applications. Releases from v0.2.3 onward are signed with a Developer ID certificate and
notarized by Apple, so the app opens with a normal double-click and updates itself through
**OverlayGen ▸ Check for Updates…**.

Earlier builds (v0.1.0 – v0.2.2) were unsigned test builds; they cannot self-update to a signed
release, so replace them by installing the current DMG once.

## License

MIT — see `LICENSE`. Third-party components are listed in `docs/third-party.md`.

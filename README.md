# OverlayGen

A modern, native macOS app for combining onboard video with telemetry data — GPS, data loggers,
lap timers — into finished videos with data-driven overlays: gauges, track maps, g-force plots,
lap timers, graphs, and more. A reimplementation of the classic RaceRender 3 workflow using
Swift 6, SwiftUI, and AVFoundation.

**Status:** early development (milestone M3: project file and first display objects; no GUI yet). `overlaygen probe` reads RaceRender CSV, RaceChrono Pro CSV and GPX files (`docs/formats.md`); `overlaygen render --project` renders a project with speedometer, track map, g-force, lap timer and text readouts (`docs/project-format.md`). See `docs/testing.md` for how to verify each milestone. See `docs/architecture.md` for the
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

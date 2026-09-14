# OverlayGen

A modern, native macOS app for combining onboard video with telemetry data — GPS, data loggers,
lap timers — into finished videos with data-driven overlays: gauges, track maps, g-force plots,
lap timers, graphs, and more. A reimplementation of the classic RaceRender 3 workflow using
Swift 6, SwiftUI, and AVFoundation.

**Status:** early development (milestone M2: media pipeline). `overlaygen probe` reads RaceRender CSV, RaceChrono Pro CSV and GPX files (`docs/formats.md`); `overlaygen render` re-encodes video through the AVFoundation compositor. See `docs/testing.md` for how to verify each milestone. See `docs/architecture.md` for the
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

## Installing an unsigned build

Builds that are not signed with an Apple Developer ID are blocked by Gatekeeper on first launch.
Either right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/OverlayGen.app
```

## License

MIT — see `LICENSE`. Third-party components are listed in `docs/third-party.md`.

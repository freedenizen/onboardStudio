# OverlayGen

A modern, native macOS app for combining onboard video with telemetry data — GPS, data loggers,
lap timers — into finished videos with data-driven overlays: gauges, track maps, g-force plots,
lap timers, graphs, and more. A reimplementation of the classic RaceRender 3 workflow using
Swift 6, SwiftUI, and AVFoundation.

**New here?** Read the [User Guide](docs/user-guide.md), or open **Help ▸ Open the Sample Project** in the app.

**Status:** feature-complete against the RaceRender 3 checklist (milestone M14: performance, hardening, parity audit; see `docs/parity.md` for what is and is not covered). On Apple silicon a 4K HEVC export of a HERO13 clip with eleven overlays runs at about twice real time with flat memory; `overlaygen bench` measures it, and fuzz suites mutate every supported file format against the importers. A data log can be synced to the video without any clocks by correlating the video's motion with the log's speed (**Auto-Sync by Motion**, `overlaygen sync`); finished exports upload to YouTube with a device-code sign-in and resumable transfer (`docs/youtube.md`); DJI `.SRT` logs import and, like Garmin FIT and GPX files next to a clip, are offered as sidecar data, with DJI and Sony sidecar clocks feeding timestamp sync. Fisheye and 360° equirectangular footage can be unwrapped into a flat, pannable view per video input (Lens section; a runtime-compiled Metal kernel), exports can be tagged as spherical video for YouTube and 360° players, and the track map can draw a second vehicle from another data input and show Apple Maps imagery (map, satellite, hybrid) behind the outline. Script objects draw with JavaScript against a canvas and data API (with RaceRender-style helper names), edited live in the inspector with error badges instead of crashes (`docs/scripting.md`). GoPro recordings' embedded GPS, accelerometer and gyro data can be used directly (**Use Embedded GPS**), Garmin FIT activities import, and data files with a clock sync to the video automatically from timestamps. The app opens `.overlayproj` documents with a live preview, sync wizard and export (presets up to 4K and vertical, H.264/HEVC, ProRes 4444 or HEVC with alpha for overlay-only output over a key colour or transparency, whole/time-span/lap-range export); projects can be saved as and created from templates; missing media is reported per input and relinked in place; a timeline strip holds segments in which objects can be shown, hidden, moved or faded (camera switching, picture-in-picture, split and quad layouts from presets), with per-property inherit/override badges; the Gauge Designer covers needle/dual-needle/arc styles, sweep and direction, needle geometry, ticks and labels, colour zones with gradients, face images and needle smoothing; Bar, Graph (time/distance/lap-vs-best), Gear, Lap Counter, seven timer modes and formatted Text Data join the object set, and object styles can be copied, pasted, imported and exported; video inputs support rotation, mirror, crop, colour adjustments, chroma key and audio mixing; data inputs support channel mapping, resampling, smoothing, calculated fields and a start/finish-line lap editor. `overlaygen probe` reads RaceRender CSV, RaceChrono Pro CSV and GPX files (`docs/formats.md`); `overlaygen render --project` renders a project with speedometer, track map, g-force, lap timer and text readouts (`docs/project-format.md`). See `docs/testing.md` for how to verify each milestone and `docs/user-journeys.md` for the user journeys the XCUITest suite (`Scripts/ui-tests.sh`) drives through the real app. See `docs/architecture.md` for the
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

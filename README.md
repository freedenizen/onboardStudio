<div align="center">

<img src="docs/images/app-icon.png" width="128" alt="Onboard Studio app icon">

# Onboard Studio

**Turn your onboard video and lap data into a finished track-day film.**

A native Mac app that lays speedometers, track maps, g-force plots and lap timers
over footage from your camera, driven by the data your logger recorded.

[Download](#download) · [User Guide](docs/user-guide.md) · [What's new](https://github.com/freedenizen/onboardStudio/releases)

</div>

---

> [!WARNING]
> **Onboard Studio is early alpha software.** It is under active development, has not been
> through a public beta, and is not yet at version 1.0. Expect rough edges, changes that
> break older project files, and occasional bugs.
>
> **Keep your original video and data files.** Onboard Studio never modifies them, but
> please do not treat a project file as the only copy of anything you care about.
>
> Bug reports and suggestions are very welcome —
> [open an issue](https://github.com/freedenizen/onboardStudio/issues/new).

## What it does

You come home from a track day with two things: video from a camera, and a data log from a
lap timer or GPS logger. Onboard Studio puts them together.

- **Line the two up.** Onboard Studio can sync your data to your video automatically — from
  the clocks in the files, or, when there are no clocks, by matching the motion in the
  picture to the speed in the log. No counting frames.
- **Drop gauges on top.** Speedometer, tachometer, track map, g-force plot, lap timer,
  bar and line graphs, gear indicator, lap counter and free text. Start from a template
  and move things around, or design a gauge face from scratch.
- **Cut between cameras.** Put a second camera picture-in-picture, split the screen, or
  switch between angles partway through.
- **Export a finished video.** Up to 4K, including vertical for phones. Upload straight to
  YouTube, or export just the overlays with a transparent background to drop into Final
  Cut or Premiere.

Everything binds to whatever data you actually loaded — Onboard Studio does not assume your
logger names things a particular way.

### What it reads

**Cameras** — GoPro (including the GPS, accelerometer and gyro recorded inside the video
file), DJI, Sony, Garmin VIRB, and anything else your Mac can play. Fisheye and 360°
footage can be flattened into a normal, pannable view.

**Loggers and apps** — RaceChrono and RaceChrono Pro, RaceRender, Harry's LapTimer,
TrackAddict, Racelogic VBO, Garmin FIT, GPX, TCX, NMEA, DJI `.SRT`, and plain CSV from
almost anything else.

Full details in [docs/formats.md](docs/formats.md).

## Download

**[⬇ Download the latest release](https://github.com/freedenizen/onboardStudio/releases/latest)**

Grab the `OnboardStudio-<version>.dmg`, open it, and drag **Onboard Studio** to your
Applications folder. That's it — the app is signed and notarized by Apple, so it opens with
a normal double-click.

Once installed, it keeps itself up to date: **Onboard Studio ▸ Check for Updates…**

### Requirements

- macOS 15 (Sequoia) or later
- Any Mac from the last several years — Apple Silicon or Intel
- Optional: [ffmpeg](https://ffmpeg.org) (`brew install ffmpeg`), only needed for unusual
  video formats macOS can't open on its own

### Upgrading from OverlayGen

This app used to be called **OverlayGen**. If you have it installed, download the new DMG
and install it once — the automatic updater does not carry across the rename.

Your work comes with you. Existing `.overlayproj` projects, templates and object styles
still open, and your settings and saved templates are migrated the first time Onboard
Studio launches. Projects you save from now on use the new `.onboardproj` extension.

## Getting started

The fastest way in is the sample project — it opens with video, data and overlays already
set up, so you can see how the pieces fit:

**Help ▸ Open the Sample Project**

From there, the [User Guide](docs/user-guide.md) walks through your first overlay in about
five minutes, then covers videos, data, objects, timeline segments and exporting.

If something looks wrong, the guide's
[troubleshooting section](docs/user-guide.md#9-troubleshooting) covers the usual causes.

## What's new

Release notes for every version are on the
[Releases page](https://github.com/freedenizen/onboardStudio/releases), newest first. The
app is at **v0.19.0**; version numbers below 1.0 mean the file format and the interface can
still change between releases.

## For developers

Onboard Studio is written in Swift 6 with SwiftUI and AVFoundation, and is a reimplementation
of the classic RaceRender 3 workflow as a native Mac app. The libraries, tests and the
`onboard` command-line tool build with Swift Package Manager alone:

```sh
swift build
swift test
swift run onboard --help
```

The app bundle is built from an Xcode project generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open OnboardStudio.xcodeproj
```

Or from the command line — `Scripts/bundle-app.sh` builds `dist/OnboardStudio.app`, and
`Scripts/make-dmg.sh` packages it into a DMG.

Further reading: [CONTRIBUTING.md](CONTRIBUTING.md) to get set up,
[docs/architecture.md](docs/architecture.md) for how it fits together,
[docs/landscape.md](docs/landscape.md) for how it compares with RaceChrono Pro, TrackAddict,
VBOX and AiM, [docs/scripting.md](docs/scripting.md) for overlay objects that draw with
JavaScript, and [docs/project-format.md](docs/project-format.md) for what's inside a project
file.

## License

MIT — see [LICENSE](LICENSE). Third-party components are listed in
[docs/third-party.md](docs/third-party.md).

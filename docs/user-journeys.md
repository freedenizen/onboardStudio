# User journeys and the UI test suite

The journeys below are the ways people actually use a telemetry-overlay editor. They come from
this app's own guide, from the manuals of the tools it replaces or sits next to, and from the
community guides written for those tools. Each journey lists what the user does, what they expect,
and which automated test covers it: an XCUITest in `UITests/OnboardStudioUITests` that drives the
real app through its windows, menus and inspectors, a unit test on the model, or a manual QA script
under `docs/qa-*.md` for the steps no automation can reach (file panels, drag-and-drop from Finder).

Sources: the Onboard Studio [user guide](user-guide.md); RaceRender 3's
[Basics](https://racerender.com/RR3/docs/Basics.html),
[How To: Data Overlay](https://racerender.com/RR3/docs/HowTo-Datalogger.html),
[Sync Tool](https://racerender.com/RR3/docs/InputFileSync.html) and
[Create Video File](https://racerender.com/RR3/docs/CreateVideo.html) pages; the
[Autosport Labs RaceRender guide](https://wiki.autosportlabs.com/RaceCapture_RaceRender_Guide);
RaceChrono's tutorials on [linking and syncing video](https://racechrono.com/article/480),
[exporting an overlaid video](https://racechrono.com/article/2083) and
[picture-in-picture export](https://racechrono.com/article/2721);
[Telemetry Overlay](https://goprotelemetryextractor.com/telemetry-overlay-gps-video-sensors)
(merging consecutive files, activity presets, transparent exports) and the
[DashWare](http://www.dashware.net/faq/) sync-tab workflow.

## Running the UI tests

```sh
Scripts/ui-tests.sh            # xcodegen + xcodebuild test, results in build/UITests.xcresult
Scripts/ui-tests.sh Journeys   # one test class
```

The app is launched with `-uiTesting YES`, which adds a **Testing** menu whose items add the
fixture files from `Tests/Fixtures` (the open panels cannot be driven), and with
`ONBOARD_TEST_EXPORT_DIR` so the export sheet writes without a save panel. Everything else is
the ordinary UI: toolbar, sidebar, inspector, transport, timeline, menus and sheets. Controls that
have no text carry accessibility identifiers (`toolbar.addVideo`, `transport.play`,
`object.Speed`, `tour.next`, `export.start`…); text controls are found by their titles, so a
renamed button fails the test that reads it, which is the point.

CI runs the suite in the **UI tests** job on every push to `main` and every pull request that is not
a draft, and keeps the `.xcresult`
as an artifact when it fails (screenshots and the accessibility hierarchy are inside).

## Journeys

Each journey is a file of its own in [journeys/](journeys/), named by its number
(`J15-choose-the-fonts.md`), so that adding one adds a file rather than editing a list every
other change is editing too (#237). A journey says where it came from, what the user does and
expects, and the tests that drive it.

## What stays manual

Open and save panels (Export… and Import Template…), opening a template from the Finder,
drag-and-drop from Finder, the Apple Maps background (network), Sparkle
updates, the real GoPro/RaceChrono sample files (local only), and anything that needs a second
machine (YouTube). These keep their scripts in the `docs/qa-m*.md` files.

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

CI runs the suite in the **UI tests** job on every push and pull request and keeps the `.xcresult`
as an artifact when it fails (screenshots and the accessibility hierarchy are inside).

## Journeys

### J1 First launch: the app explains itself
*Source: guide §1; RaceRender's New Project menu; DashWare's project wizard.*

1. Launch. The welcome window offers a blank project, a project from a template, Open Project…,
   recent projects and the sample project; no file panel and no project appear until one is
   chosen. A blank **Untitled** project shows the welcome panel (Add Video…, Open the Sample
   Project, User Guide) and the Getting Started checklist in the inspector.
2. The first time, the three-step tour appears; **Next**, **Next**, **Done** dismiss it and it
   does not return on the next launch. **Help ▸ Take the Tour** brings it back.
3. **Help ▸ Keyboard Shortcuts** opens the shortcuts window.

Tests: `LauncherUITests` (blank project, from a template, reopening the window),
`FirstLaunchUITests.testWelcomeAndGettingStarted`, `testTourStepsThroughAndCanBeRepeated`,
`testShortcutsWindowOpens`.

### J2 Track day: GoPro clip + RaceChrono log, gauges, export
*Source: guide §1; RaceRender How To: Data Overlay; Autosport Labs guide; RaceChrono export
tutorial.*

1. Add the video. The sidebar lists it with its size and length; the timeline shows one bar; the
   preview leaves the welcome panel.
2. Add the data file. The sidebar shows the format, channel count and laps; the Getting Started
   checklist ticks "Add a video" and "Add the data".
3. **Project ▸ Apply Template ▸ Classic Dash**: speedometer, tachometer, map, g-force, lap timer,
   best lap and gear appear in the sidebar and on the preview.
4. Play, pause, step, go to start: the transport time changes accordingly.
5. Export: the sheet offers presets, range and background; Export… writes the file and offers
   **Reveal in Finder**. The file exists and has the expected size and duration.

Tests: `JourneyUITests.testTrackDayFromVideoToExport`. Model: `ClipSequenceTests`,
`ExportOptionsTests`; the CLI renders the same fixture project in CI (`onboard render`).

### J3 Start from a template, then add the media
*Source: RaceRender templates; Telemetry Overlay activity presets; regression for the 0.16.2 bug.*

1. **File ▸ New from Template ▸ Classic Dash** opens a new document already listing the gauges.
2. Add the video, then the data. The gauges bind to them (the speedometer's inspector names the
   data input's channel) instead of staying orphaned.
3. Adding the same video file again is refused (status line "…is already part of…"); a different
   recording opens its own lane after the first rather than stacking on top of it.

Tests: `TemplateUITests.testNewFromTemplateThenMedia`, `testAddingTheSameFileTwiceIsRefused`.
Model: `InputPlanningTests`, `TemplateExportTests`.

### J3a Mark the moments worth coming back to
*Source: Resolve and Premiere marker models; see `docs/conventions.md`.*

1. With a video loaded, **Marker ▸ Add Marker** (**M**) drops a numbered marker at the playhead.
2. It appears in the timeline's marker lane and in the sidebar's **Markers** list.
3. **Previous/Next Marker** (**⇧↑** / **⇧↓**) walk between them, reporting each in the status
   line; past the last one the status line says so rather than jumping to the start.
4. **Delete Marker** removes the selected one, and **Undo** brings it back.

Tests: `MarkerUITests.testMarkersAreAddedListedAndJumpedBetween`. Model: `MarkerTests`.

### J3b Trim a video to the playhead
*Source: Resolve Trim Start / Trim End (`⇧[` / `⇧]`), verified in `docs/conventions.md`.*

1. Select a video in the sidebar. With the playhead at the very start there is nothing to drop,
   and the status line says so rather than silently doing nothing.
2. Step a few frames in with `.` and **Project ▸ Trim Start to Playhead**; the input's start
   position follows the playhead.
3. **Undo** puts it back. Nothing touches the file on disk.

Tests: `TrimUITests.testTrimsAVideoToThePlayheadAndRefusesWhenItCannot`. Model:
`VideoEditingModelTests` ("Timeline trimming arithmetic").

### J3c Jump between laps
*Source: RaceChrono and TrackAddict both list laps and seek to them.*

1. With a video and a data file loaded, the data gets its own timeline bar with a divider at each
   lap boundary.
2. **Marker ▸ Next Lap** (**⌥↓**) moves to the next lap and names it in the status line with its
   time; **Previous Lap** (**⌥↑**) goes back.
3. Before the first lap the status line says there is no lap that way rather than sitting silent.

Tests: `LapUITests.testJumpsBetweenTheLapsOfTheDataFile`. Model: `LapNavigationTests`.

### J3d Split a video at the playhead
*Source: Resolve Split Clip (`⌘\`), verified in `docs/conventions.md`.*

1. Select a video. At the very edge there is no second half to make and the status line says so.
2. Step in and **Project ▸ Split at Playhead**. The sidebar gains a second input *and* a second
   camera object, and the timeline gains a segment that swaps them at the cut.
3. **Undo** removes all of it in one step.

Tests: `SplitUITests.testSplitsAVideoIntoTwoHalvesThatSwapAtTheCut`. Model: `VideoSplitTests`.

### J3e Trim and split a data file
*Source: #54 — the same editing verbs applied to data, not just video.*

1. Select the data input and step the playhead in. **Project ▸ Trim Start to Playhead** moves the
   data's own trim, shown in seconds in the inspector's *Trim* section.
2. **Undo**, then **Project ▸ Split at Playhead** gives a second data input, with the gauges
   reading it duplicated so they keep drawing after the cut.
3. **Undo** removes the split in one step.

Tests: `DataEditingUITests.testTrimsAndSplitsTheDataFile`. Model: `SessionTrimTests`.

### J4 Sync the data to the picture by hand
*Source: RaceRender Sync Tool and Data Sync Wizard; DashWare synchronisation tab; RaceChrono
"Adjusting video synchronisation".*

1. With a video and a data file, open **Sync** from the toolbar.
2. A panel appears **under the preview**, not over it: the data file, live readouts of what the
   data says at the moment on screen, and nudge buttons for the data and for the video
   (−1s / −.1 / −1f / +1f / +.1 / +1s, where a frame comes from the project's rate).
3. Each nudge applies immediately and is its own undo step, so the loop is nudge, look at the
   picture, nudge again. The rest of the window stays usable throughout.
4. Nudge the data by +1s then +1f; the data input's Synchronization section shows the new offset.
   **Undo** steps back one nudge at a time.

Tests: `SyncUITests.testSyncPanelNudgesLiveAndLeavesTheWindowUsable`,
`SyncUITests.testSyncPanelAlsoMovesTheVideo`. Model: `TimestampSyncTests`, `MotionSyncTests`.

### J5 Edit the overlay: add, select, tune, hide, delete, undo
*Source: guide §5; RaceRender display objects and properties; Telemetry Overlay gauge editing.*

1. **Add Object ▸ Speedometer** adds a gauge bound to the data input; it is selected and its
   inspector shows the Gauge Designer with the channel picker.
2. Rename it in the inspector; the sidebar follows.
3. Change the channel; pick a different speed unit.
4. The eye toggles visibility; the sidebar label reflects it.
5. **Project ▸ Delete Selected Object** removes it; **⌘Z** brings it back; **⇧⌘Z** removes it
   again.

Tests: `ObjectEditingUITests.testAddRenameRetuneHideDeleteUndo`.

### J6 Warning lights that fit any logger
*Source: RaceRender "Enhanced Display" lights; this app's indicator design.*

1. **Add Object ▸ ABS Light** on a log with no ABS channel: the inspector warns "This object needs
   a channel".
2. Pick a channel; the inspector shows the channel's range in this file and **Suggest** sets the
   threshold to its midpoint.

Tests: `ObjectEditingUITests.testIndicatorLightAsksForAChannelAndSuggestsAThreshold`. Model:
`IndicatorParamsTests`.

### J7 Two cameras, picture-in-picture, camera switching
*Source: RaceRender multi-camera; RaceChrono PiP export; guide §3 and §6.*

1. Add the main video, then **Project ▸ Add Camera…** with a second file: a second lane and a
   picture-in-picture window appear.
2. **Layout ▸ Side by side** re-frames both cameras.
3. **Layout ▸ Add Segment at Playhead** (after stepping forward) adds a segment; the segment strip
   shows it and the inspector lists it.

Tests: `MultiCameraUITests.testSecondCameraLayoutsAndSegments`. Model: `TimelineTests`,
`TimelineMediaTests`.

### J8 Timeline: zoom, snapping, scrub
*Source: DaVinci Resolve timeline conventions adopted in M16; guide §2.*

1. Zoom in with the transport button and ⌘=; zoom to fit returns to 1×.
2. Toggle snapping with the magnet and with N.
3. Step forward changes the transport time; Go to start returns to 0:00.00.

Tests: `TimelineUITests.testZoomSnapAndTransport`. Model: `ClipModelTests` (snapping),
`VideoTrimmingTests`.

### J9 Open, edit and save an existing project
*Source: any document app; guide §2.*

1. Open the fixture project (a video with five gauges and a data file with a 1 s offset). The
   sidebar lists its inputs and objects and the preview renders.
2. Hide an object and save with ⌘S; the window title loses its Edited mark.
3. Close and reopen: the object is still hidden.

Tests: `ProjectUITests.testOpenEditSaveReopen` (opens through the Testing menu, saves in place).

### J10 Camera-only telemetry and sidecars
*Source: guide §1 step 3; Telemetry Overlay's embedded-telemetry import; RaceChrono's automatic
GPS sync.*

Use Embedded GPS on a GoPro clip, Use Sidecar Data for DJI/Garmin logs, timestamp auto-sync. The
fixtures hold no real GoPro footage, so this journey is covered by the unit tests
(`GPMFKitTests`, `TimestampSyncTests`, `CompanionTelemetry` tests) and the manual script in
`docs/qa-m10.md` / `docs/qa-m13.md` with the local sample files.

### J11 Overlay-only export for another editor
*Source: RaceChrono alpha-matte export; Telemetry Overlay transparent exports; the user's own
RaceRender → Resolve workflow.*

1. Export with **Behind the overlays: Transparent** and the HEVC-with-alpha codec (`.mov`).
2. The file exists and its extension is `.mov`.

Tests: `JourneyUITests.testTransparentOverlayExport`. Model: `ExportOptionsTests`.

### J12 Share to YouTube
*Source: RaceRender's YouTube upload; guide §7.*

The upload sheet needs a Google sign-in, so the UI test only checks that **Upload to YouTube…**
appears after an export and opens the sheet; the upload itself is covered by `YouTubeKitTests`
against a mock server.

### J13 Tell the app what your channels mean
*Source: #111, #89, #191, #192 — attributes are the app's words for what a value means, and every
logger names its channels differently.*

1. Add a data file, select it and choose **Project ▸ Map Attributes…** (⌥⌘A) or **Map
   Attributes…** in its inspector. The window opens on that file and lists one row per
   attribute, not per column, so nothing in it depends on which logger wrote the file.
2. The sidebar chooses the level: all projects, this project, or this input.
3. A row nobody has touched still says which column feeds it — the placeholder reads
   `Automatic (speed)` — so it is clear what the importer matched.
4. Point **Brake pressure (front)** at the `brake_pressure_front` column by typing into *From*,
   set *Shows* to `bar`, and the row reports `kPa → bar`.
5. An attribute the file does not supply stays out of the way until *Show every attribute*.
6. A channel the file names itself — `canbus:analog_1` — is offered as a **source**, never as a
   row of its own.
7. **All of it from the keyboard** (#200): ⌘F, type `pressure (front)`, Return lands in that row's
   *From* field, type `brake_pressure_front` and Return. Tab walks the rows in reading order and
   Escape abandons a half-typed column.

Tests: `AttributeMappingUITests` (mapping units, hiding unsupplied attributes, the scope sidebar,
the resolved source, `testTabWalksTheTableInReadingOrder`,
`testFilterAndReturnMapAnAttributeWithoutTheMouse`, `testEscapeAbandonsATypedColumn`,
`testTheShortcutOpensTheWindowOnTheSelectedFile`),
`ImportReportUITests.testAPressureAttributeIsMappedToAColumnAndShownInBar`,
`testASourceChannelIsNotListedAsAnAttribute`. Model: `AttributeMappingTests`,
`AttributeVocabularyTests`, `DisplayUnitTests`, `AttributeFilterTests`, `AttributeMappingScopeTests`.

### J14 Find out why a file imported badly
*Source: #149 — the channel list shows what survived and says nothing about what did not.*

1. Add a file whose columns are awkward — repeated names, unnamed analog inputs, sensors that
   never move. Its inspector says in a line how the import went; choose **Project ▸ Show Import
   Report…**, or ⌘2 in the attribute window, for the whole report.
2. It shows only the columns worth a look: which of three columns called `speed` kept the role,
   which read the same number all session, which units were not recognised.
3. *Show every column* lists the rest; a file that read cleanly says so in one line.

Tests: `ImportReportUITests.testExplainsWhatBecameOfEachColumn`,
`testCommandDigitsSwitchTheWindowsView`, `testShowImportReportOpensOnTheReport`,
`testTheDataInspectorHasOneWayToTheAttributes`. Model:
`ImportReportTests`, `ImportReportNotesTests`, `AttributeFilterTests`.

## What stays manual

Open and save panels, drag-and-drop from Finder, the Apple Maps background (network), Sparkle
updates, the real GoPro/RaceChrono sample files (local only), and anything that needs a second
machine (YouTube). These keep their scripts in the `docs/qa-m*.md` files.

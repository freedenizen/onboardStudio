# QA script — M4 app MVP

Build and launch (`xcodegen generate && open OverlayGen.xcodeproj`, run the OverlayGen scheme, or
install the release DMG). Have a video clip and a matching data file to hand; the fixtures
`Tests/Fixtures/test-3s.mp4` + `Tests/Fixtures/racerender-basic.csv` work for a smoke test.

| # | Step | Expected |
|---|---|---|
| 1 | Launch the app | Open panel appears; **File ▸ New** creates an empty editor window with sidebar, black preview, transport and inspector |
| 2 | Toolbar **Add Video** (⌘I), choose a clip | Input appears in the sidebar with size/duration; preview shows the first frame; transport enabled |
| 3 | Press **space**, then again | Video plays with audio and pauses; time readout advances; slider follows |
| 4 | Drag the slider, use ◀︎ ▶︎ frame buttons | Frame-accurate scrubbing; time readout changes per frame |
| 5 | Toolbar **Add Data**, choose a CSV/GPX | Input appears with format, channel and lap counts |
| 6 | **Add Object ▸ Speedometer** | Gauge appears bottom-right of the preview with a needle that moves during playback |
| 7 | Add Track Map, G-Force, Lap Timer, Text Data | Each appears in a distinct spot; sidebar lists them top-most first |
| 8 | Drag a gauge on the preview | It moves; the inspector X/Y update; **Edit ▸ Undo** puts it back |
| 9 | Drag a corner handle, then with ⇧ held | Resizes; with ⇧ the aspect ratio is kept |
| 10 | Select the Text Data object, change **Channel** and **Caption** in the inspector | Readout updates immediately on the paused frame |
| 11 | Select the speedometer, set **Maximum** to 200 and **Speed unit** to kph | Scale relabels; readout changes to kph |
| 12 | Scrub to a recognisable moment, click **Sync** | Wizard opens with the project time; slider scrubs the data with live readouts; **Apply** sets the input's start position (visible in the input inspector) |
| 13 | Toggle an object's eye icon in the sidebar | Object disappears from preview; toggling again restores it |
| 14 | ⌘S, choose a name | `Name.overlayproj` package is written; **File ▸ Close** then reopen it via **File ▸ Open** | All inputs and objects restored, playback works |
| 15 | **Export** (⌘E), keep project size, click **Export…**, pick a path | Progress bar advances; **Reveal in Finder** shows an MP4 that plays in QuickTime with the overlays identical to the preview |
| 16 | Start an export, click **Cancel** | Export stops; message says cancelled; no stray file plays |
| 17 | Remove the data input via its context menu | Data-driven objects are removed with it; video remains |
| 18 | Quit and relaunch, **File ▸ Open Recent** | Project reopens |

Known limits in M4: no timeline segments, one video layer per project frame, no trim/crop/colour
controls (M5), no lap-detection editor (M6), no gauge designer (M7).

# QA script — M16 timeline editing (Resolve-style), chapters, drops, tour

| # | Step | Expected |
|---|---|---|
| 1 | First launch after this version | A three-step tour appears over the window; Next/Done walks through sidebar, timeline and inspector; **Help ▸ Take the Tour** repeats it |
| 2 | Drop `GX010037.MP4` and `GX020037.MP4` together onto the window | One video input; the status line says the chapter was joined; *Clips* lists both files |
| 3 | Drop a `.csv` and a `.png` | A data input (auto-synced when it has a clock) and an image input appear |
| 4 | In *Clips*, set the second clip's In to 10 and Gap before to 2 | The sequence shortens by 10 s and grows by 2 s; scrubbing into the gap shows black |
| 5 | Timeline: ⌘= three times, scroll sideways, ⇧Z | The ruler labels tighten, the lanes scroll, then everything fits again |
| 6 | Drag a video bar's right edge left | The bar shortens; *Synchronization* shows the new end; the trim end is set in the input |
| 7 | Drag the same bar's left edge right | The bar starts later and the picture at the new start is what used to be there (head trim keeps the picture in place) |
| 8 | Drag a bar towards another bar's end with the magnet on, then off (N) | It snaps to the edge; without the magnet it lands where dropped |
| 9 | Project inspector: Zoom 1.5, Position X 30 | Every video zooms and shifts right; the number fields and sliders agree |
| 10 | Save, reopen an M15 project with `{ "path": … }` clips | The clips still load |

## Results (0.14.0, real GoPro chapters GX010037 + GX020037, second camera = GX020037 again)

- **Tour**: Help ▸ Take the Tour shows the three callouts (sidebar, timeline, inspector) with Skip/Next/Done; the first-run tour appears in the first window that opens (with several restored windows that may be a background one). The AppKit video view is not dimmed by the overlay; the callouts are.
- **Timeline**: ruler labels 0:00…40:00 at fit; the transport's + button zooms to 2:00 spacing and the lanes scroll; the fit button restores. The View menu now carries Zoom In/Out/Fit and Snapping (a first build had created a second "View" menu; fixed).
- **Tail trim**: dragging the second camera's right edge left shortened it and the project from 40:53 to 37:46; the input's trim end was set.
- **Head trim**: the scripted drag kept landing on the adjacent bar's tail handle (the two bars touch, and both edges have 8 pt handles), so the head arithmetic was moved into `VideoTrimming` and verified by unit test: dragging a head from 10 s to 14 s at double speed advances the file start by 8 s, so the picture at the new head is what used to be there.
- **Chapters and drops**: GX020037 loads as a clip of GX010037 (summed 1427.95 s). Drag-and-drop from the Finder and the silent join on Add Video go through system drag/open panels the scripted QA cannot drive; they are covered by `CameraChapters.group` tests and code review.
- **Per-clip fields**: In/Out/Gap appear under each clip in *Clips*; `ClipEditingTests` verify the composition (gap renders black, trims map to the right file seconds) and that a rotated chapter keeps its own orientation.
- **Transform (all videos)**: Zoom with a number field, Position X/Y as −100…100 offsets (disabled at zoom 1), Cropping in its own section with Reset, mirroring Resolve's Inspector layout.

## 0.16.2 follow-up: New from Template, then two videos and the data

| # | Step | Expected |
|---|---|---|
| A | **File ▸ New from Template ▸ Classic Dash** | The new window lists Camera, Speed, RPM, Map, G, Lap, Best, Gear (unbound until inputs arrive; nothing renders yet) |
| B | **Add Video…** with the first chapter of a recording, then **Add Video…** with its second chapter | The second add is refused with "…is already part of…" in the status line; the lane shows one bar with both chapters |
| C | **Add Video…** with the next recording of the same camera | It joins the same lane after the first (the status line says so); a moment later the status line reports the gap set from the camera clock and the Clips section shows it in *Gap before* |
| D | **Add Data File…** | The template's gauges bind to the log and render; the timing sync runs as usual |
| E | **Project ▸ Add Camera…** with a file from another camera | A new lane and a picture-in-picture window bottom-right |

Results (0.16.2): step A verified in the app (File ▸ New from Template ▸ Classic Dash lists Camera, Speed, RPM, Map,
G, Lap, Best and Gear on the new Untitled document; before the fix the template was handed over after the window had
already appeared). Steps B–E go through open panels, which the scripted run cannot drive; `InputPlanningTests` and
`RecordingGapsTests` cover their model logic, and on the Sonoma files
`GX010030 → GX020030` (chapters) measured a pause under 2 s and `GX010030 → GX010031` (separate recordings) a
pause of minutes, so the lane gets a gap only between recordings.

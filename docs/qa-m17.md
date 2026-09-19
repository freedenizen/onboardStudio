# QA script — M17 viewer pan, per-clip speed, timeline overview

| # | Step | Expected |
|---|---|---|
| 1 | Project inspector: Zoom 2.0, then drag the picture in the preview | The cursor is a hand over the picture; the picture follows the drag; Position X/Y change; one undo step per drag |
| 2 | Zoom 1.0 | Dragging the picture does nothing special (object selection as before) |
| 3 | Select the GoPro input, set the second clip's Speed to 2 | The input's duration drops by half the clip's length; playing across the boundary runs the second chapter at double speed with pitched-up audio |
| 4 | ⌘= three times | The strip above the ruler shows a white window for the visible part; drag it right | The zoomed lanes scroll to match |
| 5 | Save, reopen | Speeds survive; M16 projects without `speed` load at 1 |

## Results (0.15.0)

- **Viewer pan** (sample project, zoom dragged to about 1.9×): dragging inside the picture moved it with the pointer and left the Camera object selected; the framing's position changed in one undo step. A first build only panned on empty picture, which never happens with a full-frame video object, so dragging inside a zoomed video object's body now pans while its edge handles still resize.
- **Overview strip** (real GoPro project zoomed 3×): the strip shows both videos and a white window for the visible 0–11:30; dragging the window to the right scrolled the zoomed lanes to 14:00–25:00 with the window tracking.
- **Per-clip speed**: verified by `ClipSpeedTests` (a double-speed second chapter occupies half its length and shows the file's 2 s frame 1 s in); the Speed field sits beside In/Out/Gap under each clip. Not driven by script (typing into Form fields is unreliable in the harness).
- Studied the user's complete RaceRender project (`Track Sessions/Aug 23 2026 Sonoma/Untitled.rrp`, a blue-key overlay with map, deltas, temps, steering wheel, tach, brake/throttle bars) and their Resolve project (two GoPro chapters on V1 under that overlay on V2). The `.rrp` file is a binary `RRP37` format, not text.

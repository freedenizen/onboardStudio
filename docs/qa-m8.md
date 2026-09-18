# QA script — M8 timeline segments and multi-camera

Open a project with two videos (Add Video twice; the second becomes a second Camera object).

| # | Step | Expected |
|---|---|---|
| 1 | Toolbar **Layout ▸ Picture in picture** with the playhead at 0 | The top-most camera fills the frame, the other sits in the top-right corner (written to the objects themselves) |
| 2 | Seek to 0:10, **Layout ▸ Add Segment at Playhead** (⌘K) | A "Segment 1" block appears in the strip under the transport and is selected; the inspector shows its label, start and layout buttons |
| 3 | With the playhead inside the segment, **Layout ▸ Side by side** | Both cameras split the frame from 0:10 on; scrubbing before 0:10 shows the PiP layout again |
| 4 | Select a gauge; in the inspector set **Opacity** 40% | A blue pin appears next to Opacity ("set in this segment"); before 0:10 the gauge is fully opaque |
| 5 | Click the pin | Opacity is inherited again (100%) and the pin turns grey |
| 6 | Drag a gauge on the preview while inside the segment | The move applies only from the segment on; a pin appears on Position & Size |
| 7 | Add a second segment at 0:20 and hide a camera there | The switch is inherited by later time; the first segment is unaffected |
| 8 | Drag the second segment's left edge, or edit **Start** in its inspector | The segment moves and every later segment shifts by the same amount; it cannot pass the previous segment |
| 9 | Play across a segment boundary | The layout changes on the exact frame, no flicker |
| 10 | Export a range spanning the boundary | The exported frame at the boundary matches the preview |
| 11 | **Delete Segment** in the inspector, then ⌘Z | Overrides disappear and return with undo |
| 12 | Save, reopen | Segments, labels and overrides restored |

## Results (0.6.0, real Sonoma project with the GoPro clip loaded twice)

- Picture in picture on the base state, a segment added at 3:12 with side by side: the strip shows Start / Segment 1, the segment inspector lists both cameras as overridden, and scrubbing before the segment restores the inset layout with the footage upright.
- Hiding the speedometer inside the segment shows the blue pin; clicking the pin inherits it again.
- Fixes found on the way: a new segment's start was rounded up past the playhead so the first edits landed on the base objects; a camera hidden at compile time lost its rotation when a later segment showed it (transforms now live on the compiled composition); clicking a segment block now seeks as well as selects.

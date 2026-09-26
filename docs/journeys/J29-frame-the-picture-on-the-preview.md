# J29 Frame the picture on the preview
*Source: #275 — framing was three sliders in the inspector; every editor frames on the picture
itself (Final Cut Pro's Transform, DaVinci Resolve's onscreen controls, iMovie's Crop to Fill).*

1. **View ▸ Frame Picture** (⇧T), the crop button at the left end of the transport, or **Frame on
   Preview** in the project inspector's Frame section. A bar opens above the preview; the preview
   shows the whole shot, overlays put away, with the frame drawn over it and the rest dimmed.
2. Drag a corner of the frame in to zoom (or pinch, ⌥-scroll, or press **+** and **−**); drag inside
   it, or press the arrow keys (⇧ for bigger steps), to move it. The bar and the inspector's Frame
   fields follow; the fields, Undo and Export wait until the session ends, which is one step.
3. **Done** (Return) keeps it, as one step that **Edit ▸ Undo Reframe Videos** takes back;
   **Cancel** (Escape) puts it back as it was, leaving nothing to undo; **Reset** shows the whole
   shot again.

Tests: `FramingUITests` (Cancel restores and leaves nothing to undo; a corner dragged in zooms, and
Done is one undo step; Delete, Undo and Export are held while the tool is open). Model: `FramingEditingTests` (the frame's place, moving and zooming it,
kept inside the picture).

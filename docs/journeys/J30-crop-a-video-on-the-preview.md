# J30 Crop a video on the preview
*Source: #276 — a video's crop was four sliders in the inspector, with no sight of what was being
cut; Final Cut Pro, DaVinci Resolve, iMovie and Photos all crop on the picture.*

1. Select the video; **Crop on Preview** in its Crop section, **View ▸ Crop Picture** (⇧C), or
   the crop button at the left end of the transport. A bar opens above the preview; the preview
   shows the video's whole picture, overlays put away, with the crop drawn over it and what it
   cuts dimmed.
2. Drag an edge or a corner in to cut the picture back, or drag inside to move the crop; the
   arrow keys move it. **Shape** holds it to Freeform, the picture's own shape, 16:9, 9:16, 4:3 or
   Square (a fixed shape is applied at once, as large as it fits). **Rotate Left** and **Rotate
   Right** turn the picture a quarter turn; the flip buttons mirror it.
3. **Done** (Return) keeps it, as one step that **Edit ▸ Undo Crop Video** takes back; **Cancel**
   (Escape) puts it back as it was; **Reset** shows the whole picture again, upright. **Crop |
   Frame** in the bar switches to framing every video without leaving.

Tests: `CroppingUITests` (an edge dragged in and a quarter turn are one undo step; a square is
fitted and Cancel puts it back). Model: `CropEditingTests` (the crop carried through flips and
turns and back, edges found along their length, limits, a window moved whole, a shape held).

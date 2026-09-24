# J24 Export a lap as a vertical clip
*Source: #151 — a clip for a phone meant re-laying the project for 9:16 and setting a time range by
hand, then putting it all back.*

1. Put the playhead anywhere in the lap to share and choose **Project ▸ Export Lap as Vertical
   Clip…** (⇧⌘E). The sheet names the lap, shows its start and end, and a picture of the Social
   layout.
2. Or right-click a marker in the sidebar ▸ **Export as Vertical Clip…**: a range marker exports its
   own range, a point marker the lap it is in.
3. **Export…**: the clip is written as `<project> – Lap N (vertical).mp4`, 1080 × 1920, with a
   lap-following stat card above the picture and the lap timer, speed and map below. The project
   is not changed.
4. **Reveal in Finder**, or **Upload to YouTube…** straight from the sheet.

Tests: `VerticalClipUITests.testTheLapAtThePlayheadExportsAsAVerticalClip`. Model:
`VerticalClipTests`, `LapExportsTests.theLapAtThePlayheadIsTheOneStartingOnTheLine`.

# OverlayGen User Guide

OverlayGen turns a lap video and the data recorded with it into a video with gauges, a track
map, lap timing and anything else you want drawn on top. This guide walks through a first
project and then explains every part of the window. It assumes nothing beyond having a video
and, ideally, a data log.

## 1. Your first overlay in five minutes

1. **Launch OverlayGen.** A new, empty project opens with a welcome panel and, the first time, a
   three-step tour (**Help ▸ Take the Tour** repeats it). Files can be dropped anywhere in the window. (**File ▸ New from
   Template** starts with gauges already laid out, which attach themselves to the video and data
   files you add next; **Help ▸ Open the Sample Project** opens a
   short clip with a synthetic log if you just want to poke around.)
2. **Add the video** (the big button, **⌘I**, or drop it in). If the file is the first chapter of
   a GoPro recording (`GX010037.MP4`, `GX020037.MP4`, …) OverlayGen joins the following chapters
   so they play as one continuous video. Add a second recording the same way and it follows the
   first on the same lane, with the pause between the two recordings kept as a gap (read from the
   camera's clock) so one data log stays lined up across both. A file that is already in the
   project is not added twice. For a second camera to show picture-in-picture use **Project ▸ Add
   Camera…** (**⇧⌘I**), which opens a new lane.
3. **Add the data.** Either **Add Data File…** (**⇧⌘D**) with a RaceChrono export, GPX, FIT, CSV
   or similar, or, for a GoPro clip, select the video and press **Use Embedded GPS** to use the
   GPS, accelerometer and gyro the camera recorded. A DJI or Garmin log next to the clip appears as
   **Use Sidecar Data**.
4. **Line the data up with the video.** When the log has a clock (RaceChrono, GPX, FIT, DJI…)
   this happens automatically the moment the file is added; the status line says which clock was
   used. Otherwise select the data input and press **Auto-Sync by Motion** (matches the video's
   sound and motion against the log's speed) or **Synchronize with Video…** for the manual wizard.
5. **Add gauges.** **Project ▸ Apply Template ▸ Classic Dash** gives a speedometer, tachometer,
   track map, g-force plot and lap timer at once; **Add Object** adds them one by one. Drag objects
   on the preview to move them, drag the handles to resize, and tune them in the inspector on the
   right.
6. **Play** (space) and scrub the timeline to check that the gauges follow the picture. Nudge the
   data with the ±0.1 s buttons in the sync wizard if they lead or lag.
7. **Export** (**⌘E**). Pick a preset (1080p, 4K, vertical…), a range (whole project, a time
   span or a lap range) and press Export. **Upload to YouTube…** appears when it is done.

The **Getting Started** checklist in the inspector tracks these steps and offers the next one;
**Help ▸ Show Getting Started** brings it back after you hide it.

## 2. The window

- **Sidebar (left)**: inputs (videos, data files, images) and display objects, bottom of the list
  is drawn first. Click to select and edit; the eye toggles an object; right-click to remove.
- **Preview (centre)**: the composed frame at the playhead, exactly as it will export. Selected
  objects show handles; arrow keys nudge them (⇧ for bigger steps).
- **Transport and timeline (below the preview)**: play, step, scrub. The timeline has a time
  ruler (click or drag it to scrub), a lane with one bar per video and the segment strip (§6).
  Drag a video bar to move it, drag its left or right edge to trim it (the head trim keeps the
  picture where it was), click it to select the video. The magnet button (N) snaps drags to other
  videos' edges and the playhead; zoom with ⌘= / ⌘− / ⇧Z, the slider next to the transport, or
  scroll sideways. The thin strip above the ruler shows the whole project with a window for the
  visible part; drag it to scroll.
- **Inspector (right)**: settings for the selected input or object. With nothing selected it shows
  the project's output size and frame rate, the camera framing and the Getting Started checklist.
- **Toolbar**: Add Video, Add Data, Add Object, Layout, Sync, Export.

## 3. Videos

**Trim, sync and speed** live in the input's *Synchronization* section: *start position in file*
skips into the recording, *offset in project* delays the video on the project timeline, and *play
speed* slows or speeds it up. **Start After Previous Video** chains a clip onto the one above it in
the list; **Start at 0** resets its offset; the arrow buttons reorder inputs.

**Clip sequences.** The *Clips* section lists the files that make up one continuous video: the
recording's chapters, or any files you want played back to back. Chapters are joined silently
when you add or drop the first one, and further recordings added with **Add Video** join the
sequence too (the status line says so; undo or remove a clip to split it),
**Add Clips…** appends files, **Add Following Chapters** finds the camera's numbered
continuations, and the arrows reorder. Each clip has its own *In* and *Out* trim (seconds inside
that file; 0 = whole file), a *Gap before* it (black) and a *Speed* (2 = twice as fast, on top of
the input's own play speed). Trim, sync, picture settings and the
data alignment all treat the sequence as a single video, and clips may have different orientations.

**Transform and Cropping** (this video): rotation, flip, crop per edge. Then colour, sharpness, chroma key, and **Lens** for fisheye or
360° footage (unwrap into a flat, pannable view). **Audio**: include, mute, volume, balance,
channel selection.

**Transform and Cropping (all videos)**, in the project inspector, zoom, position and crop every
video at once, in the same terms an editor uses (zoom factor, position as a percentage offset from
the centre). Use it to reframe a recording without touching each chapter or each camera
separately; it applies on top of each input's own crop. When zoomed in, drag the picture itself in
the preview to pan (the cursor becomes a hand); the video object's edge handles still resize it.

**Multiple cameras.** Add each camera as its own video input, line them up in the video lane (or
with the sync fields), then arrange them with **Layout** (picture-in-picture, split, quad) and
switch between them over time with timeline segments (§6).

## 4. Data

Every data input shows its format, channels and laps. The *Channels* list maps each column to a
role (speed, RPM, latitude…) with a unit; fix a misdetected column here. *Processing* offers
resampling, smoothing, speed/heading from GPS and calculated fields (`kph = speed * 3.6`).
*Laps* come from the file when it has them, or from a start/finish line you pick on the map.

Supported files: RaceChrono (CSV v2/v3), RaceRender CSV, GPX, TCX, Garmin FIT, NMEA, Racelogic
VBO, DJI SRT, GoPro GPMF (inside the video) and generic CSV/TSV from most logging apps. Details
and column names are in [formats.md](formats.md).

## 5. Objects

Speedometer, tachometer, custom gauge (the *Gauge Designer*: needle styles, sweep, ticks, colour
zones, face images), bar/level, 2D graph (against time, distance or lap with a best-lap ghost),
g-force plot, track map (with a second vehicle and Apple Maps imagery), gear, lap counter, timers
(current/last/best lap, session, project time, time of day, delta to best), a **timing panel** (best,
previous and current lap with lap numbers plus speed-vs-best and time-vs-best lanes), **indicator
lights** (ABS, traction/stability, brake, warning triangle or text, lit when a channel crosses a
threshold, with hold time, flash and glow), text data with formatting and warning zones, shapes, text, images (data-driven rotation, opacity, flashing) and **Script** objects
that draw with JavaScript ([scripting.md](scripting.md)).

Every object has a position and size in percent of the frame, opacity, mirror and an RGB mask.
Copy/paste a style between objects (**Project ▸ Copy Object Style**) or save it as an
`.overlaystyle` file. Save a whole layout as a template (**Project ▸ Save as Template…**) to reuse
it on the next session.

### Indicator lights and your logger

Every logger names its ABS / stability / brake channels differently (a RaceChrono CAN export may
put them in `analog_1` / `analog_2`, an AiM or MoTeC file in `ABS Active` or `DSC`, a switch in
`brake_switch`). The ABS and Traction templates therefore start unbound and look through the data
input for a channel whose name mentions ABS, DSC, TCS, ESC, ESP, traction or stability; the Brake
template uses the `brake` channel when the file has one. When nothing matches the inspector says
so: pick the channel yourself. Under **Threshold** the inspector shows the channel's range in this
file ("In this file: 512 … 2800") and **Suggest** puts the threshold half way for on/off flags or
a tenth of the way up for analogue levels behind a plain light. Any channel and any level work; the
condition can be ≥, ≤, = or ≠.

The timing panel's headings, lap numbers and comparison lap (best or previous) are settings too.

## 6. Timeline segments

A segment starts at a project time and changes any object's visibility, position, size or opacity
from then on; anything not changed is inherited from the previous segment. Use them for camera
switches, hiding gauges during a pit stop, or moving a map when the picture-in-picture appears.
**Add Segment at Playhead** (**⌘K**) creates one; drag its left edge to move it (later segments
follow); the inspector shows which properties the segment overrides.

## 7. Export and share

*Export* renders through the same pipeline as the preview, so what you see is what you get.
Presets cover 720p to 4K and vertical video; codecs are H.264, HEVC, HEVC with alpha and ProRes
4444 (the last two for transparent overlay-only output to composite elsewhere). *Background* can be
the video, a key colour or transparent; *Range* exports the whole project, a time span or a range
of laps. *360°* tags a full equirectangular frame as spherical video.

**Upload to YouTube** signs in with a short code and uploads with automatic resume; it needs a
one-time Google API setup described in [youtube.md](youtube.md).

## 8. Command line

`overlaygen` does the same work without the app: `probe` inspects a data file, `render` exports
a project, `sync` finds the data/video offset from motion, `upload` sends a file to YouTube and
`bench` measures speed. See [testing.md](testing.md).

## 9. Troubleshooting

- **The gauges lead or lag the picture.** Open the sync wizard and step with the ±0.1 s buttons
  while watching a braking point; or run Auto-Sync by Motion. GoPro creation times can be tens of
  seconds off, which is why the GPS clock is preferred when the clip has one.
- **A GoPro clip appears upside down.** OverlayGen honours the camera's orientation flag; use
  Rotation 180° in the Picture section if the camera was mounted inverted without setting it.
- **A file will not open.** MTS, MKV and some AVI files need `ffmpeg` installed
  (`brew install ffmpeg`); OverlayGen converts them on first use.
- **Missing media after moving files.** The sidebar marks the input; select it and press
  **Relink…**.
- **An export is slow.** `overlaygen bench --export` reports the speed; on Apple silicon 4K HEVC
  runs at about twice real time. Large scripted objects and 4K map backgrounds cost the most.

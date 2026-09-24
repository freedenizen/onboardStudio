# Onboard Studio User Guide

Onboard Studio turns a lap video and the data recorded with it into a video with gauges, a track
map, lap timing and anything else you want drawn on top. This guide walks through a first
project and then explains every part of the window. It assumes nothing beyond having a video
and, ideally, a data log.

## 1. Your first overlay in five minutes

1. **Launch Onboard Studio.** The welcome window offers a **New Blank Project**, a project **from a
   template** (gauges already laid out), **Open Project…**, your recent projects and the sample
   project. Untick *Show this window at launch* to start on a blank project instead;
   **Help ▸ Welcome to Onboard Studio** brings the window back. A new project opens with a welcome
   panel and, the first time, a three-step tour (**Help ▸ Take the Tour** repeats it). Files can be dropped anywhere in the window. (**File ▸ New from
   Template** starts with gauges already laid out, which attach themselves to the video and data
   files you add next; **Help ▸ Open the Sample Project** opens a
   short clip with a synthetic log if you just want to poke around.)
2. **Add the video** (the big button, **⌘I**, or drop it in). If the file is the first chapter of
   a GoPro recording (`GX010037.MP4`, `GX020037.MP4`, …) Onboard Studio joins the following chapters
   so they play as one continuous video. Add a second recording the same way and it gets its own
   lane, starting where the previous video ends, with the pause between the two recordings kept
   (read from the camera's clock) so one data log stays lined up across both. Each recording has
   its own bar and its own row in the sidebar, so you can move, trim and rename it on its own. A
   file that is already in the project is not added twice. For a second camera to show picture-in-picture use **Project ▸ Add
   Camera…** (**⇧⌘I**), which opens a new lane.
3. **Add the data.** Either **Add Data File…** (**⇧⌘D**) with a RaceChrono export, GPX, FIT, CSV
   or similar, or, for a GoPro clip, select the video and press **Use Embedded GPS** to use the
   GPS, accelerometer and gyro the camera recorded. A DJI or Garmin log next to the clip appears as
   **Use Sidecar Data**.
4. **Line the data up with the video.** When the log has a clock (RaceChrono, GPX, FIT, DJI…)
   this happens automatically the moment the file is added; the status line says which clock was
   used. Otherwise select the data input and press **Auto-Sync by Motion** (matches the video's
   sound and motion against the log's speed) or **Synchronize with Video…** for the manual panel.
5. **Add gauges.** **Project ▸ Apply Template ▸ Classic Dash** gives a speedometer, tachometer,
   track map, g-force plot and lap timer at once; **Add Object** adds them one by one. Drag objects
   on the preview to move them, drag the handles to resize, and tune them in the inspector on the
   right.
6. **Play** (space) and scrub the timeline to check that the gauges follow the picture. If they
   lead or lag, open **Sync** and nudge — the panel sits under the preview, so the picture stays
   visible and scrubbable while you work.
7. **Export** (**⌘E**). Pick a preset (1080p, 4K, vertical…), a range (whole project, a time
   span or a lap range) and press Export. **Upload to YouTube…** appears when it is done.

The **Getting Started** checklist in the inspector tracks these steps and offers the next one;
**Help ▸ Show Getting Started** brings it back after you hide it.

## 2. The window

- **Sidebar (left)**: inputs (videos, data files, images) and display objects, bottom of the list
  is drawn first. Click to select and edit; the eye toggles an object; right-click to remove.
  Removing a video or data file keeps the objects that use it: they move to another file of the
  same kind, or wait for the next one you add, so replacing a log does not mean rebuilding the
  overlay.
- **Preview (centre)**: the composed frame at the playhead, exactly as it will export. Selected
  objects show handles; the arrow keys nudge them one pixel of the exported frame, or ten with ⇧
  held (the step is set in **Settings ▸ Editing**). With nothing selected, ← and → step a frame
  instead; `,` and `.` always step a frame, whatever is selected. **J**, **K** and **L** play
  backward, stop and play forward, each further tap faster. **I** and **O** mark a range on the
  ruler, which **Export** then offers as *In to out*; ⌥X clears it. In the inspector, ↑ and ↓ raise
  and lower the number field you are in (⇧↑ and ⇧↓ select text there, as they do in any field).
- **Transport and timeline (below the preview)**: play, step, scrub. The timeline has a time
  ruler (click or drag it to scrub), a marker lane (§6a), a lane with one bar per video, a lane
  with one bar per data file showing where its laps fall (§6c), and the segment strip (§6).
  Drag a video bar to move it, drag its left or right edge to trim it (the head trim keeps the
  picture where it was), click it to select the video. A click anywhere in the video or data lanes
also puts the playhead where you clicked, as in any editor. The magnet button (N) snaps drags to other
  videos' edges and the playhead; zoom with ⌘= / ⌘− / ⇧Z, the slider next to the transport, or
  scroll sideways. The thin strip above the ruler shows the whole project with a window for the
  visible part; drag it to scroll.
- **Inspector (right)**: settings for the selected input or object; drag its left edge to widen it.
  With nothing selected it shows the project's output size and frame rate, its details, font,
  camera framing and the Getting Started checklist; **Project ▸ Show Project Details** (⌃⌘I)
  clears the selection to get there from anywhere. The window fits displays 1024 points wide. What you type in a
  text field takes effect when you press Return or leave the field, so a whole name is one step
  of Edit ▸ Undo; Escape abandons what you typed. The Edit menu says what Undo and Redo will do —
  *Undo Change Sweep*, *Redo Rename Object* — before you choose them.
- **Status line (bottom)**: what the app last did for you — chapters joined, data synced, a file
  refused. Nothing it says is lost when the next message replaces it: the clock button at its right,
  or **View ▸ Show Activity** (⌥⌘L), lists everything the app has told you in this project, newest
  first, with **Copy All** for a bug report. Errors shown in an alert are listed there too.
- **Toolbar**: Add Video, Add Data, Add Object, Layout, Sync, Export. Hover over any button without
  a caption, here or under the preview, for its name and shortcut.
- **VoiceOver**: every control is named, and each object on the preview is an element of its own
  that VoiceOver can select and move with its actions (Move Left, Right, Up, Down).

## 3. Videos

**Trim, sync and speed** live in the input's *Synchronization* section: *start position in file*
skips into the recording, *offset in project* delays the video on the project timeline, and *play
speed* slows or speeds it up. **Start After Previous Video** chains a clip onto the one above it in
the list; **Start at 0** resets its offset; the arrow buttons reorder inputs.

**Clip sequences.** The *Clips* section lists the files that make up one continuous video: the
recording's chapters, or any files you want played back to back. You can see the join without
opening the inspector: the sidebar row says how many files the input is (`3840×2160, 1428 s ·
2 files`) and lists them when the input is selected, and the timeline bar draws a line at each
seam, with a break where the camera was stopped between files. Chapters are joined silently
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

**Stabilisation** steadies a shaky picture, such as from a helmet mount, using the orientation the
camera recorded with the video — GoPro HERO8 and later record it with every clip. Set **Steady** to
**From camera motion data**: each frame is moved so the camera seems to follow a smooth path, so
the shake goes but turning your head or the car still comes through. **Smoothing** sets how long
the steadied view takes to follow (towards *Follow* keeps more movement, towards *Float* smooths
more); **Zoom** enlarges the picture just enough to hide the edges the moves bring into view, and
also limits how far a frame can move. Everything else — sync, the embedded GPS and telemetry, the
chapters — is unaffected, because the video file itself is not changed.

A video recorded with HyperSmooth is already steadied by the camera and cannot yet be steadied
further here; a video with no motion record (most cameras other than GoPro) says so in the
inspector.

#### Steadying from the picture

For a camera that records no motion data — most action cameras other than GoPro, phones, a dash cam
— choose **Steady ▸ From the picture ▸ Measure Motion**. Onboard Studio follows how the picture moves
from frame to frame (about thirty times a second), once per video, and steadies it from that with the
same **Smoothing** and **Zoom**. It keeps the measurement, so the video is not measured again unless
the file changes. It works best on a picture with plenty in it; blur, darkness or a plain sky make it
weaker, and it cannot tell turning from moving sideways, so prefer motion data when the camera
records it.

#### Stabilising with Gyroflow

[Gyroflow](https://gyroflow.xyz) is a free app that steadies video from the camera's gyroscope,
corrects the lens and the rolling shutter, and handles footage recorded with HyperSmooth. Onboard
Studio can run it for you and show its steadied copy in place of the recording.

**Installing Gyroflow** (once):

1. Either, in Terminal: `brew install --cask gyroflow` (needs [Homebrew](https://brew.sh)), or
   download the macOS version from [gyroflow.xyz/download](https://gyroflow.xyz/download) and drag
   **Gyroflow** into your **Applications** folder.
2. Open Gyroflow once from Applications so macOS lets it run, then quit it. Onboard Studio finds it
   in Applications (or your own Applications folder) by itself; there is nothing to set up.

**Using it:** select the video, then **Stabilisation ▸ Steady ▸ With Gyroflow ▸ Stabilise with
Gyroflow**. A progress bar follows the render — it takes a while, several times the length of the
video for 2.7K or larger — and **Cancel** stops it. Gyroflow writes a steadied copy of each file of
the video beside the recording (`GX010037-gyroflow.mp4`), at the recording's own size; when the
folder cannot be written to, the copies go into Onboard Studio's Application Support folder. The
recording itself is never changed.

Only the **picture** is taken from Gyroflow's copy. Gyroflow's files lose the GPS and motion data a
GoPro records (GoPro Player's stabilised export does too), so the embedded telemetry, the camera's
clock for syncing and the chapters all keep coming from the recording — and the copy has exactly the
recording's frames and length, so the sync you set still holds. If a copy goes missing, the
recording is shown again until you choose **Stabilise Again**. Gyroflow runs as a separate program:
it is licensed under the GPL, and is not part of Onboard Studio.

**Transform and Cropping (all videos)**, in the project inspector, zoom, position and crop every
video at once, in the same terms an editor uses (zoom factor, position as a percentage offset from
the centre). Use it to reframe a recording without touching each chapter or each camera
separately; it applies on top of each input's own crop. When zoomed in, drag the picture itself in
the preview to pan (the cursor becomes a hand); the video object's edge handles still resize it.

**Multiple cameras.** Add each camera as its own video input, line them up in the video lane (or
with the sync fields), then arrange them with **Layout** (picture-in-picture, split, quad) and
switch between them over time with timeline segments (§6).

## 4. Data

Every data input shows its format, channels and laps. Its *Attributes* section says what is
mapped and how the import went, in a line, and **Map Attributes…** opens the window where a
misdetected column is fixed and every column's fate is listed (see below). *Processing* offers
resampling, smoothing, speed/heading from GPS and calculated fields (`kph = speed * 3.6`).
*Laps* come from the file when it has them, or from a start/finish line you pick on the map.

Supported files: RaceChrono (CSV v2/v3 and `.rcz` archives), RaceRender CSV, GPX, TCX, Garmin FIT,
NMEA, Racelogic VBO, DJI SRT, GoPro GPMF (inside the video) and generic CSV/TSV from most logging
apps. Details and column names are in [formats.md](formats.md).

### Attributes: what your channels mean

Your logger names its channels its own way. One car's ABS light is `canbus:analog_1`; the same
brake sensor is `brake_pressure_front` in a RaceChrono CSV and `66569` in the `.rcz` of the very
same session. **Attributes** are the app's names for what those numbers *mean* — Speed, Brake
pressure (front), Coolant temperature, ABS — and they are the same whatever file you opened.

**Project ▸ Map Attributes…** (⌥⌘A), or **Map Attributes…** in the data inspector or in Settings,
opens the attribute window, pointed at the data file you have selected. One row per attribute,
three columns:

| Column | What it sets |
| --- | --- |
| **From** | which column of your file feeds this attribute. Type to filter; the placeholder shows the column the app matched on its own. |
| **Reads** | what the file's numbers are in. Usually the file says, and the app shows it; set it when the file is silent or wrong. This changes how numbers are *read*, never how they are shown. |
| **Shows** | what every object displays it in. Brake pressure logged in kPa, shown in bar. Only units it can actually convert to are offered. |

An attribute that is either on or off — ABS, traction control, pit limiter — has no unit to be
shown in. Its row asks for the level it counts as on at instead, because a logger usually records
these as a raw analog channel rather than a yes or no.

The sidebar chooses who the mapping is for:

- **All projects** — set once, and every file you import afterwards follows it. This is the one to
  use for your own car: tell the app once that Brake pressure comes from `brake_pressure_front` in
  kPa and should be shown in bar.
- **This project** — where one project differs.
- **A data input** — where one file is the exception.

Each level follows the one above unless you set it, so changing the global mapping moves
everything that has not been pinned and leaves what you did pin alone. A change takes effect at
once, in projects that are already open too. A column you point an attribute at is still listed
under its own name as well, so an object's channel picker offers both *Brake pressure (front)*
and `brake_pressure_front (CAN bus)`, and objects already using the raw channel keep drawing. A single object can differ
again — see *Units* under [Objects](#5-objects).

**From the keyboard.** The window is built to be used without the mouse. **⌘F** goes to the filter
field in the toolbar. Type part of an attribute's name, or of the column it comes from, and only
the matching rows stay. A filter searches every attribute, including ones this file does not
supply. **Return** moves to the first row's *From* field; type the column and press Return again.
**Tab** walks the table in reading order: along a row, then down to the next. As you type a
column, matching columns are offered below the field; pick one with ↓ and Return. **Escape**
abandons what you typed. **⌘1** and **⌘2** switch between the attribute table and the import
report. Hover over a column title, a truncated summary or a sidebar level for a short
explanation.

The window remembers which level it was showing, which view, and whether every attribute was
listed, between launches. Without a project open it still edits *All projects*: there are no
columns to choose from then, but you can type a column's name.

### What the import read

The attribute window's **Import** tab (⌘2, or **Project ▸ Show Import Report…**) says what became
of every column of the file, in the attribute table's own words: which ones
became channels, which of three columns called `speed` kept the role, which sensor read the same
number all session (usually one that is not connected), and which units the app did not recognise.
It shows only the columns worth a look; *Show every column* gives the rest. A file where
everything read cleanly says so in one line. The filter field searches every column by name,
group or what it became. Select rows and press **⌘C** to copy them as text, for a message to
whoever wired the logger. Without a data file the tab says so and offers **Add Data File…**.

**A file that knows where the line is.** Racelogic VBO files record the start/finish line, and
any sector gates, as actual geometry — the only format that does. Add one and the line and sectors
come with it, and the app says so rather than guessing from the trace. Opening a project you saved
earlier never changes its line, whatever the file says.

**The circuit.** Onboard Studio recognises where you were driving from the GPS trace, against a
bundled list of 1,290 motorsport venues — nothing is fetched and nothing is sent anywhere. The
*Track* section names it, says how sure it is, and lets you search for the right one if it guessed
wrong or found nothing. *Not This Circuit* clears it.

**Corners.** The map can number the corners, found from your own driving. Out of the box it
counts them 1, 2, 3 — which is not what your circuit calls them: Sonoma runs 1, 2, 3, **3a**, 4,
**4a**, and letter suffixes are normal everywhere. No public source publishes corner numbering, so
type the real names into *Corners* once and they stay with the track.

**Save Start/Finish, Sectors and Corner Names for This Track** files them all against that
circuit. The next data file you *add* from the same place starts with them already
filled in, so you set a venue up once rather than once a session. Opening a project you saved
earlier never applies them: a project renders the way you left it, whatever the app has learned
since.

## 5. Objects

Speedometer, tachometer, custom gauge (the *Gauge Designer*: needle styles, sweep, ticks, colour
zones, face images), bar/level, 2D graph (against time, distance, the lap with a best-lap ghost, or another channel — see below),
g-force plot, track map (with a second vehicle and Apple Maps imagery), steering wheel, gear, lap counter, timers
(current/last/best lap, session, project time, time of day, delta to best), a **timing panel** (best,
previous and current lap with lap numbers plus speed-vs-best and time-vs-best lanes), a **stat card**
(the headline numbers — see below), **indicator
lights** (ABS, traction/stability, brake, warning triangle or text, lit when a channel crosses a
threshold, with hold time, flash and glow), text data with formatting and warning zones, shapes, text, images (data-driven rotation, opacity, flashing) and **Script** objects
that draw with JavaScript ([scripting.md](scripting.md)).

Wherever the inspector asks for a channel it lists the file's channels by the attribute they are —
*Lateral G*, *Brake pressure (front)* — and a channel the file named itself by that name, with
where it came from: `analog_1 (CAN bus)`. Hover over a control whose one-word label does not say
enough, such as a needle's *Tail* or *Hub*, for a short explanation.

### Graphs: what is coming, and one channel against another

A graph against **Time** or **Distance** shows the current moment in the **middle** of its window,
marked by a line, so the braking point you are about to reach is on the right while the corner you
have just left is on the left — the data is all loaded, so the future is known. **Now at** slides it
anywhere from the left edge (all of the window still to come) to the right edge (all of it past, as
a strip-chart recorder draws); **Line at now** turns the line off. Graphs in projects saved before
this keep drawing at the right edge, as they did.

**Horizontal axis ▸ Another channel (X-Y)** plots each series against a channel you choose instead
of time: longitudinal against lateral G for a G-G diagram, throttle against speed, brake pressure
against speed. The last *Trail* seconds are drawn as a line that fades out behind a dot at the
current moment, and the horizontal range fits the trail unless you set *Horizontal min* and *max*.
A series on its own scale keeps it here too.

Switching a bar between **Horizontal** and **Vertical** turns its frame with it, about its centre,
so a long thin bar becomes a tall thin one rather than a stub in a wide box; a frame you had
already shaped for the new direction is left as it is.

### Stat card and the Social template

A **Stat Card** (Add Object ▸ Stat Card) puts the session's headline numbers on one card, for a clip
you share: a title — `{track} · {date}` at first, filled from the project's details — then the best
lap and its number, top speed, the optimal lap (best sectors spliced together, when the data has
sectors) and how many laps were completed. Switch *Counts* to **The lap at the playhead** and the
card follows whichever lap is playing instead: its time, how far off the best it is (or *Best lap*),
and its top speed. Each number can be turned off; top speed is in the card's own speed unit.

**New from Template ▸ Social (9:16)** lays a project out for a phone: 1080 × 1920, the whole
16:9 picture as a band across the middle rather than cropped to a sliver, a lap-following stat card
above it, and the lap timer, speedometer and track map below.

To share one lap without re-laying your project, put the playhead in it and choose **Project ▸
Export Lap as Vertical Clip…** (⇧⌘E), or right-click a marker in the sidebar and choose **Export as
Vertical Clip…** — a range marker exports its own range, a point marker the lap it falls in. The
sheet shows the stretch it will export; **Export…** writes `<project> – Lap 7 (vertical).mp4` at
1080 × 1920, laid out by the Social template, with your project's channels, units, font, frame rate
and codec. The project itself is left exactly as it was. When it finishes, **Reveal in Finder** or
**Upload to YouTube…** from the same sheet.

### Locking and grouping

A finished object can be **locked** (**Project ▸ Lock**, ⌘L, the padlock beside it in the
sidebar, or *Locked* in its inspector): it still draws and still edits in the inspector, but a
click on the preview goes straight through it to whatever is behind — the video, usually — and
the arrow keys and the delete key leave it alone. It is outlined in dashes. ⌘L again unlocks it.

⌘-click or ⇧-click objects in the sidebar (or ⇧-click them on the preview) to select several;
dragging or nudging any of them moves them all. **Project ▸ Group** (⌥⌘G) keeps them together:
a click on any member on the preview selects the whole group, which moves, resizes from one box
and nudges as one, and locks as one. Clicking a member in the sidebar selects just that object,
to edit it on its own. **Ungroup** (⇧⌥⌘G) separates them again. As in Keynote, locked objects
are unlocked before they are grouped, and a group that deleting leaves with one member stops being
a group.

Every object has a position and size in percent of the frame, opacity, mirror and an RGB mask.
Copy/paste a style between objects (**Project ▸ Copy Object Style**) or save it as an
`.onboardstyle` file. Save a whole layout as a template to reuse it on the next session (see
*Your own templates* below).

### Your own templates

**Project ▸ Save as Template…** saves the layout — objects, fonts, segments, output size and
export settings, but not the videos, data files or the project's details — under a name, with a
picture of what is being saved. Saving under a name you already use says so and offers **Replace**.

Your templates sit beside the built-in ones in the welcome window (**Help ▸ Welcome to Onboard
Studio**) and in **File ▸ New from Template**, each card with a picture of its layout. Right-click
one of yours to **Rename…**, **Duplicate**, **Show in Finder**, **Export…** it to share, or
**Delete…** it (it goes to the Trash). **File ▸ Import Template…** adds a template someone sent
you, and so does double-clicking an `.onboardtemplate` file in the Finder; it keeps the file's
name. **Project ▸ Apply Template** puts any template's layout onto the project you are in.

### See-through overlays

Every colour in the inspectors has an opacity, every object has its own **Opacity**, and the
project inspector's **Overlay opacity** fades all gauges, maps and readouts together. For the look
of manufacturer track apps start from **Project ▸ Apply Template ▸ Glass Cockpit**: a band that
fades from clear to dark behind the instruments (any **Shape** can take a *Gradient fill*), ring
gauges with glass faces, a g-force trail, plain lap text without boxes, and a **Steering Wheel**:
a translucent rim whose yellow top-centre marker turns with the steering angle. The wheel is meant
to be wide and to hang below the frame so only its upper arc shows. It binds itself to your
logger's steering channel (any channel whose name starts with "steer", or `SWA`) and picks the
scale from its values: degrees, radians, or a −1…1 channel; **Invert direction** covers loggers
that count a right turn as negative.

### Deltas to your best lap

No script or pre-processing is needed for delta readouts. Whenever the data has laps, Onboard Studio
adds two channels that any object can use (bars, graphs, text, gauges, indicator lights, scripts):
**`lapDelta`**, the seconds you are behind (+) or ahead of (−) the session's best lap at the same
spot on the track, and **`speedDelta`**, your speed minus the best lap's speed there. Both compare
by distance travelled since the start of the lap, and the best lap is the quickest full lap of the
whole session, so the first lap already has a delta and the best lap reads zero. **Add Object ▸
Delta Bar (time)** and **Delta Bar (speed)** are ± bars that grow left or right of a zero mark in
green or red; any bar becomes one with **Fill from zero**. The Delta timer and the Timing Panel
can compare with the *session best lap* (the default), the *best lap so far* (what a live lap
timer shows) or the *previous lap*.

A Timer set to **Projected lap** shows what the lap in progress will come to if the rest of it goes
as the lap it compares with did: that lap's time plus the delta now, as a lap time (`1:32.45`),
green while it is on course to beat it and red while it is not. On the best lap it reads the best
lap's time throughout, and as a lap finishes it arrives at that lap's own time. The same number
against the session's best lap is the **`projectedLap`** channel, for a graph or a digital readout.

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

### Project details and title cards

The project inspector's **Details** say what the project is of: **Track**, **Car**, **Driver**,
**Event**, **Session** and **Date**, plus any detail of your own — *Add Detail…* and call it
*Tyres*, *Class* or *Setup*. Adding a data file fills in whatever it knows and nothing you have
typed: a RaceChrono export names its track and driver, and most loggers say which day they
recorded; a file that does not name its track takes the circuit it was recognised as.
**Fill In from Data** does the same later, for a project started before details existed.

Any **Text** object shows a detail by naming it in braces — `{track} · {date}`, `{car} on
{tyres}` — and **Insert Detail** in its inspector adds one without typing, each item saying what
it stands for now. **Add Object ▸ Title Card** starts with `{track} · {date}`. A detail with
nothing entered stays in its braces, so a title card asks for what is missing rather than
quietly leaving a gap. Details belong to the project, not to templates: a template with a title
card picks up each project's own track and day.

### Fonts

Every object that draws text has a **Font** section in its inspector: a font, a typeface within it
(*Bold*, *Condensed Medium*, …) and, for objects without a size of their own, a **Text size** from
50 % to 200 %. The font reaches all of the object's text at once — a gauge's tick labels and
readout, a timer's caption and time, a map's corner labels. Numbers stay one width in any font, so
a changing readout does not shuffle sideways.

To set one font for the whole project, choose **Project ▸ Show Project Details** and use the project
inspector's **Font** section. Objects follow it until they choose their own: their pop-up reads
*Project Font (Futura Bold)*, and choosing it again goes back to following. *Built-In* is how the
app drew before fonts could be chosen — labels in Helvetica Neue, numbers in Menlo — and is what a
project saved before this keeps.

A project opened on a Mac without its font says so under the pop-up and draws that text in the
built-in fonts rather than a substitute, until the font is installed. Copy and paste a style
(**Project ▸ Copy Object Style**) and the font goes with it.

### Units on an object

An object shows its channel in whatever the attribute's *Shows* unit says, and a **Unit** picker
on the object overrides it for that one object — a second brake bar in psi beside one in bar, an
altitude readout in feet in a project working in metres. *Automatic* follows the attribute, and
the caption says what that currently amounts to. Only units the channel can actually be converted
into are offered, so a temperature gauge is never asked whether it would like to be in bar.

Speed keeps its own picker (mph, kph, m/s), which is what projects saved before attributes existed
already use.

A gauge or bar **added** while a data file is loaded takes its scale and unit label from what that
channel actually reads, rather than the template's 0–100 %. A brake pressure running to 1900 kPa
gets a 0–1900 kPa scale instead of a bar pinned at full all lap. Opening a saved project never
rescales anything: it renders the way you left it.

## 6. Timeline segments

A segment starts at a project time and changes any object's visibility, position, size or opacity
from then on; anything not changed is inherited from the previous segment. Use them for camera
switches, hiding gauges during a pit stop, or moving a map when the picture-in-picture appears.
**Add Segment at Playhead** (**⌘K**) creates one; drag its left edge to move it (later segments
follow); the inspector shows which properties the segment overrides.

### 6a. Markers

A marker is a named point — or a stretch — worth coming back to: a braking reference, an
incident, the start of a sector.

- **M** drops one at the playhead; **⌘M** drops one and asks for its name straight away, pausing
  playback so you can type. **⇧↑** and **⇧↓** walk to the previous and next marker.
- Markers appear in the lane above the video bars and in a **Markers** list in the sidebar; click
  either to jump to one. Select one and the inspector gives it a name, a colour, a note and a
  *Length* — leave the length at 0 for a flag, or set it to draw a bar across a stretch.
- **Where a marker belongs matters.** With an input selected when you press M, the marker belongs
  to that input and is stored in *its* time, so re-syncing or re-speeding that input carries the
  marker along with it. With nothing selected it belongs to the timeline and stays at that
  timecode. The inspector says which kind you have.

### 6b. Splitting and trimming

Select a video on the timeline and **⌘\** cuts it at the playhead (**Project ▸ Split at
Playhead**). You get two independent halves that can be trimmed, moved and re-synced separately,
and the picture runs on unbroken across the join.

A split adds a second input *and* a second camera object, with a timeline segment that swaps them
over at the cut. That is because a segment can show and hide objects but cannot change which
input an object plays — so without the extra object the second half would sit on the timeline and
never appear. Both show up in the sidebar named after the original (`Camera 2`, and so on).

**⇧[** drops everything before the playhead and **⇧]** everything after it (**Project ▸ Trim
Start / End to Playhead**). Everything here is non-destructive — the files are untouched and
**⌘Z** puts it all back.

**Data files split and trim the same way.** Select the data bar instead of a video and the same
commands apply, with the trim shown in seconds of the file in the inspector's *Trim* section.
Trimming data is applied *before* laps are worked out, so trimming an out-lap away stops it being
counted and stops it competing for the best lap — rather than leaving it in place renumbered.
Splitting data duplicates the gauges reading it, for the same reason splitting a video duplicates
the camera.

There is no separate "split at marker" or "trim to marker": jump to the marker with **⇧↑** /
**⇧↓**, which puts the playhead on it, then split or trim. That is how Resolve works too, and one
command cannot disagree with another about where the cut goes.

### 6c. Laps

Each data file gets a bar on the timeline with a divider at every lap, numbered where there is
room. The laps come from the file's own timing, so re-syncing the data slides its laps along with
it rather than leaving them behind.

**⌥↑** and **⌥↓** jump to the previous and next lap (**Marker ▸ Previous / Next Lap**), reporting
the lap number and its time in the status line. Going back from mid-lap lands on the start of the
lap you are in, as previous-edit does in an editor; a second press goes to the one before.

Laps that fall past the end of the video cannot be reached — the timeline ends when the picture
does.

### 6d. Sectors

A lap split into parts tells you *where* the time went, not just how much. Select the data file
and open **Sectors** in the inspector:

- **Equal distances** (the default) cuts the fastest lap's distance into three. It needs no setup
  and works anywhere — a circuit, an autocross, a hill climb.
- **On the straights** puts each boundary on the nearest straight instead, so a sector never cuts
  a corner in half. The corners are found from your own driving; nothing here knows the venue.
- **Gates I place** uses lines you add at the preview position, crossed in the order you drive
  them.

The inspector then lists each sector's best time and the lap it came from, and the **theoretical
lap** — every sector's best added together, the lap you have already driven in pieces.

Add a **Sector Times** object to put them on the video. Finished sectors show their time and how
it compares; the sector you are in counts up in the highlight colour; the ones ahead stay blank.
**Compare with** chooses the yardstick: the best that sector was driven all session, the same
sector on your best lap, or on the lap before. Crossing the line holds the finished lap up for a few
seconds, which is the only moment its last sector can be read.

No source of sector definitions exists that this app could ship — circuits do not publish them in
any readable form, and the one dataset that has them is licensed so it cannot be used here. That
is why sectors are derived from your driving or drawn by you.

### Comparing two laps

**Project ▸ Compare Laps…** plays two laps side by side, kept level by distance, so the same corner
arrives in both pictures at the same moment and you can see where one lap gained on the other. Pick
the **lap** to play and the lap to **compare with** — any complete lap of any data file in the
project, with the camera that filmed it: two laps of one session, or today's best against last
month's, or against another driver's. Choose **Side by side** or **Stacked**, then **Compare**.

The project is laid out for the comparison: each lap's picture with its lap timer and speed, and
between them a **delta** — how far ahead (−, green) or behind (+, red) the lap playing is at that
point round the track. The compared lap is slowed down or sped up moment by moment to stay level,
matched by how much of the lap each has covered, so two sessions whose GPS disagree about the lap's
length still meet at the line. The export range becomes the lap, so **Export** writes just it.

Everything in the layout is an ordinary object you can move, restyle or add to. An object's
**Shows the compared lap** (in its inspector, while comparing) switches it to the other lap; a
Timer's *Compare with* ▸ **Compared lap** measures against it. **Undo** restores the layout you
had; **Project ▸ Stop Comparing Laps** removes the compared lap and keeps the rest.

## 7. Export and share

*Export* renders through the same pipeline as the preview, so what you see is what you get.
Presets cover 720p to 4K and vertical video; codecs are H.264, HEVC, HEVC with alpha and ProRes
4444 (the last two for transparent overlay-only output to composite elsewhere). *Background* can be
the video, a key colour or transparent; *Range* exports the whole project, a time span or a range
of laps. *360°* tags a full equirectangular frame as spherical video.

**Every lap, one file each** (in *Range*) writes each lap as its own video, into a folder you
choose, named for the project and the lap: `Sonoma – Lap 7.mp4`. *Complete laps only* (on at first)
leaves out the out-lap and the in-lap, which begin or end in the pits rather than at the line;
*Skip slow laps* leaves out cool-down and traffic laps, those slower than your best by more than the
percentage you set. The sheet says which files it will write before you start, and one progress bar
covers them all. From the command line: `onboard render --project X --laps each --out <folder>`,
with `--include-partial-laps` and `--skip-slower-than 10`.

**Upload to YouTube** signs in with a short code and uploads with automatic resume; it needs a
one-time Google API setup described in [youtube.md](youtube.md).

## 8. Command line

`onboard` does the same work without the app: `probe` inspects a data file, `render` exports
a project, `sync` finds the data/video offset from motion, `upload` sends a file to YouTube and
`bench` measures speed. See [testing.md](testing.md).

## 9. Troubleshooting

- **Reporting a problem.** **Help ▸ Export Diagnostics…** saves one zip for a bug report: the
  app's log since it started, everything it told you, the open project's settings and file paths,
  a description of each data file (channels, units, ranges, laps — not the data itself), which
  ffmpeg it found, and any crash report from the last two weeks. No videos or data go in, and the
  app sends nothing: you choose where it is saved and whom to give it to. After a crash, the app
  offers to make one when it next starts.

- **Something happened and the message is gone.** **View ▸ Show Activity** (⌥⌘L) lists every
  message and error since the project opened; **Copy All** puts them on the clipboard.

- **The gauges lead or lag the picture.** Open **Sync** and nudge while watching a braking point.
  The panel stays out of the way under the preview, so you can scrub, look and nudge in a loop;
  the **−1f / +1f** buttons move by a single frame, which is finer than a tenth of a second at
  every normal frame rate. You can move the video against the data as well as the data against
  the video. Or run Auto-Sync by Motion. GoPro creation times can be tens of
  seconds off, which is why the GPS clock is preferred when the clip has one.
- **A GoPro clip appears upside down.** Onboard Studio honours the camera's orientation flag; use
  Rotation 180° in the Picture section if the camera was mounted inverted without setting it.
- **A file will not open.** MTS, MKV and some AVI files need `ffmpeg` installed
  (`brew install ffmpeg`); Onboard Studio converts them on first use.
- **Missing media after moving files.** The sidebar marks the input; select it and press
  **Relink…**.
- **An export is slow.** `onboard bench --export` reports the speed; on Apple silicon 4K HEVC
  runs at about twice real time. Large scripted objects and 4K map backgrounds cost the most.

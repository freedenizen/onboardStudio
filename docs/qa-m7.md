# QA script — M7 gauge designer and full object set

Open a project with a video and a data file that has laps (a RaceChrono export works best).

| # | Step | Expected |
|---|---|---|
| 1 | Select a speedometer; in the inspector change **Style** to *Filled arc*, then *Dual needle* with a second channel | The preview redraws immediately: an arc fills from zero, or a second thinner needle appears |
| 2 | Set **Sweep** 360 and **Counter-clockwise** | Full circle; values increase anticlockwise; no duplicate label at the top |
| 3 | Drag the **Needle** sliders (length, tail, width, hub), toggle **Tapered** | Needle shape follows; hub disc resizes |
| 4 | Set **Smoothing** 1 s and play | Needle moves noticeably smoother than the Text Data readout of the same channel |
| 5 | In **Ticks & Labels** set major tick 250 on an 8000 rpm scale | Labels thin out automatically; turn off **Declutter** to see them overlap |
| 6 | Add two **Zones** (e.g. 5000–6500 orange, 6500– red); toggle *Colour needle*, *Colour ticks*, *Blend colours* | Bands paint the face; needle and marks take the zone colour; blending fades in before each threshold |
| 7 | **Face ▸ Add Face Image…** and pick a PNG; turn off **Show face** | The image sits under the scale, aspect-fitted |
| 8 | Add **Bar** (throttle, 20 segments, zone from 90) and a vertical one | Segments light up with throttle; caption fits the object |
| 9 | Add **Graph** with axis *Current lap (distance)* | Live trace grows from the left across the lap; the best lap is a grey ghost once one lap is complete |
| 10 | Add **Gear**, **Lap Counter** (*Show total*) and a **Timer** in *Delta to best lap* | Gear glyph (N/R/P for 0/−1/−99); "2 / 9"; delta shows green (ahead) or red (behind) after the first complete lap |
| 11 | Timer *Time of day* and *Video time* | Clock matches the data's timestamps; video time follows the playhead |
| 12 | Text Data: multiply 0.001, 1 decimal, thousands separator, + sign, minimum digits 2 | e.g. rpm 5478 → `+5.5` |
| 13 | **Project ▸ Copy Object Style** on the styled speedometer, select a tachometer, **Paste Object Style** | The tachometer takes the speedometer's look (undo reverts) |
| 14 | **Export Object Style…** to a file, reopen a fresh project, **Import Object Style…** with nothing selected | A new object with the saved look is added |
| 15 | ⌘S, reopen | Every designer setting restored |

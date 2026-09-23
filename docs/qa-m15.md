# QA script — M15 guided experience and video arrangement

| # | Step | Expected |
|---|---|---|
| 1 | Launch the app (new document) | The preview shows a welcome panel with "Add Video…", "Open the Sample Project" and links; the inspector shows the Getting Started checklist with step 1 highlighted |
| 2 | **Help ▸ Open the Sample Project** | A copy opens from Documents with a 3 s clip, a data log and gauges; the checklist shows the first four steps done |
| 3 | Add `GX010037.MP4` from a GoPro card that also holds `GX020037.MP4` | An alert offers to add the following chapter; **Add Chapters** produces one input whose *Clips* section lists both files and whose duration is the sum |
| 4 | Select the video, *Clips*: move the second clip up | The files swap; the preview at the old chapter boundary now shows the other file |
| 5 | Add a second video input, drag its bar in the video lane towards the first one's end | It snaps to the end; *Synchronization* shows the new offset; **Start After Previous Video** does the same exactly |
| 6 | Project inspector, *Camera Framing*: zoom 1.5, pan right | Every video zooms and pans together; per-input crop still applies underneath; **Reset Framing** restores |
| 7 | **Help ▸ Keyboard Shortcuts** / **User Guide** | A shortcuts window opens / the guide opens in the browser |
| 8 | Hide Getting Started, then **Help ▸ Show Getting Started** | The checklist disappears and returns |
| 9 | Save, reopen | Clips, offsets and framing survive; a project saved by an older version opens with no framing and no clips |

## Results (0.13.0, real GoPro chapters GX010037 + GX020037 and the RaceChrono log)

- **New document**: the preview shows the welcome panel ("Add Video…", "Open the Sample Project", User Guide and formats links) and the inspector shows the Getting Started checklist with the first step highlighted. A first run also surfaced a spurious "The project has no video input that can be opened" alert on the empty document; fixed (an empty project is not an error).
- **Chapters**: a project whose GoPro input lists `GX020037.MP4` under *Clips* reports the summed duration (1427.95 s = 769 + 659 s) and plays through the chapter boundary; the *Clips* section shows both files with reorder/remove controls, **Add Clips…** and **Add Following Chapters**. The chapter alert on adding `GX010037.MP4` goes through an open panel, which the scripted QA cannot drive, so it was checked by code review only.
- **Camera framing**: dragging *Zoom* to 1.90× zooms the live preview immediately and reveals the pan sliders; the per-input crop still applies underneath; **Reset Framing** restores.
- **Video arrangement**: with two video inputs a purple lane appears above the segments. Dragging the GoPro bar moved it to 366.14 s (the project grew to 29:54 accordingly); selecting the second camera and pressing **Start After Previous Video** set its offset to 1,794.093 s, exactly the GoPro sequence's end, and the lane shows the two bars back to back (project 40:53). *Synchronization* shows "Plays from … to …", **Start at 0** and the order arrows. Note for scripted QA: the lane only reacts when its window is frontmost.
- **Sample project**: **Help ▸ Open the Sample Project** copied the bundled sample to Documents and opened it: a 3 s clip, a RaceRender log with 3 laps, speedometer, map, g-force, lap timer and RPM, with the first four checklist steps ticked.
- **Help menu**: User Guide, formats, scripting, YouTube, project format links; Keyboard Shortcuts window; Show Getting Started; Open the Sample Project (copies the bundled sample to Documents and opens it).

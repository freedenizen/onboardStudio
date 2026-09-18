# QA script — M9 templates, export options and polish

| # | Step | Expected |
|---|---|---|
| 1 | **File ▸ New from Template ▸ Classic Dash**, then Add Video and Add Data | The dash objects appear and bind to the new inputs; gauges move |
| 2 | Style the project, **Project ▸ Save as Template…**, name it | The template appears under **Apply Template** and **New from Template** |
| 3 | Open another project, **Apply Template ▸ (yours)** | Objects, timeline and export settings replaced; inputs kept; ⌘Z restores |
| 4 | **Export…**: pick *3840 × 2160 · HEVC* | Size, codec and bitrate fields update; changing any field switches the preset to Custom |
| 5 | Range *Laps*, first 2 last 3 | The caption shows the project time span; the exported file is exactly those laps long |
| 6 | Background *Key colour*, blue | The export has no video, a flat blue background and the overlays; keying it in another editor works |
| 7 | Background *Transparent* | Codec switches to ProRes 4444; the `.mov` has an alpha channel (drop it on a video in another editor) |
| 8 | Move a data file away, reopen the project | The sidebar shows a warning on that input, the inspector explains and offers **Relink…**; the video still plays |
| 9 | **Relink…** to the file | Warning clears, gauges come back |
| 10 | Select an object, press arrow keys (⇧ for larger steps) | The object nudges by the step set in Preferences |
| 11 | **OverlayGen ▸ Settings…** | Default export preset, nudge step, ffmpeg path and automatic update checks are editable and persist |

## Results (0.7.0, real Sonoma project)

- A camera pointed at a missing file shows the warning in the sidebar and the reason plus **Relink…** in the inspector while the other camera and the data keep rendering (the open panel itself cannot be driven by script, so the relink click was verified by hand-inspection of the code path and the loader tests).
- **Save as Template…** wrote `QA Dash.overlaytemplate`; **Apply Template ▸ Classic Dash** replaced the dash and dropped the second camera and segment; applying **QA Dash** brought them back.
- The export sheet opens on *Project size* with the project's audio bitrate; presets, background and range controls render.
- Preferences window shows the default preset, nudge step, ffmpeg path and update toggle.
- Fixes on the way: `ProjectCompiler.load` never populated converted media URLs or loaded images (image inputs and MTS conversion did not reach the compositor); number fields committing on focus marked the preset Custom.

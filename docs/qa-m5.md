# QA script — M5 input processing

Continue from a project with one video and one data file (see `docs/qa-m4.md`).

| # | Step | Expected |
|---|---|---|
| 1 | Select the video input; in **Picture** choose Rotation 90° | Preview rotates immediately (paused frame redraws); the letterbox changes shape |
| 2 | Toggle **Mirror horizontally** | Picture flips; toggle again to restore |
| 3 | Drag **Crop left** to ~20% | Left edge of the picture disappears and the rest re-fits the frame |
| 4 | In **Colour**, drag Saturation to 0, Brightness to 150% | Greyscale, brighter picture; **Reset colour** restores |
| 5 | Enable **Chroma Key**, pick a colour present in the picture, raise Tolerance | That colour turns transparent (black background shows through) |
| 6 | In **Audio**, set Balance fully left, then Channels = Right only | Playback audio pans / switches accordingly; export carries the same mix |
| 7 | Select the Camera object; in **Video Layer** turn off the Red channel | Picture loses red; export matches |
| 8 | **Add Object ▸ Shape**, set Ellipse, pick a fill colour, stroke width | Shape draws with fill and stroke; drag/resize works |
| 9 | **Add Object ▸ Text**, type a caption, set outline | Caption appears with outline; alignment options move it |
| 10 | **Add Object ▸ Image…**, choose a PNG | Image input and object appear; set **Rotate by channel** = heading, Degrees per unit = 1 | Image turns with the car during playback |
| 11 | Set **Flash when channel above** = speed, threshold 0 | Image blinks during playback |
| 12 | ⌘S, reopen | All picture, colour, chroma, audio and object settings restored |
| 13 | **Add Video** with an `.mts`/`.m2ts` file (ffmpeg installed) | Import succeeds after a short conversion; without ffmpeg an error explains how to install it |
| 14 | Export | Output shows every effect exactly as previewed |

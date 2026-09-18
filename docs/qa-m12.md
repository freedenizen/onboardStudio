# QA script — M12 lens unwrap, 360° export, two-vehicle map, map backgrounds

| # | Step | Expected |
|---|---|---|
| 1 | Select a video input, **Lens ▸ Unwrap ▸ Fisheye**, source FOV 150 | The picture's edges straighten; the centre stays put |
| 2 | Drag **View FOV** down to 60, then **Yaw** to 30 | The view zooms in, then pans right; the preview follows every slider move |
| 3 | **Reset view** | Yaw/pitch/roll back to 0, view FOV 90 |
| 4 | With a 360° (2:1 equirectangular) clip: **Unwrap ▸ 360°**, pitch 45 | A flat window looks up into the panorama; no seam at yaw ±180 |
| 5 | Export with **360° ▸ Tag as 360° video** on a full equirectangular frame (unwrap off) | `ffprobe` reports a spherical mapping (equirectangular); QuickTime Player / YouTube show a panorama |
| 6 | Select the track map, **Map Background ▸ Satellite** | Imagery appears behind the outline and lines up with it; rotating the map rotates the imagery too |
| 7 | Set **Imagery ▸ None** | Plain outline again, instantly (no network) |
| 8 | Add a second data input (a second car's log), **Second Vehicle ▸ Data input** | A second (blue) dot follows the second log; changing that input's sync moves only that dot |
| 9 | Save, reopen | Lens, map background and second-vehicle settings survive; old projects open unchanged |
| 10 | Export a range covering all of the above | The exported frames match the preview |

## Results (0.10.0, real GoPro + RaceChrono project at Sonoma)

- **Fisheye unwrap** on the HERO13 clip (Lens ▸ Fisheye, source FOV 150): the picture is straightened and the Lens section shows source FOV, view FOV, yaw, pitch, roll sliders. Dragging **Yaw** to 32° pans the view to the passenger side live; dragging it to 143° (beyond the 150° source) shows black, as expected; **Reset view** restores the defaults.
- **Map Background ▸ Satellite** on the RaceChrono track map: Apple Maps imagery of the circuit appears under the outline within a second of opening and the white trace follows the tarmac exactly; the tile is cached in `~/Library/Caches/OverlayGen/maps`.
- **Second Vehicle ▸ GoPro GPS**: a blue dot is drawn under the orange RaceChrono dot at the same spot (same car, so the two GPS sources agree to within a couple of pixels, which also confirms the auto-sync); the inspector's Second Vehicle section shows the input picker and colour.
- **360° export** verified with the synthetic test rather than a real 360° camera clip (none in the sample set): `ffprobe` reports `Spherical Mapping` / `equirectangular`, and the tagged file still probes and decodes late frames.
- Older projects (without `lens`, `background`, `secondInputID`, `spherical`) open unchanged.

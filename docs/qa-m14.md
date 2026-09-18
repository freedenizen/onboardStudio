# QA script — M14 performance, hardening, parity

| # | Step | Expected |
|---|---|---|
| 1 | `swift run -c release overlaygen bench --project my.overlayproj --export --codec hevc --seconds 60` | Overlay ms/frame, export "× real time" ≥ 1 for 4K HEVC on Apple silicon, resident memory within a few MB of the start |
| 2 | `swift run -c release overlaygen bench --project my.overlayproj --size 3840x2160 --frames 150` | 4K overlay drawing under 25 ms/frame after the first (cache-building) frame |
| 3 | Export a full session (10+ minutes) from the app while watching Activity Monitor | Memory stays flat for the whole export |
| 4 | `swift test --filter Fuzz` | Every mutated fixture is rejected or imported; nothing crashes or hangs |
| 5 | `swift test --filter LongSession` | A two-hour 20 Hz session renders every object at 1280×720 in well under 40 ms/frame with under 200 MB growth |
| 6 | Read `docs/parity.md` against RaceRender's feature list | Every row is ✅, ◐ with a note, or ❌ with the reason |

## Results (0.12.0, real GoPro + RaceChrono project at Sonoma, M2-class Apple silicon)

- `overlaygen bench` (release): 11 overlays at 1080p 4.4–5.8 ms/frame (≈ 180 fps); 4K 17.8 ms/frame (56 fps). The first frame of each plan costs 90–135 ms building gauge faces and fonts.
- Full export of 60 s of the real project: 1080p HEVC 16.2 s (3.7× real time, 111 fps); 4K HEVC 31.0 s (1.9× real time, 58 fps). Resident memory 397 MB → 410–416 MB.
- Before M14 the headless loop grew by one output-sized buffer per frame (2.5 GB over 300 frames at 1080p) because Core Image objects were only autoreleased at the end of a long dispatch block; per-frame pools in `FrameCompositor.render` and the export pump fixed it, and the two-hour session test now guards it.
- Fuzz suites (importers over 11 fixtures × 150 mutations, FIT × 500, GPMF payloads × 1500, MP4 containers × 800, expressions × 3000, spherical × 80) pass. Their first runs found and fixed five real defects: `Int()` traps on absurd values in lap-number runs, resampling, lap-time formatting, the gear readout and the bar readout (a `NaN` from a corrupt file); a GLL sentence with too few fields crashed the NMEA importer; and a mutated MP4 sample table made the box reader loop for 14 minutes (counts are now bounded by the bytes present). The two-hour session renders every data object at 3.5 ms/frame with 0.3 MB of growth.

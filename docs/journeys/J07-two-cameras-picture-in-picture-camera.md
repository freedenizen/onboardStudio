# J7 Two cameras, picture-in-picture, camera switching
*Source: RaceRender multi-camera; RaceChrono PiP export; guide §3 and §6.*

1. Add the main video, then **Project ▸ Add Camera…** with a second file: a second lane and a
   picture-in-picture window appear.
2. **Layout ▸ Side by side** re-frames both cameras.
3. **Layout ▸ Add Segment at Playhead** (after stepping forward) adds a segment; the segment strip
   shows it and the inspector lists it.

Tests: `MultiCameraUITests.testSecondCameraLayoutsAndSegments`. Model: `TimelineTests`,
`TimelineMediaTests`.

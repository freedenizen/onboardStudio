# J2 Track day: GoPro clip + RaceChrono log, gauges, export
*Source: guide §1; RaceRender How To: Data Overlay; Autosport Labs guide; RaceChrono export
tutorial.*

1. Add the video. The sidebar lists it with its size and length; the timeline shows one bar; the
   preview leaves the welcome panel.
2. Add the data file. The sidebar shows the format, channel count and laps; the Getting Started
   checklist ticks "Add a video" and "Add the data".
3. **Project ▸ Apply Template ▸ Classic Dash**: speedometer, tachometer, map, g-force, lap timer,
   best lap and gear appear in the sidebar and on the preview.
4. Play, pause, step, go to start: the transport time changes accordingly.
5. Export: the sheet offers presets, range and background; Export… writes the file and offers
   **Reveal in Finder**. The file exists and has the expected size and duration.

Tests: `JourneyUITests.testTrackDayFromVideoToExport`. Model: `ClipSequenceTests`,
`ExportOptionsTests`; the CLI renders the same fixture project in CI (`onboard render`).

# J4 Sync the data to the picture by hand
*Source: RaceRender Sync Tool and Data Sync Wizard; DashWare synchronisation tab; RaceChrono
"Adjusting video synchronisation".*

1. With a video and a data file, open **Sync** from the toolbar.
2. A panel appears **under the preview**, not over it: the data file, live readouts of what the
   data says at the moment on screen, and nudge buttons for the data and for the video
   (−1s / −.1 / −1f / +1f / +.1 / +1s, where a frame comes from the project's rate).
3. Each nudge applies immediately and is its own undo step, so the loop is nudge, look at the
   picture, nudge again. The rest of the window stays usable throughout.
4. Nudge the data by +1s then +1f; the data input's Synchronization section shows the new offset.
   **Undo** steps back one nudge at a time.

Tests: `SyncUITests.testSyncPanelNudgesLiveAndLeavesTheWindowUsable`,
`SyncUITests.testSyncPanelAlsoMovesTheVideo`. Model: `TimestampSyncTests`, `MotionSyncTests`.

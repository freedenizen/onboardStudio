# J9 Open, edit and save an existing project
*Source: any document app; guide §2.*

1. Open the fixture project (a video with five gauges and a data file with a 1 s offset). The
   sidebar lists its inputs and objects and the preview renders.
2. Hide an object and save with ⌘S; the window title loses its Edited mark.
3. Close and reopen: the object is still hidden.

Tests: `ProjectUITests.testOpenEditSaveReopen` (opens through the Testing menu, saves in place).

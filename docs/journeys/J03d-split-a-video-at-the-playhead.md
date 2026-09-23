# J3d Split a video at the playhead
*Source: Resolve Split Clip (`⌘\`), verified in `docs/conventions.md`.*

1. Select a video. At the very edge there is no second half to make and the status line says so.
2. Step in and **Project ▸ Split at Playhead**. The sidebar gains a second input *and* a second
   camera object, and the timeline gains a segment that swaps them at the cut.
3. **Undo** removes all of it in one step.

Tests: `SplitUITests.testSplitsAVideoIntoTwoHalvesThatSwapAtTheCut`. Model: `VideoSplitTests`.

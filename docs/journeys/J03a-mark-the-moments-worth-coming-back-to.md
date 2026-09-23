# J3a Mark the moments worth coming back to
*Source: Resolve and Premiere marker models; see `docs/conventions.md`.*

1. With a video loaded, **Marker ▸ Add Marker** (**M**) drops a numbered marker at the playhead.
2. It appears in the timeline's marker lane and in the sidebar's **Markers** list.
3. **Previous/Next Marker** (**⇧↑** / **⇧↓**) walk between them, reporting each in the status
   line; past the last one the status line says so rather than jumping to the start.
4. **Delete Marker** removes the selected one, and **Undo** brings it back.

Tests: `MarkerUITests.testMarkersAreAddedListedAndJumpedBetween`. Model: `MarkerTests`.

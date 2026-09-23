# J5 Edit the overlay: add, select, tune, hide, delete, undo
*Source: guide §5; RaceRender display objects and properties; Telemetry Overlay gauge editing.*

1. **Add Object ▸ Speedometer** adds a gauge bound to the data input; it is selected and its
   inspector shows the Gauge Designer with the channel picker.
2. Rename it in the inspector; the sidebar follows.
3. Change the channel; pick a different speed unit.
4. The eye toggles visibility; the sidebar label reflects it.
5. **Project ▸ Delete Selected Object** removes it; **⌘Z** brings it back; **⇧⌘Z** removes it
   again.

Tests: `ObjectEditingUITests.testAddRenameRetuneHideDeleteUndo`.

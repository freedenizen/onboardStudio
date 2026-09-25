# J31 Put an overlay in front of another
*Source: #277 — objects drew in the order they were added, with no way to change it short of
deleting and adding them again; every layout app on the Mac has Keynote's Arrange commands.*

1. The sidebar lists objects front first. Select one (or several, or a group).
2. **Arrange ▸ Bring to Front** (⇧⌘F) or **Send to Back** (⇧⌘B) moves it all the way; **Bring
   Forward** (⌥⇧⌘F) and **Send Backward** (⌥⇧⌘B) one place. The same four are on the row's
   right-click menu. A command that would change nothing is off.
3. Or drag the row up or down the sidebar. Each change is one step of Undo (*Bring to Front*,
   *Change Layer Order*…); a group moves as one.

Tests: `LayerOrderUITests` (the Arrange menu and its keys, with Undo names; a row dragged down
sends the object back). Model: `LayerOrderTests` (one place and all the way, a run of objects,
the ends, groups, a drag in the front-first list).

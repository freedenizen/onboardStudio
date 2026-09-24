# J20 Leave finished work alone, and keep a cluster together
*Source: #90 — any visible object moved the moment it was clicked, and a speedometer with its
label and backing shape took three drags to move.*

1. Select the Speedometer in the sidebar, ⌘-click the Timer: the inspector says *2 Objects*.
2. **Project ▸ Group** (⌥⌘G): *Group of 2*. On the preview, a click on either selects both, and
   a drag moves both.
3. **Project ▸ Lock** (⌘L): both padlocks close; Delete says locked objects are not deleted.
4. Unlock, **Ungroup** (⇧⌥⌘G): still both selected. Delete removes both; ⌘Z brings both back.

Tests: `GroupLockUITests` (`testGroupLockUngroupDeleteUndo`, `testDraggingAGroupMemberMovesTheGroup`).
Model: `LockAndGroupTests`.

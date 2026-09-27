# J32 Try an edit and walk away from it
*Source: #300 — every edit used to be written into the project file a few seconds after it was
made, so an experiment could not be abandoned: closing never asked, and the file already held it.*

1. Open a saved project and change something. The window's title shows *Edited*; the project file
   on disk is still the one last saved, however long the change sits there.
2. Close the window (⌘W). The app asks whether to save: **Save** writes the changes, **Don't Save**
   leaves the file exactly as it was.
3. If the app quits unexpectedly first, the changes were kept aside: on the next launch the project
   reopens with them, still marked *Edited* and still unsaved.

Tests: `SavingUITests` (an edit left for longer than the autosave interval is not in the file
after Don't Save; after the app is killed, the project reopens with the unsaved edit).

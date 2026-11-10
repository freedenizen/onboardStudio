# J40 The project and the logbook know each other
*Source: #349 — if the logbook only filled from its own Add Track Day…, the sessions people actually
work on would never reach it, and the project's details would be typed again though the logbook
already knew them.*

1. **Project ▸ Add Data File…** as always. Once the file has loaded, the status bar says
   *Entered Sonoma in the logbook*: the session is in **Window ▸ Logbook** too, and the input
   remembers which entry is its own. A file already in the logbook (the same bytes) is the same
   entry, not a second one, and so is another export of a session the logbook has (#465).
   Settings ▸ Logbook turns this off.
2. The project's blank **car** and **driver** details are filled from the entry, as the track and
   the day already are from the file.
3. Save the project and the entry's detail lists it under **Projects**, as a link that opens it;
   every video exported from the project is listed under **Exports**, as a link that shows it in
   the Finder.
4. Move the data file: a project whose path no longer finds it takes the place the logbook's
   bookmark still knows (*Found session_3.csv where the logbook last saw it*, undoable); a logbook
   entry whose path is stale learns the project's. Once, on opening.
5. Opening a saved project changes nothing it renders: none of this touches a project the user
   did not just add a file to.

Tests: `LogbookLinkUITests.testADataFileAddedToAProjectIsEnteredInTheLogbook`. Model:
`LogbookLinkTests`.

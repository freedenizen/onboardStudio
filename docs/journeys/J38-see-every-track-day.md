# J38 See every track day
*Source: #347 — once sessions are kept they need a window: every track day in one list, narrowed by
circuit, car or year, with the numbers a driver asks about, and a way from any row into the work.*

1. **Window ▸ Logbook** (⌃⌘L). The sidebar lists **All Sessions**, then the circuits, cars and
   years the logbook knows, each with how many sessions; the table shows date, circuit, car, laps,
   best, optimal and fastest rolling lap, sortable by any column.
2. Type in the search field to narrow by circuit, car, driver, notes, tags or file name; pick a
   circuit, car or year in the sidebar to narrow to it.
3. Select a session: the detail shows its numbers, every lap with the best marked, the notes, the
   projects made from it and where the file is.
4. **Open as Project** starts a new project with the session's data file; **Add to Current
   Project** adds it to the project in front. **Show in Finder** and **Remove from Logbook…**
   (the file is not touched).
5. **Add Track Day…** in the toolbar, or files and folders dropped on the window, enter more.

Tests: `LogbookUITests.testTheLogbookListsSessionsAndAddsOneToTheProject`. Model:
`LogbookFilterTests`, `LogbookTests`.

# J55 The Logbook from the menu bar and the keyboard
*Source: #450 — the app opens on the Logbook, but the menu bar was the editor's: nothing in it acted
on a session, the Logbook's three views had no menu items or keys, Edit was dimmed throughout, and
the Project menu stood enabled with no project open, its items doing nothing.*

1. Open the Logbook (⌃⌘L) and select a session. The **Session** menu, between View and Project,
   holds what the buttons at the foot of its detail do: **New Project from Session** (⇧⌘N), **New
   Project from Session with Template**, **Add to Current Project**, **Coach…** (⌃⌘C), **Replay…**,
   **Compare With**, **Export Coaching Debrief…**, **Show in Finder** (⇧⌘R) and **Remove from
   Logbook…** (⌘⌫). With no session on show they are dimmed.
2. **Session ▸ Coach…**, or ⌃⌘C, opens Coaching on that session. In a project ⌃⌘C is Project ▸
   Coaching…, as before: each window's item holds the key while it is in front.
3. ⌘2 shows Trends, ⌘3 the Season, ⌘1 the sessions again — also under **View**, with a check by
   the one on show. **View ▸ Customize Toolbar…** can show the toolbar's names under its icons.
4. ⌘F puts the keyboard in the search field. While typing there, ⌘⌫ deletes to the start of the
   line, as in any text field; with the table of sessions in hand, ⌘⌫ asks to remove the selected
   session, and **Cancel** keeps it.
5. With no project in front, the Project, Arrange, Marker and Playback menus are dimmed, except
   **Map Attributes…**, which works on every project's mapping without one. Their keys are left
   alone, so Space, Delete and the letters do nothing in the Logbook.
6. **File ▸ Add Files to Logbook…** adds a day's files from any window: on the day chosen in the
   Logbook, else each on its own day. The Logbook's exports and **Import Logbook Export…** are in
   File while it is in front.

Tests: `LogbookMenuUITests.testTheSessionMenuActsOnTheSelectedSession`,
`LogbookMenuUITests.testTheKeysSwitchViewsFindAndRemove`; File ▸ Add Files to Logbook… in
`TrackDayUITests.testAFolderOfSessionsIsEnteredAndReportedPerFile`.

# J49 Get coached straight from the logbook
*Source: #396 — the session is in the logbook with its file, laps and circuit known; opening a
project just to see where its laps lost time was a detour.*

1. Select a session in the Logbook and **Coach…**. The Coaching window opens on that session
   with no project: the lap, what it is compared with (its best, the fastest rolling lap, the
   optimal lap, any other lap, and the logbook's other sessions at the circuit — the personal
   best here, the last visit), and *Line up by position*, as from a project. The choices are kept
   with the session, so the next Coach… on it starts where this one left off.
2. The opportunities, the corner table and a corner's detail read as they do from a project.
   What needs a picture or a project — Show Me moving a playhead, Compare in Video, the
   next-session plan — is not there; in its place, **Make a Project** opens a project from the
   session (its data file, its clips, the last template used) and the window follows it.
3. **File ▸ Export Coaching Sheet as PDF…** and **as Markdown…** write the sheet from the window
   as they do from a project; the window's footer says where it went.
4. **Project ▸ Coaching…** (⌃⌘C) from an open project brings the window back to that project.

Tests: `CoachingFromLogbookUITests.testASessionIsCoachedWithNoProjectOpen`. Model:
`CoachingSettingsTests` (the choices on an entry), `LogbookTests`.

# J48 Keep the day's video with its sessions
*Source: #394 — a track day is data files and video files; a logbook that kept only the data
sent the driver back to the camera's card every time a project was made.*

1. Choose a day in the Logbook and **Add Files…** with the camera's clips among the files (or
   drop them on the window). Each recording — GoPro chapters joined — is listed under **Clips**
   in the day's header with when it started and how long it ran, and the sheet's line says whose
   picture it is: *GX010037.MP4 — video, 12:04–12:31, 27 min: the picture of Sonoma, 23 Aug 2026,
   12 laps, best 1:56.88*. The camera's clock (a GoPro's GPS clock, else the file's date) against
   the log's decides; a clip that overlaps no session says *no session at that time, assign it in
   the logbook*.
2. A clip with GPS in it and no session of its own is entered as a session too, as before, and is
   then the picture of that session.
3. The pop-up beside a clip changes whose it is, or leaves it unassigned. A session's detail lists
   its clips under **Video**.
4. **New Project** on a session starts a project with its clips and its data file, laid out with
   the template the last New Project used (Classic Dash to begin with); the arrow on the button
   offers every template, or a blank project. The toolbar's **New Project** menu makes the same
   project while the session is selected, and names the session. The data lines up with the
   picture by the clocks, as it does when the files are added by hand.
5. A logbook exported as files lists the clips by path; the videos are not copied.

Tests: `LogbookClipsUITests.testAClipIsAssignedAndANewProjectHasVideoAndData`. Model:
`ClipMatcherTests`, `TrackDayImportTests.aClipGoesOnTheDayAndIsMatchedOrLeftToAssign`.

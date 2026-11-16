# J79 Hand a session's telemetry to another app
*Source: #563 — telemetry came into the app and never went out: no way to give a friend or an
instructor one lap in a format their app reads, to look at the line in Google Earth, or to carry a
trim, a split or a start/finish line made here into another tool.*

1. In the Logbook, choose a session and click **Export Telemetry…** (also on the row's right-click
   menu and in the session menu).
2. Choose the format: **CSV** (every channel the file has, each column named with its unit, the
   time from the session's start, the time of day when the file knows its clock, and the lap),
   **GPX** (the path with times, height and speed, a segment per lap), **KML** (a line per lap, for
   Google Earth) or **VBO** (Racelogic's format, with the start/finish line when the session has
   one).
3. Choose **The whole session** or one lap; the best lap is chosen to begin with.
4. Click **Export…** and choose where it goes; the status line says what was written.
5. On the command line: `onboard export-data <file> --format gpx --lap best`.

What is written is the session as the app reads it. The app's own readings — the delta to the
best lap, the projected lap time, the GPS rate — are left out; another tool works out its own.
Without the file's clock, a GPX and a VBO say where but not when, rather than make a date up.

Tests: `ExportTelemetryUITests.testTheBestLapIsWrittenAsGPX`. Model: `TelemetryExportTests`.

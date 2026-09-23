# J22 Send the details of a problem
*Source: #152 — the only channel back from a user was an issue written from memory.*

1. With a project open, **Help ▸ Export Diagnostics…**, and save the zip.
2. It holds `about.txt` (versions, Mac, ffmpeg), `log.txt`, `activity.txt`, `project.json` and a
   `data/<file>.json` description per data file, plus recent crash reports; no media.
3. After a crash, the next launch asks whether to make one.

Tests: `DiagnosticsUITests.testExportDiagnosticsWritesOneZipWithTheProjectAndItsData`. Model:
`DiagnosticsTests`. The post-crash offer stays manual.

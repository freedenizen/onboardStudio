# J56 Export your best lap
*Source: #467 — what a driver most often wants from a session is one lap, usually the best one. The
range was the last thing in the Export Video sheet, a lap range began at lap 1 (the out-lap, as a
rule) with no lap's time shown, and the file was called "Onboard Studio Export".*

1. **Export** (⌘E). **Range** is the first thing in the sheet; choose **Laps**.
2. **From** and **To** both show the best lap, marked *(best)*; each menu lists every lap with its
   time (*Lap 7 · 1:42.31*), and a partial one says so.
3. For a run of laps, move either end: one moved past the other brings the other with it, so the
   range never runs backwards.
4. **Export…**: the file is named after the project — its file once saved, otherwise its window's
   name, which for a project made from a Logbook session is the session (*Sonoma Raceway, Sep 22,
   2026.mp4*).

Tests: `ExportBestLapUITests.testTheBestLapIsOfferedFirstAndExportedUnderTheProjectsName`. Model:
`ProjectNamingTests`.

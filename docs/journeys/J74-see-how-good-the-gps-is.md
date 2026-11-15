# J74 See how good a session's GPS is
*Source: #555 — a phone logging once a second and a 25 Hz logger looked the same, and Coaching
quoted brake points to the metre from either, so a driver could not tell a fact from noise.*

1. Add a data file to a project and choose **Project ▸ Show Import Report…**. Above the columns,
   the **GPS** line rates the positions **Good**, **Fair** or **Poor** and says what it measured:
   positions a second, the logger's accuracy, HDOP and satellites when the file has them, and how
   close a distance read from them can be (*distances to about 15 m*).
2. Under it, a sentence for each thing that counts against the data: too few positions a second,
   a dropout while moving, a position that jumped, a poor accuracy, HDOP or satellite count, or a
   lap about twice the usual length because the start/finish line was missed.
3. Add a gauge or graph and choose **GPS rate** as its channel to watch the rate through the lap;
   it reads zero through a dropout.
4. Add files to the Logbook: a file whose GPS is fair or poor says so in its line of the report
   (*added: Sonoma, 4 laps, best 0:41.20, GPS fair*).
5. In the Logbook, the **GPS** column shows each session's rating, with the reasons in its help
   tag; choose a session and its details say the same beside **GPS**.
6. Coach a lap from coarse data: the notes say "Braked ≈ 25 m earlier than your best lap" and
   why, and a corner a dropout runs through gets no brake-point note.
7. **Settings ▸ GPS Quality** changes what counts as good and poor; every rating follows.

Tests: `GPSQualityUITests.testTheImportReportSaysHowGoodTheGPSIs`,
`GPSQualityUITests.testTheLogbookSaysHowGoodEachSessionsGPSIs`,
`GPSQualityUITests.testTheThresholdsInSettingsRateTheData`. Model: `GPSQualityTests`,
`LogbookGPSTests`, `GPSThresholdsTests`, `TrackDayImportGPSTests`, `CoachingGPSPrecisionTests`,
`ExactDistancesMigrationTests`.

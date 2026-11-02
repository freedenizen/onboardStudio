# J43 Compare with a logbook session
*Source: #352 — the lap a driver most wants to be measured against is in the logbook: the personal
best at this circuit, last visit's best, the same corner in the other car. It meant finding the
file and adding it as an input first.*

1. **Project ▸ Coaching…**. When the logbook has other sessions at this circuit, **Compared with**
   gains a **Logbook** section: **Personal best here**, **Last visit**, then every session by date
   and car.
2. Choose one. Its file is read in on demand and the lap is read against that session's best lap
   (or the lap named), lined up by position as a lap from another file is; the headline names the
   session and the date. The choice is saved with the project and is one undo.
3. A Corner Callout, the track map's coaching options and the debrief read the same reference when
   the project renders. Compare in Video is not offered for a logbook session, whose video is not
   in the project: add the session as an input for that.
4. From the command line: `onboard coach session.csv --reference logbook:pb`, `logbook:last` or
   `logbook:2026-08-23`.

Tests: `CoachingLogbookUITests.testALogbookSessionIsAReference`. Model: `LogbookReferencesTests`,
`CoachingSettingsTests`.

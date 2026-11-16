# J75 Note what was on the car
*Source: #559 — tyres and setup were one line of text each, so a driver could not say which
pressures or which bar setting a session was driven on, nor keep a setup to use again.*

1. In the Logbook, choose a session. Under **Conditions**, **Setup** says what its sheet notes
   (*Base · 30/28 psi cold · 6 more*) or *Not noted*; **Edit Setup…** opens the sheet.
2. Note as much or as little as you like: the tyre set, pressures at each corner cold, hot and how
   much was bled, camber, toe, ride height, bump and rebound clicks, the anti-roll bars and the
   wing. The pressures are in psi, bar or kPa, from the pop-up beside **Tyres**; ride heights follow
   the speed setting (inches with mph, millimetres otherwise); toe is in mm, inches or degrees.
3. Name the setup and click **Save to Car** to keep it with the session's car. **Saved Setups**
   loads one onto another session; saving under a name the car already has is **Update Saved
   Setup**.
4. Tick **Start new sessions in the *car* with this setup** to make it the car's starting setup:
   a session added later in the car, with no setup of its own, starts with it.
5. **Done** keeps the sheet as one step of **Edit ▸ Undo** (*Undo Change Setup*); saving and the
   starting setup are steps of their own.
6. A track day has a sheet too: a session added to the day starts with the day's.

Tests: `SetupSheetUITests.testASetupIsNotedSavedToTheCarAndUndone`. Model: `SetupSheetTests`,
`TrackDayImportSetupTests`.

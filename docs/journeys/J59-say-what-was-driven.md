# J59 Say what was driven, and keep the garage
*Source: #489 and #490 — a new driver adds their files before anything else, and every session
arrives with no car, gathered under "No car", with nothing saying so. The garage the logbook keeps
(each car's name and notes) was written and never shown, and a misspelt car stayed in it after it
was put right everywhere else.*

1. **Add Files…** in the Logbook with no day chosen (or **File ▸ Add Files to Logbook…**), and
   choose the folder of a first track day.
2. The report says no car is set for the new day (or *the 3 new days*) and asks what was driven.
   Type it, or pick a car the logbook knows from the menu beside the field, and **Set Car**: the
   line now says it is the car of those days and their sessions. A car typed and not set is set
   when the report is closed. A day that already names a car gives it to the sessions that join it.
3. The car is under **Cars** in the sidebar. Choose it: above its sessions are its name, how many
   sessions, days and circuits it has and when, and **Notes** for whatever is worth keeping about it.
4. **Rename…** changes its name on every day and session. Typing another car's name makes the two
   one car under that name, both cars' notes kept — how a misspelling is folded into the car it
   should have been.
5. A car typed by mistake and put right on the day or the session leaves the garage with it. A car
   with notes stays when nothing names it any more — one that was sold, or borrowed for a day — and
   is listed with no sessions, saying so; **Remove from Garage…** takes it out, after asking. A car
   that is driven cannot be removed.
6. In a project, **Details ▸ Car** offers the same cars from the menu beside the field.

Tests: `GarageUITests.testAFirstImportAsksForTheCarAndTheGarageShowsIt`,
`GarageUITests.testACarNothingNamesIsTidiedOrRemoved`. Model: `GarageTests`, `TrackDayCarTests`.

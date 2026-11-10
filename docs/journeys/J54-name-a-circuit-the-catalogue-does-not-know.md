# J54 Name a circuit the catalogue does not know
*Source: #455 — a file from a place the catalogue does not know, naming no track, became a circuit
of its own in the sidebar, called after the file: `track`, `activity`, `generic`. Nothing could
rename it, and two files that happened to be named alike counted as two visits to one place.*

1. Add files from a kart track, an airfield, a circuit too new or too small for the catalogue.
   Sessions whose trace is recognised nowhere and whose file names no track are gathered in the
   sidebar's **Circuits** under one entry, **No circuit**, the way **No car** ends the cars. Each
   keeps its file's name as its title, so it can still be told apart and searched for. There is
   no personal best and no Trends among them: they are not visits to one place.
2. Choose their day in the sidebar. Its header has a **Circuit** row above Car: a search field
   when the day has no circuit. Type the name. The catalogue's matches are offered first, then
   names typed into the logbook before (*"Stadium", as Typed Before*), then **Use "…" as Typed**.
3. Choose one. The day takes the name, the sidebar's day keeps its place under its new label, and
   every session of the day that had no circuit is now at that one: it moves out of **No
   circuit** into a circuit of its own, with a personal best, Trends and the other sessions there
   to compare with. A session that said where it was — recognised by its trace, or named by its
   file — keeps its own.
4. The second visit is the same: add its files, name the day with the name offered from last
   time, and the two visits are one circuit. Add them to a day that is already named and they
   take its circuit as they are added; so does a session with no circuit that lands, by its
   date, on a day that has one.
5. A circuit named wrongly is corrected in the same row: **Change**, choose again (or **Keep …**
   to leave it), and the sessions that were filed under the old name follow.

Tests: `TrackDayUITests.testSessionsWithNoCircuitAreGatheredAndTakeTheNameTheirDayIsGiven`. Model:
`LogbookFilterTests.sessionsThatNameNoCircuitAreOneGroupAndNotOneEach`,
`TrackDayTests.aDaysCircuitGoesToTheSessionsThatHadWhatItHad`,
`aSessionWithNoCircuitTakesTheCircuitOfTheDayItJoins`, `anUndatedSessionGoesOnTheDayItsFileIsDated`,
`PersonalBestsTests.thereIsNoPersonalBestAtNoCircuit`.

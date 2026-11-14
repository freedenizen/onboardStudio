# J65 Say which configuration of a circuit was driven
*Source: #549 — a circuit was one place to the app: the club course's laps and the long course's
went into one personal best, one Trends chart, one set of goals and one plan, and the circuit kept
one start/finish and one set of turn names, whichever layout they were for.*

1. In the Logbook, choose a session. Under **Car** and **Driver**, type the layout it drove in
   **Configuration** — *Club Course* — or choose one already named at that circuit from the menu
   beside the field. Leave it empty for the circuit's usual layout.
2. The session moves to its own row under **Circuits**, *Sonoma Raceway — Club Course*, with its own
   card: personal best, last visit, goals, plan and Trends, none of them mixed with the usual layout.
3. **Edit ▸ Undo Change Configuration** puts it back.
4. In a project, the data file's **Track** section has the same **Configuration** field. Choosing
   one uses the start/finish, sectors and turn names saved for that configuration, and **Save
   Start/Finish, Sectors and Corner Names for This Track** saves them for it.
5. Once a configuration has named turns, the next files added at that circuit — to the Logbook or
   to a project — are filed under the configuration whose turns they drive, without being asked.

Tests: `ConfigurationUITests.testASessionOnTheClubCourseIsItsOwnCircuitUntilUndone`. Model:
`CircuitConfigurationTests`, `ConfigurationImportTests`.

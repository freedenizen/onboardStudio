# J58 See how the new day went
*Source: #459 — a returning driver adds the new day, then wants to know whether it was better than
the last. The import ended with a count of files and the session table; nothing said that progress
could now be read, or where.*

1. **Add Files…** in the Logbook (or **File ▸ Add Files to Logbook…**), and choose the day's files
   or folder.
2. When they are in, the sheet has a line for each circuit under the count: the day's best lap,
   and how it compares with your last visit there (*0.84 s quicker than your last visit (12 Oct) —
   a personal best*). On a first visit it says so, and that Trends begins with the next day there.
3. **Show Trends** opens the Logbook on that circuit's Trends, the circuit chosen in the sidebar.
   After a first single session somewhere, or files from more than one circuit, the button is
   **Show Season**. From a project, the button opens the Logbook window too.

Tests: `ImportProgressUITests.testASecondSessionLeadsToTheCircuitsTrends`,
`ImportProgressUITests.testAFirstVisitLeadsToTheSeason`. Model: `ImportProgressTests`.

# J14 Find out why a file imported badly
*Source: #149 — the channel list shows what survived and says nothing about what did not.*

1. Add a file whose columns are awkward — repeated names, unnamed analog inputs, sensors that
   never move. Its inspector says in a line how the import went; choose **Project ▸ Show Import
   Report…**, or ⌘2 in the attribute window, for the whole report.
2. It shows only the columns worth a look: which of three columns called `speed` kept the role,
   which read the same number all session, which units were not recognised.
3. *Show every column* lists the rest; a file that read cleanly says so in one line.

Tests: `ImportReportUITests.testExplainsWhatBecameOfEachColumn`,
`testCommandDigitsSwitchTheWindowsView`, `testShowImportReportOpensOnTheReport`,
`testTheDataInspectorHasOneWayToTheAttributes`. Model:
`ImportReportTests`, `ImportReportNotesTests`, `AttributeFilterTests`.

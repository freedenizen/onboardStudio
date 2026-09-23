# J13 Tell the app what your channels mean
*Source: #111, #89, #191, #192 — attributes are the app's words for what a value means, and every
logger names its channels differently.*

1. Add a data file, select it and choose **Project ▸ Map Attributes…** (⌥⌘A) or **Map
   Attributes…** in its inspector. The window opens on that file and lists one row per
   attribute, not per column, so nothing in it depends on which logger wrote the file.
2. The sidebar chooses the level: all projects, this project, or this input.
3. A row nobody has touched still says which column feeds it — the placeholder reads
   `Automatic (speed)` — so it is clear what the importer matched.
4. Point **Brake pressure (front)** at the `brake_pressure_front` column by typing into *From*,
   set *Shows* to `bar`, and the row reports `kPa → bar`.
5. An attribute the file does not supply stays out of the way until *Show every attribute*.
6. A channel the file names itself — `canbus:analog_1` — is offered as a **source**, never as a
   row of its own.
7. **All of it from the keyboard** (#200): ⌘F, type `pressure (front)`, Return lands in that row's
   *From* field, type `brake_pressure_front` and Return. Tab walks the rows in reading order and
   Escape abandons a half-typed column.

Tests: `AttributeMappingUITests` (mapping units, hiding unsupplied attributes, the scope sidebar,
the resolved source, `testTabWalksTheTableInReadingOrder`,
`testFilterAndReturnMapAnAttributeWithoutTheMouse`, `testEscapeAbandonsATypedColumn`,
`testTheShortcutOpensTheWindowOnTheSelectedFile`),
`ImportReportUITests.testAPressureAttributeIsMappedToAColumnAndShownInBar`,
`testASourceChannelIsNotListedAsAnAttribute`. Model: `AttributeMappingTests`,
`AttributeVocabularyTests`, `DisplayUnitTests`, `AttributeFilterTests`, `AttributeMappingScopeTests`.

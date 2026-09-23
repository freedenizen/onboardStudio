# J3e Trim and split a data file
*Source: #54 — the same editing verbs applied to data, not just video.*

1. Select the data input and step the playhead in. **Project ▸ Trim Start to Playhead** moves the
   data's own trim, shown in seconds in the inspector's *Trim* section.
2. **Undo**, then **Project ▸ Split at Playhead** gives a second data input, with the gauges
   reading it duplicated so they keep drawing after the cut.
3. **Undo** removes the split in one step.

Tests: `DataEditingUITests.testTrimsAndSplitsTheDataFile`. Model: `SessionTrimTests`.

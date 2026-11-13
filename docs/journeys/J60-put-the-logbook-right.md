# J60 Put the Logbook right
*Source: #454 — a new driver's first import goes partly wrong: sessions on the wrong day, one that
should not be there. Nothing in the Logbook could be undone, a removal asked first and was final,
nothing could be right-clicked, the table selected one row, and a session could not be moved to
another day — only removed and added again.*

1. In the Logbook, click a session and Shift-click two rows further down: the detail column says
   *3 Sessions Selected*, where and when they were driven, and offers their **Car**, **Move to Day**
   and **Remove 3 Sessions**.
2. **Remove 3 Sessions** takes them out with no question. **Edit ▸ Undo Remove 3 Sessions** (⌘Z)
   brings them back, and **Redo** removes them again. Every change in the Logbook is undone the same
   way, named for what it did: a car, a circuit, a day's notes, an import, a car renamed.
3. Right-click a session that is on the wrong day: **Move to Day** lists the day its own date and
   circuit say, the days at its circuit, then the others. Choose one and the session moves, with
   its clips; it takes the new day's car and driver if it had the old day's.
4. Or drag the session from the table onto a day in the sidebar.

Tests: `LogbookCorrectionsUITests.testSeveralSessionsAreRemovedAndUndone`,
`LogbookCorrectionsUITests.testASessionIsMovedByItsMenuAndByADrag`, `LogbookMenuUITests` (⌘⌫ and
⌘Z). Model: `LogbookCorrectionsTests`.

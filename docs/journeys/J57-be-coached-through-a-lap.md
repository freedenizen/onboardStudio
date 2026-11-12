# J57 Be coached through a lap
*Source: #458 — the Coaching window laid everything out at once: pickers, three cards cut off at a
line, a plan, a table of every corner and a detail pane. A driver who wanted to be taken through
the session had to assemble it from the parts.*

1. **Project ▸ Coaching…** (⌃⌘C), or **Coach…** on a session in the Logbook. The window opens on
   the walkthrough: **The Lap** says, in a sentence, how far behind the lap finished and against
   what; **Change…** chooses the lap, what it is compared with and how the two are lined up.
2. **Next** (Return): the biggest loss first, one corner per step — *Turn 4 · 1 of 3* — with what
   happened, the whole of what to try, the corner on the map with both lines and where the time
   went phase by phase. **Watch** plays the corner in the window — this lap's, then the compared
   lap's when it was filmed — from the project's picture, or from the Logbook from the day's clips;
   with no video of the corner it says so (#516). **Try this next time** is on; turn it off for a corner you will leave.
   **Back** (⌘[) goes a step back and keeps what was chosen.
3. After the third corner, **Your Plan**: the chosen corners as experiments in the analysis's own
   words, editable. **Save Plan** keeps it for the circuit — there when preparing to go back and on
   the Season page — and in the project, undoably, when there is one. From the Logbook it needs no
   project; a session whose circuit the Logbook does not know says so, and cannot keep a plan.
4. **All Corners**, in the toolbar, is the whole analysis at once (J33); the window opens next time
   on whichever was used last.

Tests: `CoachingWalkthroughUITests.testTheLapItsCornersAndAPlanOneStepAtATime`,
`CoachingWalkthroughUITests.testASessionIsWalkedThroughWithNoProjectOpen`. Model:
`CoachingWalkthroughTests`, `CornerFootageTests`, `RecordingAssetTests`. Watch playing real footage
is checked by hand: the fixtures' videos are seconds long and reach no corner.

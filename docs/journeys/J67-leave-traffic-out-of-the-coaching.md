# J67 Leave traffic out of the coaching
*Source: #571 — a corner where another car held the driver up was ranked as an opportunity and got
advice on the driver's braking and throttle, and the lap's slow corner widened that corner's
consistency spread, though nothing the driver did there was their choice.*

1. **Project ▸ Coaching…** (⌃⌘C), or **Coach…** on a session in the Logbook, and the lap to read.
2. On a corner's step of the walkthrough, **Leave This Corner Out ▸ Held Up by Traffic** (or
   **Under a Flag**). The reading starts again without it: the lap's sentence ends "…, 1.20 s of it
   held up by traffic", and the corner is listed as left out. In the video, its Corner Callout
   says "Turn 4: held up by traffic" and nothing more.
3. In **All Corners** the table's Phase column reads *traffic* or *flag* and its time is grey;
   right-click a row for **Mark Turn 4 as Traffic**, **Mark Turn 4 as a Flag** or **Clear Traffic
   Mark**, or use the mark at the top of the corner's detail (*Driven Freely*, *Held Up by
   Traffic*, *Under a Flag*), which also says what the mark does.
4. Every mark is one undo step — **Edit ▸ Undo Mark Traffic**, **Undo Mark Flag**, **Undo Clear
   Traffic Mark** — in a project; from the Logbook the mark is kept with the session.

Tests: `CoachingTrafficUITests.testACornerHeldUpByTrafficIsLeftOutOfTheCoaching`. Model:
`TrafficTests`, `CoachingSettingsTests.trafficMarksRoundTripApplyToTheirInputAndAreAbsentInOlderSettings`,
`CornerExportsTests.aCornerMarkedAsTrafficIsNoOpportunityClipAndTheMarksReachTheSession`,
`CornerCalloutTests.aCornerMarkedAsTrafficSaysSoAndNothingMore`.

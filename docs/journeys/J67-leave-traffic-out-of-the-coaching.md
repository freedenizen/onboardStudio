# J67 Leave traffic out of the coaching
*Source: #571, #572 — a corner where another car held the driver up was ranked as an opportunity and got
advice on the driver's braking and throttle, and the lap's slow corner widened that corner's
consistency spread, though nothing the driver did there was their choice; and every such corner had
to be found by watching the video.*

1. **Project ▸ Coaching…** (⌃⌘C), or **Coach…** on a session in the Logbook, and the lap to read.
2. On a corner's step of the walkthrough, **Leave This Corner Out ▸ Held Up by Traffic** (or
   **Under a Flag**). The reading starts again without it: the lap's sentence ends "…, 1.20 s of it
   held up by traffic", and the corner is listed as left out. In the video, its Corner Callout
   says "Turn 4: held up by traffic" and nothing more.
3. In **All Corners** the table's Phase column reads *traffic* or *flag* and its time is grey;
   right-click a row for **Mark Turn 4 as Traffic**, **Mark Turn 4 as a Flag** or **Clear Traffic
   Mark**, or use the mark at the top of the corner's detail (*Driven Freely*, *Held Up by
   Traffic*, *Under a Flag*), which also says what the mark does.
4. The telemetry points at corners worth checking: under the lap's sentence, "Possibly traffic in
   Turn 1 and Turn 2. Check the video before you trust their notes."; on each one's step and in
   its detail, what it saw ("You lifted for 40 m where most of your other laps were flat out and
   Turn 1 took 1.86 s longer than it usually does") with **Mark as Traffic** and **Not Traffic**.
   Marking leaves the corner out as above; Not Traffic stops the suggestion (**Edit ▸ Undo Dismiss
   Traffic Suggestion**). In the table a suggested corner has a small car by its number, and its
   context menu has **Dismiss Traffic Suggestion**.
5. Every mark is one undo step — **Edit ▸ Undo Mark Traffic**, **Undo Mark Flag**, **Undo Clear
   Traffic Mark** — in a project; from the Logbook the mark is kept with the session.

Tests: `CoachingTrafficUITests.testACornerHeldUpByTrafficIsLeftOutOfTheCoaching`,
`CoachingTrafficUITests.testTheTelemetrysTrafficSuggestionsAreTakenOrDismissed`. Model:
`TrafficTests`, `TrafficSuggestionsTests`,
`CoachingSettingsTests.dismissedSuggestionsRoundTripApplyToTheirInputAndAreAbsentInOlderSettings`, `CoachingSettingsTests.trafficMarksRoundTripApplyToTheirInputAndAreAbsentInOlderSettings`,
`CornerExportsTests.aCornerMarkedAsTrafficIsNoOpportunityClipAndTheMarksReachTheSession`,
`CornerCalloutTests.aCornerMarkedAsTrafficSaysSoAndNothingMore`.

# J51 Replay your laps in 3D
*Source: #413–#415 — race.ngoansx.com shows laps as cars racing round a 3D circuit; the app had
the laps, the circuit's shape and the logbook's other sessions, and only numbers to show for them.*

1. Select a session in the **Logbook** and **Replay…** (or **Window ▸ Replay**, ⌃⌘R, for the
   project in front; or **Replay** in the Coaching window's toolbar). The Replay window opens
   with the session's three quickest laps ticked in the list on the left and racing from the
   line: the circuit as a road with kerbs over its real elevation, each lap's line painted on
   the tarmac in its colour, a car per lap with its name above it.
2. The list offers every complete lap of the session and, under their own headings, the
   logbook's other sessions at the circuit (another day, another car, a friend's logbook
   import); tick one and its file is read in and its lap joins the race in the next colour.
3. **Play** (Space) and the cars go; the standings at the bottom left show each car's place and
   gap to the leader, and a click on a car follows it. The HUD at the top left reads the followed
   car's speed, lap time and gap; the map at the top right shows where everyone is.
4. The toolbar's camera control: **Chase** behind the car, **Trackside** from a post beside the
   track, **Above** straight down, **In Car**, and **Free** (drag to orbit, scroll or pinch to
   zoom; the keys 1–5 do the same). **Go to Turn ▸** jumps to just before any corner; the
   scrubber and ← → step through the lap; **Speed** slows or quickens the replay.
5. A session whose logger recorded no altitude gets a flat road; nothing is guessed from a map.

Tests: `ReplayUITests.testLapsAreReplayedFromTheLogbook`. Model: `TrackModelTests`,
`ReplayMeshTests`, `TrackSceneTests`.

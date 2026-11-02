# J45 Set two cars against each other
*Source: #354 — a driver with two cars wants to know not just which is quicker but where: which
corners one car gains in, and what that says about the driving in the other.*

1. **Window ▸ Logbook ▸ Trends** for a circuit where the logbook has sessions in two cars.
2. The lap-time chart narrows by **Car**; at the foot, **Car against car** picks two cars (the two
   it has most sessions in at first). Each car's best lap at the circuit is read in once and set
   against the other, lined up by position as two drivers' laps are.
3. A sentence says which is quicker and by how much; the speed traces of both laps are drawn over
   distance; and every corner gets a sentence naming the car: *Turn 4: the GR86 is 0.31 s quicker
   than the Miata: brakes 12 m later, carries 5 km/h more through the apex, leaves 3 km/h faster.*

Tests: `CarVersusCarUITests.testTwoCarsAtOneCircuitAreCompared`. Model: `CarVersusCarTests`.

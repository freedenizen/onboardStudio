# J78 See how much of the car's grip was used
*Source: #558 — the G-force object drew the dots, but nothing said how much of the car's grip a
lap used, or whether braking ran into turning or stopped before it, a well-known sign of a driver
still learning.*

1. Add a session to the Logbook in a car. Its details gain **Grip**: how much of the car's grip its
   best lap used while braking and turning, how much of the lap was near the limit, and how long
   it coasted (*Used 82% of the grip braking and turning · 14% of the lap near the limit*).
2. Under it, what the grip is: the most combined G the car has shown in conditions like these —
   its sessions on the same kind of surface, on the same tyres and in much the same air when those
   were noted — as a range from the typical session to the best (*Against 1.02–1.15 G from 6
   sessions, dry, RE-71RS*). Too few sessions alike, and the air and then the tyres are let go;
   wet grip never stands for dry.
3. When braking stopped before turning, it says where (*Braking stopped before turning into Turns 2
   and 5*).
4. Choose the car under **Cars**: its card shows **Grip** on a dry and a wet surface, and a stepper
   scales it (*Adjusted to 105% of what it has shown*) when the car has more grip than its sessions
   have shown. The scale is a step of **Edit ▸ Undo** (*Undo Adjust Grip*).

Tests: `GripUITests.testASessionsGripIsReadAgainstTheCars`. Model: `GripTests`, `CarGripTests`,
`GripWordingTests`.

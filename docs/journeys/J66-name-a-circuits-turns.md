# J66 Name a circuit's turns
*Source: #550 — turn names could only be typed in a project's inspector, in a collapsed list of
Corner 1, Corner 2… with nothing to show which corner was which, while what reads them — Trends'
corner table, goals on a corner, plans, Coaching — is in the Logbook. #548 made a name stay on its
turn; #549 gave each configuration of a circuit its own names.*

1. In the Logbook, choose the circuit (or one of its configurations) under **Circuits**. On its
   card, **Name Turns…**.
2. The sheet draws the circuit from your best lap there, each corner numbered on the map, and lists
   the corners in driving order with a field each. The field being typed in lights its corner on
   the map.
3. Type what the circuit calls each turn — *3a*, *Carousel*. After a turn the circuit numbers its
   own way, **Number the Following Turns from Here** (also on the field's right-click menu) calls
   the ones after it 4, 5, 6…. Leave a kink blank: it is not one of the circuit's turns.
4. **Done** keeps the names for the circuit. The sessions there are read again with them, so Trends,
   goals, plans and Coaching call the turns by their names, and a project's map numbers them so.
5. **Edit ▸ Undo Name Turns** puts the names back as they were.

Tests: `TurnNamingUITests.testATurnNamedOnTheCardIsKeptForTheCircuitUntilUndone`. Model:
`CornerNamingTests`.

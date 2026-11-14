# J63 Prepare to go back to a circuit
*Source: #460 — before the next day a driver wants to say where they are going and be told what to
work on. A new day showed the circuit and the date and nothing of the visits before it; a plan made
in the Coaching window was shown again only there and under Season ▸ "Still planned", and choosing
the circuit in the sidebar only filtered the table.*

1. In the Logbook, choose the circuit under **Circuits** in the sidebar. A card above its sessions
   gives the visits, the personal best there and how the last visit went against it.
2. **Plan for Next Time** shows the plan made for the circuit, each line editable on the card;
   **Add Experiment** and the minus add and remove lines. With no plan, **Start a Plan** begins one
   from **Where the Last Visit Lost Time** (the corners slowest against the best lap, with how much
   and why), and **Make a Plan in Coaching…** opens Coaching on the last visit's best session;
   the plan saved there is on the card at once (#543). Every change, that one too, is a step of
   the Logbook's Edit ▸ Undo.
3. **New Track Day Here…** opens New Track Day with the circuit chosen. The new day shows the same
   card, plan and all, until its first session arrives.

Tests: `PrepareForACircuitUITests.testAPlanIsWrittenForTheCircuitAndGreetsTheNextDay`,
`PrepareForACircuitUITests.testAPlanMadeInCoachingIsOnTheCardAtOnce`. Model:
`CircuitBriefTests`.

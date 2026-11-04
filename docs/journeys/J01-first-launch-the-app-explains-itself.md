# J1 First launch: the logbook explains itself
*Source: guide §1; #395 — the workflow begins with a track day, so the first thing on screen is the
logbook, with the start-a-project controls inside it. Before v0.34.0 a welcome window offered a
blank project, a template, Open Project…, recents and the sample.*

1. Launch. The **Logbook** window opens; no project and no file panel appear until one is asked
   for. With nothing in it yet, it says so and offers **New Track Day…**, **Add Files…** and **New
   Project**. The toolbar's **New Project** menu offers a **Blank Project**, every template (the
   built-in ones and yours), **Open Project…**, **Templates…** and **Open the Sample Project**.
2. **New Project ▸ Blank Project**: an **Untitled** project opens beside the logbook, which stays
   open — it is where the work comes from — with the welcome panel (Add Video…, Open the Sample
   Project, User Guide) and the Getting Started checklist in the inspector. **New Project ▸ Glass
   Cockpit** opens a project with that layout.
3. The first time, the three-step tour appears; **Next**, **Next**, **Done** dismiss it and it
   does not return on the next launch. **Help ▸ Take the Tour** brings it back.
4. **Help ▸ Keyboard Shortcuts** opens the shortcuts window. **Settings ▸ Logbook** turns *Open the
   Logbook at launch* off to start on a blank project; **Window ▸ Logbook** (⌃⌘L) opens it any time.

Tests: `LogbookLaunchUITests` (the logbook at launch, a blank project, a project from a template),
`FirstLaunchUITests.testWelcomeAndGettingStarted`, `testTourStepsThroughAndCanBeRepeated`,
`testShortcutsWindowOpens`.

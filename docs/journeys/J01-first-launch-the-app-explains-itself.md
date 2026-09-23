# J1 First launch: the app explains itself
*Source: guide §1; RaceRender's New Project menu; DashWare's project wizard.*

1. Launch. The welcome window offers a blank project, a project from a template, Open Project…,
   recent projects and the sample project; no file panel and no project appear until one is
   chosen. A blank **Untitled** project shows the welcome panel (Add Video…, Open the Sample
   Project, User Guide) and the Getting Started checklist in the inspector.
2. The first time, the three-step tour appears; **Next**, **Next**, **Done** dismiss it and it
   does not return on the next launch. **Help ▸ Take the Tour** brings it back.
3. **Help ▸ Keyboard Shortcuts** opens the shortcuts window.

Tests: `LauncherUITests` (blank project, from a template, reopening the window),
`FirstLaunchUITests.testWelcomeAndGettingStarted`, `testTourStepsThroughAndCanBeRepeated`,
`testShortcutsWindowOpens`.

# J18 Use the editor without seeing its icons
*Source: #79, #153 — icon-only controls said nothing until clicked, VoiceOver read toolbar menus by
their symbol names, and the preview was one blank picture to assistive technology.*

1. Hover over any toolbar or transport button: a help tag names it and its shortcut.
2. With VoiceOver on, the toolbar reads *Add Object* and *Layout*, the sidebar's glyphs say *Video*,
   *Data*, *Problem: …*, and the checklist says *Done* / *To Do*.
3. On the preview, each object is its own element — *Speedometer*, *Selected* — which VoiceOver
   can press to select and whose actions move it (*Move Left*, *Move Right*, *Move Up*,
   *Move Down*, by the ⇧-arrow step).
4. Text passes the contrast audit in the light appearance as well as the dark.

Tests: `AccessibilityUITests` (`testEveryControlHasAName`, `testTextHasContrastInBothAppearances`,
`testTheObjectsOnThePreviewCanBeFoundAndSelected`). A spoken VoiceOver walk through J2 stays manual.

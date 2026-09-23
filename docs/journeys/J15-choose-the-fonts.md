# J15 Choose the fonts
*Source: #118 — only a text object could choose a font, and a readout's had to be typed by name.*

1. With nothing selected, choose **Font ▸ Futura** in the project inspector. The typeface starts at
   *Bold*, which is what overlays mostly draw in.
2. Add a **Lap Timer**. Its **Font** pop-up reads *Project Font (Futura Bold)*: it follows the
   project and says what that is. A **Text size** slider scales all of its text.
3. Choose **Helvetica Neue** for the timer alone: it keeps *Bold*. Choose *Light* as its typeface.
4. ⌘Z takes back the typeface, and ⌘Z again the font, each named in the Edit menu.

Tests: `FontUITests.testProjectFontThenAnObjectsOwnAndUndo`. Renderers: `TypefaceTests`. Model:
`TypefaceModelTests`.

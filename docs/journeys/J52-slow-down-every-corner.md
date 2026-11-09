# J52 Slow down every corner, with a sight picture
*Source: #360 — a corner clip at normal speed goes by too fast to learn from; instructors and
Garmin's Catalyst both teach braking from the frame at the better lap's brake point.*

1. With a lap chosen in **Project ▸ Coaching…** (or the session best as the reference), **Export** ▸
   *Range* ▸ **Every corner, one file each**.
2. **Slow the braking zone** is on: each clip plays from its brake point to its slowest point at
   *Speed* 50% (25% and 75% too). **Hold where the reference braked** is on: the whole frame stands
   still for *Hold* 1 second (½ to 3) when your lap reaches the spot where the reference lap braked.
   The picture and every gauge, graph and map slow and hold together; the sound is muted meanwhile.
3. The sheet's sentence says what the files will do (*… each from two seconds before the brake
   point to two seconds after the corner, with the braking zone at 50% and a 1-second hold where the
   reference braked.*) and follows the switches and the choices.
4. **Export…**, choose a folder: one file per corner, as before, each retimed.
5. From the command line: `onboard render --project X --corners all --slow-braking 0.5
   --hold-reference 1 --out <folder>`.

Tests: `CornerClipsUITests.testCornerClipsSlowTheBrakingZoneAndHoldASightPicture`. Model:
`CornerExportsTests.aRetimedCornerSlowsItsBrakingZoneAndHoldsWhereTheReferenceBraked`,
`CornerExportRangeTests`, `RetimeTests`.

# J53 Slow down and hold part of the video
*Source: #443 — a pass, a lock-up or a brake point wants watching slowly, or standing still for a
moment, and the video had one speed throughout; Final Cut (Retime, Hold) and Premiere (Time
Remapping) both do it, RaceRender only has a speed per input.*

1. Mark the stretch with **I** and **O**.
2. **Playback ▸ Change Speed of In to Out ▸ 50%** (25%, 75%, 150% and 200% too). The status line
   says *0:10.0 to 0:14.0 plays at 50%*, and a **Retime** lane appears under the ruler with a band
   labelled *50%* over the range. Undo reads *Undo Slow Down* (*Speed Up* above 100%).
3. Move the playhead to a moment and press **⇧H** (**Playback ▸ Hold Frame**): a mark labelled
   *Hold 1 s* appears there.
4. Play: the playhead crawls through the band and stops on the hold while the picture and every
   gauge, graph and map slow and stand still with it, the sound muted meanwhile. Nothing else on
   the timeline moves; the export plays the same and is longer by what the retimes add.
5. Right-click a band to change its speed (or a hold its length) or to remove it; **Normal Speed**
   over a range takes its speed changes away. Every change can be undone.
6. VoiceOver reads each as *Plays at 50% from 0:10.0 to 0:14.0* or *Holds for 1 second at 0:21.3*,
   with a Remove action.

Tests: `RetimeUITests.testSlowARangeAndHoldAFrame`. Model: `RetimeEditingTests`, `TimeMapTests`,
`RetimeTests`.

# J34 Export a coaching debrief
*Source: #327 — the product of a coaching session is a short video to re-watch before the next one:
what the session was, the corners to work on with the footage of each, and what to try. Blayze's
coaches send one; Garmin builds one. Here it was a day of manual editing.*

1. Open the project with the session's video and data. Optionally **Project ▸ Coaching…** to
   choose the lap to read and what it is compared with; otherwise the lap being compared, else the
   first lap, is read against the best lap.
2. **Project ▸ Apply Template ▸ Coaching Debrief** if you want the Corner Callout and the
   following track map on the clips; any layout works, including Compare Laps' two pictures.
3. **Project ▸ Export Coaching Debrief…**. The sheet lists what it will write: the title card, the
   corners that cost the most (biggest loss first, with the seconds lost), and the closing card,
   with the running time. **Corners** sets how many; **Read the notes aloud** adds the system
   voice over the cards and the clips (#335).
4. **Export…**, choose where. One progress bar covers the cards and the clips; the pieces are
   joined into one file named `<project> – Coaching Debrief.mp4`, in the project's codec and size.
5. When it finishes, **Reveal in Finder** or **Upload to YouTube…**. The project is left exactly
   as it was.
6. The same from the command line: `onboard render --project X --out debrief.mp4 --debrief`
   (`--debrief-corners 5` for more).

Tests: `DebriefUITests.testTheDebriefExportsAsOneVideo`. Model: `DebriefTests` (the plan, the
cards, the stitch, and a whole export on the fixture).

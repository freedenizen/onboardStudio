# J36 Hand over the debrief on paper
*Source: #331 — a debrief in the paddock wants a sheet of paper: the track map with the corners
numbered, the corner table and the three things to try. The app's only artefact was video.*

1. **Project ▸ Coaching…**, choose the lap and what it is compared with; make a plan if you want
   it on the page.
2. **File ▸ Export Coaching Sheet as PDF…** (there while the Coaching window is in front with a
   lap read): one US Letter page — the track and the day, the headline, the circuit with every
   corner numbered, the top opportunities with their evidence and what to try, every corner's
   numbers in a table, and *Next session, try…*. Black on white, for printing.
3. **File ▸ Export Coaching Sheet as Markdown…** writes the same as text, for a message or a
   notes app. The file is named for the track and the lap: `Sonoma – Lap 2 coaching sheet.pdf`.
4. From the command line, `onboard coach session.csv --lap 2 --markdown` prints the Markdown.

Tests: `CoachingSheetUITests.testTheSheetExportsAsPDFAndMarkdown`. Model: `CoachingSheetTests`.

# J23 Export every lap as its own file
*Source: #150 — people share laps, not sessions, and a 12-lap day was twelve exports by hand.*

1. **Export** ▸ *Range* ▸ **Every lap, one file each**. The sheet says which files it will write:
   *Writes 3 files: Lap 1, Lap 2, Lap 3.*
2. *Complete laps only* (on) leaves out the out-lap and in-lap; *Skip slow laps* leaves out laps
   slower than the best by more than a set percentage. The list updates as they change.
3. **Export…**, choose a folder: each lap is written as `<project> – Lap N.mp4`, under one progress
   bar. **Reveal in Finder** opens the folder.
4. The same from the command line: `onboard render --project X --laps each --out <folder>`.

Tests: `ExportLapsUITests.testEveryLapIsWrittenAsItsOwnFile`. Model: `LapExportsTests`.

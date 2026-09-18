# QA script — M11 scripted objects

| # | Step | Expected |
|---|---|---|
| 1 | **Add Object ▸ Script** | A speed readout panel appears (the default script); the inspector shows the code and "Script compiles." |
| 2 | Change `"mph"` to `"kph"` in the code and press **Apply** | The readout switches units immediately |
| 3 | Delete a closing brace and pause | The inspector shows "Line N: SyntaxError…"; after **Apply** the object shows a red "Script error" badge; the app keeps running |
| 4 | Restore the brace (or **Revert**), Apply | Badge disappears |
| 5 | **Examples ▸ Shift light**, Apply, scrub to a high-rpm moment | The light turns amber then flashes red |
| 6 | **Examples ▸ Lap delta (RaceRender style)**, Apply | Delta in green/red once a lap is complete; lap number and time in the corner |
| 7 | **Examples ▸ Speed trace**, Apply, play | A sparkline of the last 10 s scrolls |
| 8 | Write `function frame(c, d) { c.rect(0, 0, undefinedVariable, 1); }`, Apply | Runtime error badge with the line number; export still completes |
| 9 | Export a range containing the script | The exported frames match the preview |
| 10 | Copy the object style to another Script object | The code comes with it |

## Results (0.9.0, real Sonoma project)

- **Add Display Object ▸ Script** drew the default speed panel reading 80 mph, matching the speedometer, with the code in the inspector.
- Typing `function frame(c, d) { c.rect(0, 0, undefinedVariable, 1); }` and pressing **Apply** put a red "Script error (line 1) ReferenceError: Can't find variable: undefinedVariable" badge on the object; the preview, gauges and inspector kept working. (The inspector's own check is syntax-only, so it still says "Script compiles." for runtime errors; the badge carries those.)
- The busy-script benchmark averages 0.34 ms per frame on the test machine.

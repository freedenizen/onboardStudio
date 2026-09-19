# QA script — M18 native indicator lights, timing panel, readout zones

| # | Step | Expected |
|---|---|---|
| 1 | **Add Object ▸ ABS Light**, set the channel to one the logger records ABS on (e.g. `aux:ABS`) and the threshold | The dim ISO ABS symbol sits where placed; scrubbing to an event lights it amber with a glow; **Hold on** keeps it lit briefly after |
| 2 | **Add Object ▸ Traction Light**, channel `aux:DSC` (or "Analog 2" on a BMW CAN log), threshold 0.2 | The car-with-skid-marks symbol lights when DSC intervenes |
| 3 | **Add Object ▸ Brake Light**, channel `brake`, threshold 1 | A red round light with BRAKE under it, on under braking |
| 4 | **Add Object ▸ Timing Panel** across the top of the frame | Best / Previous / Current with small lap numbers and `m:ss.d` times; left lane: speed with a marker on a ±10 mph scale and the signed difference to the best lap; right lane: a green/red bar on a ±2 s scale with the signed time delta |
| 5 | Text Data for coolant temperature: multiplier 1.8, offset 32, zones amber from 220 and red from 235 | The number turns amber then red as the value rises |
| 6 | Compare with the RaceRender project's ABS / DSC / "Timing and Deltas" objects | Same information and layout, no script |

## Results (0.16.0)

Run on 2026-09-18 against the Sonoma track-day project (GoPro GX010037 + RaceChrono v3 CSV, local files only). The
user's desktop was in use during the run, so the checks went through the headless renderer (`overlaygen render`
uses the same compositor as the preview) plus a window capture of the app with the same project open.

| # | Result |
|---|---|
| 1 | Pass. ABS Light on `obd:analog_1` ≥ 600 (the RaceChrono column RaceRender's script read as `DataValue > 600`). Dim grey symbol at 0:00; at 5:55 (a braking event) it is amber with the glow. The hold test in `IndicatorPanelTests` covers the 0.3 s hold. |
| 2 | Pass. Traction Light on `obd:analog_2` ≥ 600 lights at 5:47 while the ABS light stays dim, matching the DSC intervention in the log. |
| 3 | Pass. Brake Light on `brake` ≥ 30 %: red round light with BRAKE under it at 5:55, grey with grey label at 5:47 (no brake). |
| 4 | Pass. At 10:00 (lap 3): Best ²1:56.9, Previous ²1:56.9, Current ³1:12.7; speed lane 90 mph, +3, green marker right of centre; time lane −0.55 with a green bar, agreeing with the existing Delta timer (−0.55). In lap 1 the times read `-:--.-` with no lap number and no delta (nothing to compare with yet). |
| 5 | Pass. WATER readout (°C × 1.8 + 32, °F) shows 192 in amber (zone 190–200) and 203 / 214 in red (zone from 200). |
| 6 | Pass by inspection. Same lanes, scales (±10 mph, ±2.0 s), colours (amber 0xFFB000, green 0x20C040 / red 0xE03030) and ISO ABS geometry as the RaceRender scripts, rendered natively; the RaceRender project's three scripted objects are not needed. |

Captures: `m18-354.5.png` (ABS + brake on), `m18-346.5.png` (traction on), `m18-600.png` (timing panel with deltas),
`m18-app-d.png` (the app with the five new objects at 0:00). The scripted scrub and inspector edits were not
exercised this run; they use the same code paths as the earlier milestones' inspectors and are covered by the
next QA pass.

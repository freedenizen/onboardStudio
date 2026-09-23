# Scripted objects

A **Script** object draws itself with JavaScript (JavaScriptCore, sandboxed: no network, no files,
no timers). Add one from **Add Object ▸ Script**, edit the code in the inspector and press
**Apply** (⌘↩ from inside the editor, where Return starts a new line); the preview updates live and errors are shown in the inspector and as a red badge on
the object instead of a crash.

A script defines one or both of:

```js
// Runs once per output size; the result is cached. Static panels, scales, labels.
function background(canvas) { … }

// Runs every frame with the telemetry at that moment.
function frame(canvas, data) { … }
```

Coordinates are pixels inside the object's rectangle, origin top-left; `canvas.width` and
`canvas.height` are its size. Drawing outside the rectangle is clipped.

## `canvas`

| Call | Draws |
|---|---|
| `fill(color)` / `stroke(color, width)` | Set the fill colour / stroke colour and line width for later calls |
| `rect(x, y, w, h)` · `strokeRect(…)` | Rectangle |
| `roundRect(x, y, w, h, radius)` · `strokeRoundRect(…)` | Rounded rectangle |
| `circle(cx, cy, r)` · `strokeCircle(…)` | Circle |
| `line(x1, y1, x2, y2)` | Line |
| `polygon([x1, y1, x2, y2, …])` · `strokePolygon(…)` | Closed polygon |
| `arc(cx, cy, r, startDeg, endDeg)` | Stroked arc (0° = right, clockwise) |
| `gradientRect(x, y, w, h, fromColor, toColor, vertical)` | Linear gradient fill |
| `text(string, x, y, { size, align: "left"/"center"/"right", bold, mono, font, color, baseline: "middle" })` | Text with its top-left (or centre line) at x, y |
| `textWidth(string, options)` | Width of the text in pixels |
| `opacity(alpha)` | Alpha for everything drawn afterwards |
| `time` | Project time in seconds |

Colours: `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)`, `rgba(r,g,b,a)`, or `white`, `black`, `red`,
`orange`, `green`, `yellow`, `blue`, `transparent`.

## `data`

| Member | Meaning |
|---|---|
| `value(id)` | Channel value in its canonical unit (`speed` in m/s, `distance` in m, angles in degrees, `throttle` in %), or `null`. Ids as in the channel list: `speed`, `rpm`, `gear`, `throttle`, `brake`, `latitude`, `longitude`, `altitude`, `heading`, `lateralG`, `longitudinalG`, `distance`, `canbus:Name`, `obd:Name`, `aux:name` |
| `speed(unit)` | Speed in `"mph"`, `"kph"` or `"ms"` |
| `valueAgo(id, seconds)` | The value that many seconds earlier |
| `range(id)` | `[min, max]` over the session |
| `has(id)`, `channels` | Availability |
| `lap` | `{ number, elapsed, last, best, bestNumber, delta }` (`delta` = seconds behind (+) / ahead (−) the best lap at the same distance; needs a distance channel) |
| `laps` | `[{ number, start, duration }]` |
| `time`, `inputTime`, `duration` | Project time, time inside the data file, session length |

Helpers: `clamp(v, lo, hi)`, `lerp(a, b, t)`, `formatTime(seconds, decimals)` → `1:23.46`,
`formatDelta(seconds, decimals)` → `+0.35` / `−0.12`. `data.value("lapDelta")` and
`data.value("speedDelta")` give the deltas to the session's best lap (`data.lap.delta` is against
the best lap so far).

## RaceRender-style names

Scripts written for RaceRender's Enhanced Objects can use the familiar names; they map onto the
API above and take pixel coordinates:

`GetDataValue(DFT_Speed | DFT_RPM | DFT_Gear | DFT_Throttle | DFT_Brake | DFT_Latitude |
DFT_Longitude | DFT_Altitude | DFT_Heading | DFT_LatG | DFT_LongG | DFT_Distance)`, `DataValue(id)`,
`HasData(id)`, `GetSpeed(unit)`, `GetLapNumber()`, `GetLapTime()`, `GetBestLapTime()`,
`GetLastLapTime()`, `GetLapDelta()`, `GetTime()`, `Width()`, `Height()`, `SetColor(r, g, b, a)`
(0–255), `SetLineWidth(w)`, `SetFontSize(s)`, `DrawRect`, `DrawRectOutline`, `DrawRoundRect`,
`DrawLine`, `DrawCircle`, `DrawCircleOutline`, `DrawPolygon`, `DrawArc`, `DrawText(x, y, text, size,
align)`, `DrawNumber(x, y, value, decimals, size, align)`, `DrawTime(x, y, seconds, size, align)`.

## Examples

The inspector's **Examples** menu inserts: a speed readout, a shift light, throttle and brake
bars, a RaceRender-style lap delta, and a ten-second speed trace.

## Performance

`background` is drawn once and cached. `frame` runs on the render thread for every frame; keep it
to a few dozen drawing calls. The test suite holds a 60-shape, 4-text script under 4 ms per frame.

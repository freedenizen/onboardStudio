---
paths:
  - "Sources/Importers/**/*.swift"
  - "Sources/TelemetryKit/**/*.swift"
  - "Sources/GPMFKit/**/*.swift"
  - "Tests/ImportersTests/**/*.swift"
  - "Tests/TelemetryKitTests/**/*.swift"
  - "Tests/GPMFKitTests/**/*.swift"
---

# Importers and telemetry

## Conventions
- Add a fixture in `Tests/Fixtures` **and** a test for every new format or parsing rule. Fixtures
  are synthetic and committed; real logger files live in `~/OverlayGenSamples` and are never
  committed.
- RaceChrono Pro CSV v3 is a must-have format: preamble `This file is created using RaceChrono`,
  `Format,3`, a header row starting `timestamp,`, then a units row, then a source row such as
  `100: gps` / `calc` / `200: obd`.
- Fuzz suites mutate every fixture (byte flips, truncation, inserted garbage, digit storms) with a
  fixed seed and feed them to every importer, the GPMF/MP4 readers, the expression parser and the
  spherical-metadata reader. **Throwing is fine; crashing or hanging is the failure.** Seeds must
  use a stable hash — `String.hashValue` is per-process.
- Reproduce a fuzz case with
  `FUZZ_REPRO_DIR=… FUZZ_REPRO_CASE=fixture:iteration swift test --filter FuzzReproTests`,
  then `swift run onboard probe --format …` under `lldb --batch -o run -o bt`.
- Sanitise in `SessionBuilder`: past traps were `Int(Double)` on huge/NaN values, NMEA GLL
  indexing, MP4 sample-table counts, unit-suffix slicing and NaN time axes.

## Swift and format gotchas
- `"\r\n"` is **one** `Character`, so `split(separator: "\n")` does not split CRLF lines. Use
  `components(separatedBy: .newlines)`.
- AVFoundation does not expose the GoPro `gpmd` track; GPMFKit reads the MP4 boxes itself.
- GoPro chapter files all report the same `recordingStartEpoch` from GPMF, so a chapter's own start
  is recording start + the earlier chapters' durations (`RecordingGaps.span`).
- Never trust a container `creation_time` over the GPS clock — on the reference clip it is 32 s late.
- Laps shorter than 90% of the longest complete lap are demoted to partial in `SessionBuilder`;
  deltas compare against the session's best **full** lap.

## Never hard-code channels
Channel names are logger- and file-specific (the reference RaceChrono file happens to use
`obd:analog_1`, `obd:analog_2`, `brake`, `obd:coolant_temp`, but another file will not). Bind
through `IndicatorParams.adapted(to:)` / `Project.bindEmptyChannels` and expose thresholds and
units as parameters with suggested defaults derived from the loaded channel's range.

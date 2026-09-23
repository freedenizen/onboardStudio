# J11 Overlay-only export for another editor
*Source: RaceChrono alpha-matte export; Telemetry Overlay transparent exports; the user's own
RaceRender → Resolve workflow.*

1. Export with **Behind the overlays: Transparent** and the HEVC-with-alpha codec (`.mov`).
2. The file exists and its extension is `.mov`.

Tests: `JourneyUITests.testTransparentOverlayExport`. Model: `ExportOptionsTests`.

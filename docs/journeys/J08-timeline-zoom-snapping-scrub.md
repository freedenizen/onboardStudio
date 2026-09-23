# J8 Timeline: zoom, snapping, scrub
*Source: DaVinci Resolve timeline conventions adopted in M16; guide §2.*

1. Zoom in with the transport button and ⌘=; zoom to fit returns to 1×.
2. Toggle snapping with the magnet and with N.
3. Step forward changes the transport time; Go to start returns to 0:00.00.

Tests: `TimelineUITests.testZoomSnapAndTransport`. Model: `ClipModelTests` (snapping),
`VideoTrimmingTests`.

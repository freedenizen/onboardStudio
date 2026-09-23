# J6 Warning lights that fit any logger
*Source: RaceRender "Enhanced Display" lights; this app's indicator design.*

1. **Add Object ▸ ABS Light** on a log with no ABS channel: the inspector warns "This object needs
   a channel".
2. Pick a channel; the inspector shows the channel's range in this file and **Suggest** sets the
   threshold to its midpoint.

Tests: `ObjectEditingUITests.testIndicatorLightAsksForAChannelAndSuggestsAThreshold`. Model:
`IndicatorParamsTests`.

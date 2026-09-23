# J3 Start from a template, then add the media
*Source: RaceRender templates; Telemetry Overlay activity presets; regression for the 0.16.2 bug.*

1. **File ▸ New from Template ▸ Classic Dash** opens a new document already listing the gauges.
2. Add the video, then the data. The gauges bind to them (the speedometer's inspector names the
   data input's channel) instead of staying orphaned.
3. Adding the same video file again is refused (status line "…is already part of…"); a different
   recording opens its own lane after the first rather than stacking on top of it.

Tests: `TemplateUITests.testNewFromTemplateThenMedia`, `testAddingTheSameFileTwiceIsRefused`.
Model: `InputPlanningTests`, `TemplateExportTests`.

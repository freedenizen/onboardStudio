---
name: qa-milestone
description: Write and run the QA script for an Onboard Studio milestone, then record the results in docs/qa-m<N>.md
disable-model-invocation: true
---

Produce or complete the QA pass for milestone `$ARGUMENTS` (a milestone number such as `19`, or a
feature name). The deliverable is `docs/qa-m<N>.md` in the established house format.

## Format

Match the existing files exactly — read the most recent `docs/qa-m*.md` first for tone and shape.

1. `# QA script — M<N> <short title>`
2. A numbered step table: `| # | Step | Expected |`. Steps are written as a **user** would perform
   them ("**Add Object ▸ ABS Light**, set the channel to one the logger records ABS on"), never as
   code. "Expected" describes what the user should see, with concrete values and colours.
3. A `## Results (<version>)` section: the date, what data it ran against, then a
   `| # | Result |` table with Pass/Fail and the *observed* numbers, times and file names.
4. A closing paragraph naming the captures produced and anything **not** exercised this run.

## How to run the checks

Prefer the headless path — it uses the same compositor as the preview and does not need the
user's desktop:

```sh
swift run onboard probe <session> --at <t>          # values at a time
swift run onboard render --project X --range a:b --preset 1080p --fps 10
ffmpeg -ss 0.5 -frames:v 1 …                           # pull a frame to look at
swift run onboard render --template "<built-in>"    # eyeball a template
```

- Real data lives in `~/OverlayGenSamples` and the user's iCloud track-day folders
  (`ONBOARD_SAMPLES_DIR`). **Local only — never upload, commit or attach these files.**
  The Sonoma reference session's best lap is 1:56.88 with finish line
  `38.16155,-122.45467,308,30`.
- The scratch QA project is `scratchpad/real.overlayproj` (session-local).
- Where a step cannot be checked headlessly, cover it with a unit test and say so in the Results
  table rather than claiming a pass.

## If the user's desktop is in use

Do **not** steal focus or click. Capture the app window with
`screencapture -l <windowID>` (window ids from a `CGWindowListCopyWindowInfo` snippet) — it works
even when the window is covered. Only fall back to scripted interaction when the user says the
machine is free:

- `cliclick` + `screencapture -R`; type into SwiftUI form fields with click → ⌘A → type → Tab.
- Click a DisclosureGroup's chevron, not its label.
- Out-of-process open/save panels ignore synthetic Return/Escape — never script a flow that needs
  one to close. Click the Save button on an NSAlert rather than pressing Return.
- AppleScript can drive menus:
  `click menu item "X" of menu "Sub" of menu item "Sub" of menu "Project" of menu bar 1`.
- DragGesture bars only react when the window is frontmost (AXRaise first) and with `-w 60` waits.

## Finish

Report Pass/Fail per step with the evidence inline, list any follow-up bugs found, and do not mark
the milestone verified if any step is unproven.

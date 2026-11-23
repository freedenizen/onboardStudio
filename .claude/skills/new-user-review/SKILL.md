---
name: new-user-review
description: Use a published Onboard Studio release as a first-time user would — the download, the user documentation and real track days — and record every friction point for the app and the guide in docs/reviews/v<version>.md
disable-model-invocation: true
---

Run the new-user review of release `$ARGUMENTS` (a version such as `0.37.0`). The process, its
rules, the task table and the shape of the report are in `docs/new-user-review.md`; the checklist a
finding cites is `docs/ux-checklist.md`. Read both in full first. This file is only how to carry
them out here.

## Before starting

- **The release must be published**: `gh release view v$ARGUMENTS --json assets`. If it is not,
  say so and stop — the review is of what a user received, never of a build of `main`.
- **Start in a fresh session.** A session that has just worked on the code knows where things are,
  and a new user does not.
- It needs **computer use** and takes the screen for a few hours. Tell the user before starting;
  the display must stay awake.
- The data is a folder of track days, by default `~/Onboard Studio Testing Set`; ask if it is not
  there. It is **local only**: nothing from it is committed, uploaded or attached, and no value
  read from it (a lap time, a speed, a position) is written anywhere outside the review folder.
- Find the review's issue (`gh issue list --label new-user-review`), or open it
  (`New-user review of v$ARGUMENTS`, labels `documentation` and `new-user-review`).
- Read the newest report in `docs/reviews/`: its scorecard is the comparison, and its findings are
  re-tested at the end.

## What may be read during the walk

`README.md`, the release notes (`gh release view`), `docs/user-guide.md` and the pages it links
to, and the app itself. **Not** `Sources/`, `Tests/`, `UITests/`, `docs/architecture.md`,
`docs/journeys/`, `.claude/rules/`, or any memory of how the app is built. If you catch yourself
taking a step because you know the code, stop: record the finding, mark the task failed at that
step, and only then carry on.

## Setting up

```sh
gh release download v$ARGUMENTS --pattern 'OnboardStudio-*.dmg' --dir "$(mktemp -d)"
Scripts/review-copy.sh make  $ARGUMENTS <the dmg>
Scripts/review-copy.sh stage $ARGUMENTS ~/"Onboard Studio Testing Set"/*/
Scripts/review-copy.sh launch $ARGUMENTS
```

`make` prints what Gatekeeper said about the download: that is the first evidence for task T0.
Keep `notes.md` and `shots/` in the review folder (`Scripts/review-copy.sh info $ARGUMENTS`).
Write the release's own tasks from the release notes before the first launch, in the same form as
the core tasks — a goal, no button names.

## Driving the app

- Ask for access to the review copy and to Finder. Two apps may be called Onboard Studio: the one
  to drive is `com.freedenizen.onboardstudio.review`. Never act on the real one.
- Files go in the way a user's would: dragged from a Finder window showing the staged folder
  (`…/v$ARGUMENTS/Track Days`), or through the app's own panels. Take a screenshot immediately
  before every drag between apps. Never click in a Finder sidebar — a missed click there has
  navigated to the real home folder and dropped a real folder on the app.
- A save or export panel opens on the real Documents: press ⇧⌘G and send it into the review
  folder, every time.
- Never **Upload to YouTube**, never send or attach what **Export Diagnostics…** writes.
- A size in a finding comes from `Scripts/review-copy.sh info` or the accessibility frame, in
  points. Do not convert screenshot pixels.
- After each step write the note at once: did, expected, happened, the screenshot names. Count the
  steps as you go.

## After the walk

Follow "After the walk" in the process, in its order. Notes for doing it here:

- Re-check each finding from a fresh launch (`clean`, `make`, `launch`) before writing it up, and
  say in the report which ones changed.
- The independent reading is `swift run onboard probe <staged file>`. Compare, and write only
  whether the app agreed.
- Checking the guide's bold labels and pictures against the screens visited is mechanical: give it
  to a Sonnet subagent with the chapters and the screenshots. Lookups and status checks go to
  Haiku. The walk itself and the severity ratings stay in the main thread.
- Before any commit, search the diff for values seen in the data and for file names from the set.
- Write `docs/reviews/v$ARGUMENTS.md` and add it to `docs/reviews/README.md`. Show the report to
  the user and file the issues they agree to; then the PR (`docs: new-user review of
  v$ARGUMENTS`, `Closes #<the review's issue>.`), as a draft if another PR is in CI.
- `Scripts/review-copy.sh clean $ARGUMENTS`. The notes and screenshots stay on this Mac.

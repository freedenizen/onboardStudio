# Onboard Studio

Native macOS app (Swift 6 / SwiftUI / AVFoundation) that combines onboard video with telemetry
into finished videos with data-driven overlays — a reimplementation of the RaceRender 3 workflow.
Libraries, tests and the `onboard` CLI build with SwiftPM; the app bundle builds from an
XcodeGen-generated project.

## Commands

```sh
Scripts/setup-dev.sh                                # once per clone: git hooks + allowed signers
swift build
Scripts/test.sh quick                               # everything but the two-hour session and fuzz suites
swift test --filter ImportersTests                  # PREFER one target over the full suite
swift test                                          # everything, as CI runs it (Scripts/test.sh full)
UPDATE_GOLDENS=1 swift test --filter RenderKitTests # regenerate golden images
swift run onboard probe <file>                   # what channels/laps were read
swift run onboard render --project X --out out.mp4 --range a:b --preset 1080p --fps 10
swift run onboard bench --export --codec hevc --seconds 60
```

- Unit tests use **swift-testing** (`import Testing`, `@Suite`, `#expect`), not XCTest; only the
  UITests target is XCTest. Every `swift test` run therefore also prints an XCTest line reading
  `Executed 0 tests, with 0 failures` — that is always present and never the real result. The real
  result is `Test run with N tests in M suites passed/failed`.
- `xcodegen generate` **after adding or removing any source file**, before `xcodebuild` or
  `Scripts/bundle-app.sh` — the `.xcodeproj` is generated and gitignored, and skipping this
  fails with bogus "no member" errors.
- `Scripts/bundle-app.sh` → `dist/OnboardStudio.app`; `Scripts/make-dmg.sh` → the DMG.
- `Scripts/ui-tests.sh [Class[/test]]` — XCUITest journeys. See `.claude/rules/uitests.md`.
- Media tests use `ffprobe` and skip when it isn't installed.
- Set `ONBOARD_SAMPLES_DIR=~/OverlayGenSamples` to run the real-clip tests.

## Repo etiquette

- **Every piece of work starts as a GitHub issue, and its PR closes that issue.** Before opening a
  PR, check for an existing issue (`gh issue list`); if there is none, write one first with
  `gh issue create` — do not wait to be asked. The issue states the problem and the evidence for
  it, not the fix. Label it to match the Conventional Commits type the PR will use: `bug` (`fix:`),
  `enhancement` (`feat:`), `documentation` (`docs:`), `ci`, `chore`, `refactor`. The PR body then
  begins `Closes #N.` so merging closes the issue. This applies to fixes found in passing, not just
  planned features.
- Branch + PR into `main`. `main` is protected by one ruleset: required checks are Lint,
  Lint (fast), Test, UI tests, Verify commit signatures, Analyze (actions); linear history,
  signed commits, review threads resolved, no force pushes. **Not strict**: a PR need not be up
  to date with `main` to merge, so a merge never puts another PR `BEHIND`. The push run on
  `main` is what proves `main`; when it is red the `main health` job opens the issue labelled
  `main-red` — fix forward at once. CodeQL's Swift analysis still runs on every PR but does not
  block it. Never push to `main` directly and never force-push it.
  **Force-pushing a feature branch is fine and is how you rebase one.** Rebase locally and
  `git push --force-with-lease`; never `gh pr update-branch --rebase`, which re-creates the
  commits on GitHub's side **unsigned** and fails the required `Verify commit signatures` check.
  `UI tests` is reported by an aggregating job that fans out to `UI tests (build)` and three
  `UI tests (shard N)` jobs; only the aggregate name is required, so the shards can be rebalanced
  freely. A new XCUITest class names its shard in a `// ci-shard: N` line above its
  declaration — `Scripts/check-ui-test-shards.sh` (run by Lint (fast) and the pre-commit hook)
  fails the build if one is missing; `ci.yml` is not edited for it. A shard retries a failed
  test once; a test that passes only on retry is recorded on the `flaky-tests` issue, so look
  there before calling a test stable.
- **One PR in CI at a time; the rest are drafts.** CI runs one PR at a time (a run is six macOS
  jobs), and a draft skips the macOS jobs and the Claude review — its **UI tests** check is red
  on purpose, so a draft never reads green (#239). Open further PRs with
  `gh pr create --draft`, and `gh pr ready <n>` the next one only when the one before has merged —
  rebase it first, so it is tested once against the `main` it will land on (#237). Related issues
  can share one PR (`Closes #79.` and `Closes #153.`).
- The nightly workflow (`.github/workflows/nightly.yml`) runs what a PR does not wait for:
  the ffprobe-backed media tests, `onboard render` on the fixture, an unsigned bundle and the
  bench against a budget; red opens the `nightly-red` issue.
- Every commit is SSH-signed (key lives in the 1Password agent; `SSH_AUTH_SOCK` must point at it).
- Conventional Commits subjects: `feat(importers): …`, `fix(mediakit): …`, `test(ui): …`, `ci: …`.
- **Every user-visible change is documented in the same PR that makes it.** A feature nobody can
  find is not finished. `docs/user-guide.md` for what it does and where it is; a journey in
  `docs/journeys/` (one file per journey, `J23-short-title.md`, naming the XCUITest that drives
  it) when it is a new thing a user *does*; `docs/formats.md` for anything about a file format;
  `docs/project-format.md` for a new field in the document; `docs/parity.md` when it changes what
  we do or do not have against RaceRender. Say what changed for the user, not what changed in
  the code.
- Every behaviour change ships unit tests. Parsers and renderers test against `Tests/Fixtures`;
  renderers additionally use golden images.
- `swift format` (`.swift-format`) and SwiftLint (`.swiftlint.yml`) are enforced by the pre-commit
  hook. Run them rather than fighting the hook. `swift format` rewraps lines, so read the exact
  text before patching it.
- Merge with `gh pr merge <pr> --auto --squash --delete-branch`. GitHub merges it server-side once
  the required checks pass, so it does not matter whether this laptop is awake. Do not start a
  local polling watcher for a merge. Every check that matters is a *required* check, so auto-merge
  is as strict as the old merge-when-green script. Never pipe `gh pr checks --watch` through
  `tail` — it has masked a red job and merged a broken PR.
- Changing a model type's layout (a new `ChannelRole` case, a new field on a params struct) leaves
  stale objects in `.build` when you switch branches. Symptom: a phantom SIGSEGV, or unrelated
  failures like `session[.speed] → nil` that reproduce *with your changes stashed*. Fix with
  `swift package clean`. This has cost two debugging cycles; suspect it first.

## IMPORTANT — project rules

- **It should feel like a native, premium utility Apple shipped.** Follow the Apple Human
  Interface Guidelines. Standard controls and system metrics before anything hand-rolled, semantic
  colours so dark mode and Increase Contrast work without a second code path, everything undoable
  with a name that reads in the Edit menu, full keyboard access and VoiceOver labels, and empty
  states that explain rather than blank panes. A control that works but does not belong on a Mac
  is not finished. Details and the mistakes this app has already made are in
  `.claude/rules/appui.md`, which loads whenever `Sources/OnboardStudioApp` is touched.

- **Never hard-code the user's logger channels, thresholds or units.** Templates bind to whatever
  data is loaded (`IndicatorParams.adapted(to:)`, `Project.bindEmptyChannels`,
  `Project.bindOrphanObjects`); everything else is a parameter with a sensible default. This is
  the core flexibility requirement of the app.
- **Opening a saved project never changes how it renders.** New defaults, new inheritance and new
  automatic behaviour apply to projects created after the change; a project saved by an earlier
  build keeps the values it had. Pin the old behaviour explicitly in `Project.migrateIfNeeded()`
  while stepping `currentSchemaVersion` — never by leaning on a decode default, which cannot tell
  an old file from a new one. See `docs/project-format.md`.
- **Ask before creating or pushing any git tag.** A tag cuts a signed, notarized public release.
  Push tags one at a time — GitHub starts no workflows when more than three arrive in one push.
- `~/OverlayGenSamples` and the user's iCloud track-day folders are **local testing only**:
  never commit, upload or attach them.
- Secrets are referenced by name only (`MACOS_CERT_P12`, `NOTARY_KEY_P8`, `SPARKLE_PRIVATE_KEY`, …).
  `sparkle_private_key*` is gitignored and must never be committed.
- RaceChrono Pro CSV v3 is a first-class importer and must keep working.
- After an Xcode build, `git checkout -- Package.resolved` and revert autosaved fixture projects.

## Layout

`Sources/` — `Importers`, `TelemetryKit`, `RenderKit`, `MediaKit`, `ProjectModel`, `GPMFKit`,
`Scripting`, `YouTubeKit`, `OnboardStudioApp`, `OnboardStudioCLI`. Tests mirror these names.

Deeper docs, read on demand: `docs/architecture.md`, `docs/formats.md`, `docs/project-format.md`,
`docs/conventions.md` (editor conventions to follow; which shortcut claims are verified),
`docs/landscape.md` (what other track-day tools do, where we are ahead, ranked candidate work),
`docs/tracks-and-sectors.md` (circuit identification, sectors, what each logger format carries),
`docs/testing.md`, `docs/parity.md`, `docs/scripting.md`, `docs/user-journeys.md` and
`docs/journeys/`, `docs/user-guide.md`, `docs/youtube.md`.

Path-scoped rules load automatically when you work in those areas:
`.claude/rules/renderkit.md`, `.claude/rules/importers.md`, `.claude/rules/uitests.md`,
`.claude/rules/appui.md`.

## Compact instructions

When compacting, preserve the full list of modified files, the exact build/test commands used,
and the names of any failing tests.

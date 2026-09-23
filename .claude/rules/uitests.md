---
paths:
  - "UITests/**/*.swift"
  - "Sources/OnboardStudioApp/**/*.swift"
  - "project.yml"
---

# App UI and XCUITest

Run with `Scripts/ui-tests.sh [Class[/test]]` (it wraps `xcodebuild` in `caffeinate -dis`).
One test class per journey in `docs/journeys/` (one file each). A new class names its CI shard in
a `// ci-shard: N` line above its declaration (above its doc comment). CI job **UI tests** uploads the `.xcresult`
on failure — read it with `xcrun xcresulttool export attachments`.
Local run ≈ 5 min for 13 tests.

## Target configuration
- The test bundle needs `ENABLE_HARDENED_RUNTIME: NO` (the base setting is YES, which fails with a
  "different Team IDs" dlopen error).
- The test bundle must **not** use `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (XCTestCase inits).
  Annotate test methods `@MainActor` instead, and hold the app under test in an optional property,
  not an implicitly-unwrapped one (SwiftLint).
- Scheme environment variables reach the **test runner only**. Anything the app needs goes through
  `app.launchEnvironment`. The fixtures path is derived from `#filePath` → `Tests/Fixtures`.
- Launch arguments: `-ApplePersistenceIgnoreState YES`
  `-NSShowAppCentricOpenPanelInsteadOfUntitledFile NO -tourSeen YES -uiTesting YES`
  `-skipLauncher YES -SUEnableAutomaticChecks NO -SUHasLaunchedBefore YES`.
  Launch-argument booleans arrive as **strings** — read them with `bool(forKey:)`, never `as? Bool`.
- `-uiTesting YES` adds the **Testing** menu (`UITestSupport.swift`) that installs fixture files,
  because open panels cannot be scripted; `ONBOARD_TEST_EXPORT_DIR` makes the export sheet skip
  the save panel. The fixture project is copied to a per-launch temp folder so ⌘S never touches
  the checkout.
- Base class `OnboardStudioUITestCase` provides `launch()`, `menu(_:_:)`, `menu(_:_:_:)`,
  `toolbarMenu`, `choose(_:inPopUpShowing:)`, `reveal`, `expectStatus`,
  `sidebarInput`/`sidebarObject`. Use these rather than raw queries.

## Query pitfalls
- Menu-bar items are always in the AX tree, so `app.menuItems["Speedometer"]` is ambiguous with
  toolbar and pop-up menus. **Scope every query**: `menuBarItems[m].menus.menuItems[i]`,
  `menuButton.menus.menuItems`, `popUp.menus.menuItems`; a sheet's pop-ups fall back to
  `app.menuItems`.
- Elements below a sheet's or inspector's scroll area get clicked at their off-screen frame and
  nothing happens — `reveal` them first.
- `.accessibilityIdentifier` on an HStack row leaks onto every child. Put it on the `Text`
  (objects) or use `.accessibilityElement(children: .combine)` (inputs).
- Identifier conventions: `toolbar.*`, `transport.*`, `object.<label>`, `input.<label>`, `tour.*`,
  `export.*`, `sync.*`, `status.message`, `preview.object.<label>`. Text controls are found by title.
- **An identifier is for tests; a label is for people.** Every icon-only control and status glyph
  gets `.accessibilityLabel` (title case, what it does: "Move Up", "Remove Tyres") *and* `.help`
  (sentence case, with the shortcut: "Export the finished video (⌘E)"); decorative images get
  `.accessibilityHidden(true)`. `AccessibilityUITests` runs Apple's audit for element descriptions
  and for contrast in the light appearance and fails on either — XCUITest cannot read help tags,
  so those are checked in review.
- `XCUIElement` cannot read a help tag, and the Touch Bar duplicates a dialog's buttons: scope a
  dialog button to `app.windows.buttons[…]`. Context menus share titles with menu-bar items
  (File ▸ Rename…); click the one that `isHittable`.
- `NSLog` truncates `app.debugDescription` — attach it with `XCTAttachment`.

## Runner and environment
- GitHub macOS runners have a 1024×768 screen (usable height ≈ 674 with the Dock). SwiftUI
  `.inspector` adds 2× its ideal width to the window minimum, so the editor uses an `HSplitView`
  with the inspector at `minWidth: 280, idealWidth: 300, maxWidth: 460` and the editor pane at
  `minWidth: 700` + `layoutPriority(1)` (window minimum ≈ 980). Measure minimums with AppleScript
  `set size of window 1 to {500, 500}` then read `size`.
- `UITestSupport.editorAppeared` activates the app, fits windows to the screen and remembers the
  last editor as a `FocusedValue` fallback (Sparkle's first-launch panel used to steal key window).
- **"Timed out while enabling automation mode" / "Failed to activate application" means the
  display is asleep** (displaysleep is 120 s; check `ioreg -c IOHIDSystem` `HIDIdleTime`). After a
  wake, 1Password's SSH agent also refuses signing until unlocked.

## SwiftUI notes
- `CommandMenu("View")` creates a duplicate View menu — use `CommandGroup(after: .toolbar)`.
- Help-menu actions needing the front window must live in the `Commands` struct that holds
  `@FocusedValue(\.editor)`.
- A SwiftUI `.overlay` does not dim an `NSViewRepresentable` (AVPlayerView).
- `PendingTemplate` must be set **before** `NSDocumentController.newDocument`.
- `swiftlint`'s `orphaned_doc_comment` fires when a `// swiftlint:disable:next` sits between a
  `///` doc comment and its declaration — put a plain `//` comment above the disable.

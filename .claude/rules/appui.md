---
paths:
  - "Sources/OnboardStudioApp/**/*.swift"
  - "project.yml"
---

# App UI: a native, premium Mac utility

**Onboard Studio should feel like a utility Apple shipped.** Follow the
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).
That is the standard for every UI change, not a polish pass at the end — a control that works but
does not belong on a Mac is not finished.

The rest of this file is what that means here, and the places this app has got it wrong before.

## Use the platform, don't reinvent it

- **Standard controls first.** `Form`, `Section`, `LabeledContent`, `Picker`, `Toggle`, `Stepper`,
  `TextField`. A hand-rolled control has to earn its place against the one the user already knows.
- **System metrics.** No hard-coded font sizes, paddings or row heights where a semantic one
  exists: `.font(.body)`, `.font(.caption)`, default spacing, `.formStyle(.grouped)`. Fixed
  numbers are for layout the content genuinely fixes, such as the column widths of a table.
- **Semantic colour.** `.primary`, `.secondary`, `.tint`, `Color.accentColor`, the standard
  materials. Never a literal grey for "dim text". Dark mode and Increase Contrast must both work
  without a second code path.
- **SF Symbols** for iconography, with a weight and scale that match the text beside them.

## Structure

- **Sheet, window or popover** is a real decision. A sheet for a modal task belonging to one
  document; a window for something the user leaves open beside their work (the attribute table);
  a popover for a short, dismissible aside. Do not use a sheet because it was easier to reach.
- **Windows are restorable and sized sensibly**: `defaultSize`, a `minWidth`/`minHeight` the
  content actually needs, and state that survives a relaunch. Remember that CI runs on a
  1024×768 screen (`.claude/rules/uitests.md`) — a window that cannot fit there cannot be tested.
- **The inspector is a column, not a page.** Anything needing three columns or a long scroll
  belongs somewhere else; #192 was exactly this mistake.
- **Menus mirror the app's verbs.** Every action reachable by mouse has a menu item where a user
  would look for it, with the standard shortcut when one exists.

## Behaviour

- **Everything is undoable**, through the document's undo manager, with a name that reads in the
  Edit menu: "Change Attribute Mapping", not "Edit".
- **Never block the main thread.** Long work is async with determinate progress where the length
  is knowable, and the window stays usable.
- **Destructive and irreversible actions confirm**; everything else just happens and can be undone.
- **Commit text fields on submit or on losing focus**, not per keystroke, or one typed word becomes
  twenty undo steps.

## Saying what is going on

- **Empty states explain and offer a way forward** — `ContentUnavailableView` with a real
  description, never a blank pane.
- **A control that defers says what it defers to.** "Automatic" alone is a word; `Automatic (kPa)`
  is an answer. This app has got this wrong twice (#187, #196), both times by showing the setting
  instead of the value in force.
- **Errors are in the user's language**, say what to do next, and never show a raw `Error`
  description or a file path the user did not choose.
- **Help tags** on anything whose label cannot carry the whole meaning.

## Accessibility is not optional

- Every control has a label that makes sense read aloud, and an accessibility identifier for the
  UI tests. Decorative images are hidden from VoiceOver.
- Full keyboard access: tab order follows reading order, focus is visible, Escape and Return do
  what they should in a sheet.
- Honour Reduce Motion, Reduce Transparency and Increase Contrast.
- Text scales; nothing clips at the largest accessibility sizes that a Mac offers.

## Polish that makes it feel bought rather than built

- Alignment across a form: labels on one axis, controls on another. `Grid` or `LabeledContent`
  rather than eyeballed padding.
- Consistent terminology with the user guide. An *attribute* is an attribute everywhere — in the
  UI, the menus, the docs and the release notes.
- Title case for buttons, as macOS uses it, in Apple's title style: short articles, conjunctions
  and prepositions stay lowercase (**Go to Segment**, **Open the User Guide**). Menu items, window
  titles, toolbar labels and undo action names are title case too, so a command reads the same as
  a button and in the menu bar. Checkbox and toggle labels, descriptions and help tags stay
  sentence case, as they do in Apple's own apps.
- No jargon from the codebase in the interface: the user has never heard of a `ChannelRole`.

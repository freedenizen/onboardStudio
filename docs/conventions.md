# Editor conventions

Anyone who has edited video already knows how a timeline behaves. Matching those conventions is
free; inventing our own costs the user a translation step every time they reach for something.

DaVinci Resolve is the primary reference, Premiere Pro and Final Cut Pro secondary. Where the three
disagree, that is said explicitly rather than papered over.

This file is about how an *editor* behaves. How the app should look and feel as a Mac application —
the Human Interface Guidelines, and what following them means here — is `.claude/rules/appui.md`.
Where an editor convention and the HIG disagree, the HIG wins for chrome and controls, and the
editor convention wins for the timeline and the verbs that act on it.

## Vocabulary

These five terms are standardised across Resolve, Premiere, Final Cut and the editing literature
generally. Use them exactly, in code, in menus and in docs — a "trim" that ripples when the user
expected a roll is a bug report waiting to happen.

| Term | Meaning |
| --- | --- |
| **Ripple** | Move one clip's edit point, changing that clip's duration, and shift everything after it by the same amount. Sequence duration changes. |
| **Roll** | Move the edit point *shared* by two adjacent clips: the outgoing clip's out point and the incoming clip's in point move together. Sequence duration is unchanged; only where the cut falls moves. |
| **Slip** | Change which part of the source media is shown, without moving the clip or changing its duration. In and out shift together within the source. Neighbours untouched. |
| **Slide** | Move a clip along the timeline without changing its own in/out or duration; the clips either side are trimmed to absorb it. Sequence duration unchanged. |
| **Ripple delete** | Remove a clip or range **and close the gap**, pulling everything after it earlier. Shortens the sequence. |
| **Lift** | Remove a clip or range and **leave a gap** of the same length. Nothing else moves. |

Premiere calls a ripple delete of a marked range **Extract**, and uses **Lift** for the
gap-leaving version exactly as above. Resolve and Final Cut just say "ripple delete". Prefer
"ripple delete" and "lift".

## Cutting: the two-tier model

All three editors converge on the same two-tier shape, and it is worth copying:

1. A **blade/razor tool**, bound to a single letter, that turns the pointer into a cutter. Each
   click cuts one clip on one track. Resolve and Final Cut use `B`; Premiere uses `C`.
2. A separate **command** that splits at the playhead without needing the tool selected, plus a
   modifier variant that cuts **every** track at once. Resolve's Split Clip is `⌘\`; Final Cut uses
   `⌘B` for the selection and `⇧⌘B` to cut all clips at the playhead.

In every case the two halves become independent clips that still reference the original media —
the cut changes in/out points, it does not touch the file, and no gap appears between the halves.

Resolve pairs this with **Join** (`⌥\`), which welds two adjacent segments of the same source back
together. Worth having: an undo covers the immediate mistake, but not one noticed later.

## Markers

The converged model across Resolve and Premiere:

- A marker has a **colour**, a **name**, and a **note**. It may optionally have a **duration**,
  drawn as a bar rather than a flag (a "range marker").
- `M` adds one at the playhead. Pressing `M` again — or `⌘M` — opens it for naming, pausing
  playback so you can type. Final Cut uses a dedicated `⌥M` for the same thing.
- There is a **marker list panel** (Resolve's Edit Index, Premiere's Markers panel, Final Cut's
  Timeline Index). Universal, and worth having: markers you cannot enumerate are markers you lose.
- Resolve distinguishes **timeline markers** from **clip markers**: a clip marker travels with the
  clip when it moves, a timeline marker stays at its timecode. Which one `M` creates depends on
  what is selected.

**Do not copy** Final Cut's marker *types* (standard / chapter / to-do / completed). They are
Final Cut-specific, and a Resolve or Premiere user will not expect them.

For Onboard Studio this maps cleanly: lap boundaries, incidents and sectors are all colour + name +
optional range, and a marker scoped to a data input is the clip-marker case.

**Implemented** (#54, first slice). `Marker` carries colour, name, note and an optional duration;
Final Cut's marker *types* are not copied. `M` adds at the playhead, `⌘M` adds and names, and
`⇧↑`/`⇧↓` walk the list — the bindings verified above. The timeline/clip distinction is real
rather than cosmetic: a marker with an `inputID` is stored in **that input's own time**, so
re-syncing the input carries its markers with it, while a timeline marker stays at its timecode.
The sidebar's **Markers** section is the marker list panel.

**Trim implemented** (#54, second slice): `⇧[` / `⇧]` trim the selected video's start / end to the
playhead, Resolve's bindings. Trimming *to a marker* is deliberately not a separate command —
`⇧↑`/`⇧↓` put the playhead on the marker, then trim, which is Resolve's own two-step and leaves
no second code path to disagree about where the cut goes.

**Split implemented** (#54, third slice): `⌘\` cuts the selected video at the playhead, Resolve's
Split Clip. Worth knowing why it does more than it looks: a `Segment`'s `ObjectOverride` can change
visibility, frame and opacity but **not** which input an object plays, so camera switching works by
showing one object and hiding another. A split therefore creates an input *and* an object *and* a
segment that swaps them, or the second half would sit on the timeline and never reach the screen.

**Data implemented** (#54, final slice): `DataInputSettings.trim` is applied in `SessionBuilder`
*before* anything else, so laps, deltas and calculated fields are all worked out from what is
left. A trimmed-away out-lap does not become lap 1 and does not compete for the best lap. Fixing
this also fixed a latent bug: `lapsFromMarkers` assumed a session starts at t=0, so any file whose
first sample is later reported its first lap as starting before its own data.

## Navigation

- **J-K-L shuttle** is universal and predates all three apps — it comes from tape-deck logging.
  `J` plays backward, `L` forward, `K` stops; repeated taps increase speed, and holding `K` while
  tapping `J`/`L` steps a frame at a time. **Onboard Studio has J, K and L** (#230): each further
  tap doubles the speed up to 8×; where the picture cannot play backward, `J` steps back a frame.
  Holding `K` with `J`/`L` is not implemented — `,` and `.` step frames.
- **`I` and `O`** set in and out points, used both to choose a portion of a source clip and to mark
  a range on the timeline for playback, render or a lift/extract. **Onboard Studio has I and O**
  (#230) for a scratch range shown on the ruler, which the export sheet offers (and starts on);
  ⌥X clears it, as in Final Cut. It is not saved with the project.
- `Home` / `End` go to start and end.
- **A click in a timeline lane moves the playhead** there in all three apps. Onboard Studio does
  this in the video and data lanes as well as the ruler and segment strip (#106); J-K-L and I/O
  are #230.

## Where Onboard Studio deliberately differs

**Arrow keys nudge the selected object; `,` and `.` step frames.**

This is the reverse of Resolve and Final Cut, where `,`/`.` nudge the selected clip and the arrow
keys belong to the timeline — left/right step a frame, up/down move the selection between edits.
The divergence is deliberate, not an oversight:

Onboard Studio's display objects are positioned in the **picture** — `x`/`y` as fractions of the frame —
not along the timeline. Nudging one with the arrow keys is the *inspector* gesture, which is what
arrows do in every app when a graphic is selected, rather than the *timeline* gesture. Issue #50
asks for exactly this. Premiere also nudges the selected clip with arrows, so the three references
do not agree with one another here in any case.

Two consequences worth keeping:

- **`,`/`.` still step frames here**, which is the one place the key is reused for a different job
  than Resolve gives it. Accept it: the alternative is leaving frame stepping unbound.
- **Resolve's fast nudge is 5 frames and is a preference**, not a fixed 10. Onboard Studio's existing
  ⇧ multiplier was already 5×; #50 moves it to 10 px because that is what the issue asks for, which
  is a defensible product choice rather than a convention. Keeping it configurable would match
  Resolve more closely than either number.

**Implemented** (#50, and #86 for the inspector fields). The plain step is a preference (**Settings ▸ Editing**, 1/2/5 px, default
1 px) and ⇧ multiplies it by ten, so the configurable half of the note above is kept. The step is
counted in **pixels of the exported frame** rather than a fraction of it, so one press moves the
same distance on screen in a 1080p and a 4K project. With no object selected the arrows fall back
to stepping the playhead, which is what #50 asks for and what the keys did before.

If Onboard Studio ever gains clips that move along the timeline, revisit all of this.

## Resolve shortcuts, from the shipped manual

Read out of `DaVinci Resolve.app/Contents/Resources/DaVinci Resolve.pdf` (4,351 pages) with
PDFKit, mostly from the "Keyboard Shortcuts in This Chapter" tables on pages 889 and 942. This is
primary source material, not a secondary guide — web research had produced conflicting claims on
six of these, and every one of those conflicts is settled below.

| Key | Function | Page |
| --- | --- | --- |
| `A` | Selection tool/mode | 942 |
| `B` | Razor blade tool — adds cuts with the pointer | 942 |
| `⌘\` | Adds a cut to the clip(s) at the playhead | 889, 942 |
| `Delete` | Delete clip and **leave a gap** — a lift edit | 889, 942 |
| `Forward Delete` | **Ripple delete** — delete and close the gap | 889, 942 |
| `N` | Toggle timeline snapping | 889, 942 |
| `,` / `.` | Nudge the selected edit or clip one frame | 942 |
| `⇧,` / `⇧.` | Fast nudge — **5 frames**, customizable | 942, 114 |
| `⇧[` / `⇧]` | Trim Start to Playhead / Trim End to Playhead | 942 |
| `E` | Extend edit: move the selected edit point to the playhead | 942 |
| `↑` / `↓` | Move the **selection** to the previous/next edit | 889, 942 |
| `⇧↑` / `⇧↓` | Previous / next **marker** | 4324 |
| `M` | Add a marker at the playhead | 718 |
| `⌘M` | Add a marker and open its edit dialog immediately | 880, 1016 |
| `W` | Dynamic Trim mode (JKL trimming) | 731 |
| `⇧Z` | Zoom to Fit | 3076, 3828 |
| `⌥⇧1`…`8` | Lock an individual video track | 889 |
| `⌥⇧9` | Lock **all** video tracks | 889 |
| `⌥⇧F1`…`F8`, `⌥⇧F9` | The same for audio tracks | 889 |
| `⌘⇧X` | Ripple cut — cut and close the gap | 942 |
| `⌘X` | Cut, leaving a gap | 942 |

Conflicts the web research could not settle, now resolved: ripple delete is **Forward Delete**
(not `⇧Delete`), zoom to fit is **`⇧Z`**, next/previous marker is **`⇧↑`/`⇧↓`** (not plain arrows),
trim-to-playhead is **`⇧[`/`⇧]`** (no `⌘`), and lock-all-tracks is **`⌥⇧9`** (`F9` is Insert Edit).

Two details worth noting because they contradict what is widely repeated online:

- **Fast nudge is 5 frames, not 10**, and it is a preference ("Default fast nudge length").
- **Up/Down arrows move the selection between edits**, so Resolve does not reserve the arrow keys
  for the playhead the way the secondary sources implied. Only left/right step frames.

## The attribute window (#200)

Not from an editor, so not verified against one; chosen against the Mac's own conventions.

- **⌥⌘A — Map Attributes…** ⌘A is Select All and ⇧⌘A is Deselect All in text and lists across
  the system, so the plain and shifted forms are taken. ⌥⌘A is unused in this app and, in the
  Finder, is only the option-variant of Select All.
- **⌘1 / ⌘2 — the window's two views**, as the Finder's ⌘1–⌘4 switch between its views and
  Xcode's ⌘-digits between its navigators. They exist only while the attribute window is in
  front, so they never shadow anything in the editor.
- **⌘F — the window's filter field**, as in any Mac window with a search field. A toolbar
  `.searchable` field does not take ⌘F by itself (checked with the UI test with the command
  removed), so the window adds it as a menu command while it is in front.

## Selection and the inspector (#280)

Chosen against Apple's own document apps, not an editor.

- **⇧⌘A — Edit ▸ Deselect All**, as in Keynote, Pages and Freeform; ⌘A and ⇧⌘A are Select All and
  Deselect All across the system. A click on empty space in the sidebar does the same, as in the
  Finder's lists.
- **⌥⌘I — View ▸ Show/Hide Inspector**, as in Pages and Keynote, with the toggle at the trailing
  end of the toolbar over the inspector it controls. The menu item names what it will do.

## Framing on the preview (#275)

- **⇧C / ⇧T — View ▸ Crop Picture / Frame Picture**, as Final Cut Pro's Crop and Transform (#276,
  #275). Both were free in this app. The crop's shapes are Photos' (Freeform, Original, 16:9, 9:16,
  4:3, Square), and a fixed shape is applied at once, as large as it fits, as Photos does. The tool's own keys follow Photos and Final Cut: Return is Done,
  Escape is Cancel, the arrows nudge (⇧ for ten times as far), pinch and ⌥-scroll zoom.
- The way in also sits at the left end of the transport, under the preview, where Final Cut and
  Resolve keep their viewer's tool pop-up — not over the picture, which is what is being judged.

## Other apps

Verified from Apple's official documentation; the Premiere rows could not be confirmed against an
Adobe page and are marked accordingly.

| Claim | App | Status |
| --- | --- | --- |
| Blade `B`, `⌘B` splits the selection, `⇧⌘B` splits all clips | Final Cut | Verified |
| Nudge selected clip `,` / `.`, ten frames `⇧,` / `⇧.` | Final Cut | Verified |
| Add marker `M`, add-and-edit `⌥M`, delete `⌃M` | Final Cut | Verified |
| Razor = `C`; `⇧`-click cuts all tracks | Premiere | Unverified |
| Lift = `;`, Extract = `'`, ripple trim = `Q` / `W` | Premiere | Unverified |
| Ripple `B`, roll `N`, slip `Y`, slide `U` as separate tools | Premiere | Unverified |

To re-check anything here, or to extract a table this doc does not cover:

```sh
swift Scripts/resolve-shortcuts.swift "Ripple Delete"   # lines matching, with page numbers
swift Scripts/resolve-shortcuts.swift --page 942        # a whole page
```

## Sources

- Final Cut Pro keyboard shortcuts — https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac
- Final Cut Pro markers — https://support.apple.com/guide/final-cut-pro/intro-to-markers-ver397279dd/mac
- Final Cut Pro slip edits — https://support.apple.com/guide/final-cut-pro/make-slip-edits-ver1632d8e4/mac
- Blackmagic forum, duration markers — https://forum.blackmagicdesign.com/viewtopic.php?f=21&t=160509
- Blackmagic forum, ripple trim to playhead — https://forum.blackmagicdesign.com/viewtopic.php?f=36&t=159927
- Blackmagic forum, no Edit-page solo/mute shortcut — https://forum.blackmagicdesign.com/viewtopic.php?f=21&t=121494
- Premiere sync lock — https://helpx.adobe.com/premiere/desktop/edit-projects/change-clip-sequence/sync-lock-to-prevent-changes.html
- Premiere clip markers — https://helpx.adobe.com/premiere/desktop/organize-media/apply-labeling/add-a-marker-to-a-clip.html

Every Resolve binding above comes from the manual shipped inside the application bundle, read with
`Scripts/resolve-shortcuts.swift`. Apple's documentation was fetched directly. Only the Premiere
rows rest on secondary sources, and they say so.

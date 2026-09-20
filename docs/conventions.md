# Editor conventions

Anyone who has edited video already knows how a timeline behaves. Matching those conventions is
free; inventing our own costs the user a translation step every time they reach for something.

DaVinci Resolve is the primary reference, Premiere Pro and Final Cut Pro secondary. Where the three
disagree, that is said explicitly rather than papered over.

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

For OverlayGen this maps cleanly: lap boundaries, incidents and sectors are all colour + name +
optional range, and a marker scoped to a data input is the clip-marker case.

## Navigation

- **J-K-L shuttle** is universal and predates all three apps — it comes from tape-deck logging.
  `J` plays backward, `L` forward, `K` stops; repeated taps increase speed, and holding `K` while
  tapping `J`/`L` steps a frame at a time. OverlayGen has no equivalent today.
- **`I` and `O`** set in and out points, used both to choose a portion of a source clip and to mark
  a range on the timeline for playback, render or a lift/extract. OverlayGen has no equivalent;
  its trim range is the closest thing, but that is a property of the input, not a scratch selection.
- `Home` / `End` go to start and end.

## Where OverlayGen deliberately differs

**Arrow keys nudge the selected object; `,` and `.` step frames.**

This is the reverse of Resolve and Final Cut, where arrows move the playhead and `,`/`.` nudge the
selected clip by a frame. The divergence is deliberate, not an oversight:

OverlayGen's display objects are positioned in the **picture** — `x`/`y` as fractions of the frame —
not along the timeline. Nudging one with the arrow keys is the *inspector* gesture, which is what
arrows do in every app when a graphic is selected, rather than the *timeline* gesture. Issue #50
asks for exactly this. Premiere also nudges the selected clip with arrows, so the three references
do not agree with one another here in any case.

If OverlayGen ever gains clips that move along the timeline, revisit this.

## Shortcut claims and their status

Researched from the sources below. **The unverified rows must not be copied into the app's
Keyboard Shortcuts window without being checked against a licensed install first** — a shortcut
reference that is confidently wrong is worse than one that is silent.

| Claim | App | Status |
| --- | --- | --- |
| Blade tool = `B`, Pointer = `A` | Resolve | Corroborated by several independent guides; the official shortcut PDF could not be read directly. Verify. |
| Split Clip at playhead, all tracks = `⌘\`; Join = `⌥\` | Resolve | As above — consistent across secondary sources, no readable primary. Verify. |
| Trim Edit Mode = `T`; Dynamic Trim = `W` | Resolve | Corroborated, not primary-verified. |
| Snapping = `N` | Resolve | Consistently reported across many sources; long-standing. Reliable. |
| Add marker = `M`; press again to name | Resolve, Premiere | Widely corroborated; the exact "twice or ⌘M" behaviour is community-sourced. |
| Next / previous marker = `⇧↓` / `⇧↑` | Resolve | **Conflict** — plain `↑`/`↓` also appears in some guides. Unresolved. |
| Ripple delete vs lift key | Resolve | **Conflict** — `⇧Delete`, plain `Delete`, and forward-delete are all claimed. Unresolved, and high risk. |
| Zoom to fit = `Z` or `⇧Z` | Resolve | **Conflict** between sources, probably a version change. Unresolved. |
| Ripple Trim Start/End to playhead = `⇧⌘[` / `⇧⌘]` | Resolve | Inferred from a forum thread, not an official table. Probable, unverified. |
| Track lock = `⌥⇧<number>`; all tracks = `F9` or `9` | Resolve | Lock binding corroborated; the all-tracks key is disputed. |
| Move a clip to the track above/below by keyboard | Resolve | **No shortcut found at all.** Likely mouse-only. |
| Lift = `;`, Extract = `'`, ripple trim = `Q`/`W` | Premiere | Multiple secondary sources agree; no Adobe page fetched. Unverified. |
| Blade = `B`, `⌘B` splits selection, `⇧⌘B` splits all | Final Cut | **Verified** from Apple's official shortcut page. |
| Nudge selected clip = `,` / `.`, ten frames = `⇧,` / `⇧.` | Final Cut | **Verified** from Apple's official docs. |
| Add marker `M`, add-and-edit `⌥M`, delete `⌃M` | Final Cut | **Verified** from Apple's marker docs. |

## Sources

- Final Cut Pro keyboard shortcuts — https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac
- Final Cut Pro markers — https://support.apple.com/guide/final-cut-pro/intro-to-markers-ver397279dd/mac
- Final Cut Pro slip edits — https://support.apple.com/guide/final-cut-pro/make-slip-edits-ver1632d8e4/mac
- Blackmagic forum, duration markers — https://forum.blackmagicdesign.com/viewtopic.php?f=21&t=160509
- Blackmagic forum, ripple trim to playhead — https://forum.blackmagicdesign.com/viewtopic.php?f=36&t=159927
- Blackmagic forum, no Edit-page solo/mute shortcut — https://forum.blackmagicdesign.com/viewtopic.php?f=21&t=121494
- Premiere sync lock — https://helpx.adobe.com/premiere/desktop/edit-projects/change-clip-sequence/sync-lock-to-prevent-changes.html
- Premiere clip markers — https://helpx.adobe.com/premiere/desktop/organize-media/apply-labeling/add-a-marker-to-a-clip.html

Apple's documentation was the only source that could be fetched and read directly throughout;
Blackmagic's shortcut PDF returned unreadable binary, which is why so many Resolve rows above are
marked unverified.

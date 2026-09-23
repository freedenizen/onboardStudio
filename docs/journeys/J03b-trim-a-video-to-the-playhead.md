# J3b Trim a video to the playhead
*Source: Resolve Trim Start / Trim End (`⇧[` / `⇧]`), verified in `docs/conventions.md`.*

1. Select a video in the sidebar. With the playhead at the very start there is nothing to drop,
   and the status line says so rather than silently doing nothing.
2. Step a few frames in with `.` and **Project ▸ Trim Start to Playhead**; the input's start
   position follows the playhead.
3. **Undo** puts it back. Nothing touches the file on disk.

Tests: `TrimUITests.testTrimsAVideoToThePlayheadAndRefusesWhenItCannot`. Model:
`VideoEditingModelTests` ("Timeline trimming arithmetic").

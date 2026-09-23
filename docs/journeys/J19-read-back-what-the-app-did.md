# J19 Read back what the app did
*Source: #112 — the status line kept one message, and the next one replaced it before it could be
read.*

1. Walk between markers: the status line says *Marker 1*, then *Marker 2*, then *No marker that
   way*, each replacing the last.
2. Dismiss it. **View ▸ Show Activity** (⌥⌘L) lists all three, newest first, with their times.
3. **Copy All** puts them on the clipboard, one line each.

Tests: `ActivityUITests.testEveryStatusMessageIsKeptAndCanBeCopied`.

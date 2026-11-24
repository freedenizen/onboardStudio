# What's New, release by release

Each release that adds features (`vX.Y.0`) has a file here, `vX.Y.0.md`: a short *What's New*
written for someone who drives, not for someone who reads commits. It opens that release's page
on GitHub, which is where the README's **What's new** leads; the list of every feature and fix
follows it there, made from the commits by `Scripts/release-notes.sh` (#702).

The page GitHub generates by itself is every pull request's title — `ci:`, `test(ui):` and
`chore:` among them. Nothing on it says what the release is for.

## Writing one

Write it **before the tag**. The release workflow checks for the file first and stops, before it
builds anything, when a `vX.Y.0` tag has none. A fix release (`vX.Y.Z`) and a pre-release
(`vX.Y.0-rc1`) may go without; their pages open with the list.

- **Begin with `## What's New`**, so the file reads the same here and on the release page.
- **What a driver can now do, and where it is.** "Analysis lays laps over each other as data; it
  opens from a session in the Logbook" — not "added `LapAnalysisView`".
- **The words of the app and the guide.** A *session*, a *track day*, an *attribute*: whatever
  the menus and `docs/user-guide.md` call it (`docs/ux-checklist.md`, G1).
- **Group by what it is for**, five to eight short paragraphs, each led by a few words in bold.
  A fix is worth a line only when a user would have met the fault.
- **Say what changes for a project or a logbook someone already has**, when anything does.
- **No numbers from anyone's driving.** Examples are made up.
- About 150 to 250 words. The list below it carries the rest.

To see the page as it will be published, before or after tagging:

```sh
Scripts/release-notes.sh v0.38.0
```

`Scripts/test-release-notes.sh` holds the script's cases; Lint (fast) and the pre-commit hook
run them.

## Releases

- [v0.37.0](v0.37.0.md)

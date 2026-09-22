# Contributing

## Setup

```sh
brew install xcodegen swiftlint actionlint   # optional but recommended
Scripts/setup-dev.sh                          # installs git hooks and allowed-signers
swift build && swift test
```

## Workflow

- Work on a branch and open a pull request against `main`. `main` is protected: the required
  checks must pass, history is linear, and every commit must be signed. A PR does **not** have
  to be up to date with `main` to merge — two PRs that are each green can still conflict once
  combined, so the push run on `main` is what proves `main` itself. When it is red, the **`main
  health`** job opens (or adds to) the issue labelled `main-red` and closes it on the next green
  push; the fix is to fix forward promptly, never to leave `main` red.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org):
  `feat(importers): add RaceChrono CSV v3`, `fix(mediakit): …`, `ci: …`, `docs: …`, `test: …`.
- Every behaviour change ships with unit tests. Parsers and renderers are tested against fixtures
  in `Tests/Fixtures`; renderers additionally use golden images.
- Formatting is enforced by `swift format` (`.swift-format`) and style by SwiftLint
  (`.swiftlint.yml`). The pre-commit hook runs both on staged files.

## Signed commits

Commits on `main` must be signed. SSH signing is the simplest option:

```sh
git config --global gpg.format ssh
git config --global user.signingkey "ssh-ed25519 AAAA…"   # your public key
git config --global commit.gpgsign true
```

Register the same key on GitHub as a **signing key** (Settings → SSH and GPG keys → New SSH key →
key type "Signing Key") so commits show as Verified, and add it to `.github/allowed_signers` so CI
can verify it. If your private key lives in an agent such as 1Password, make sure `SSH_AUTH_SOCK`
points at that agent when committing.

## Tests

```sh
Scripts/test.sh quick                        # everything but the two-hour session and the fuzz suites
swift test --filter ImportersTests           # one target
swift test                                   # everything, as CI runs it
UPDATE_GOLDENS=1 swift test --filter RenderKitTests   # regenerate golden images
```

Media tests use `ffprobe` when it is installed and skip otherwise; the nightly workflow is the
one place in CI where they run.

## Project rules

`CLAUDE.md` and `.claude/rules/` hold the working conventions — commands, repo etiquette, the
rules that must never be broken (no hard-coded logger channels; a saved project never renders
differently) and the rendering, importer and UI-test pitfalls that have each cost a build cycle.
They are written for the AI assistant and the review bot but apply to everyone; read them before
a first change.

## Releases

Tag `vX.Y.Z` on `main`; the Release workflow builds, signs, packages and publishes the DMG,
Sparkle appcast and CLI tarball. See `docs/architecture.md`.

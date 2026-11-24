#!/bin/bash
# The cases for Scripts/release-notes.sh, run by Lint (fast) and by the pre-commit hook when
# either file is staged. That script writes the page a release is published with, and it runs
# once per release, at the end of an hour's build: a mistake in it is found on the public page.
#
# Builds a throwaway repository holding a copy of the script, with tags and commits whose
# subjects are the kinds this repository's are.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GITHUB_REPOSITORY=owner/repo

git init -q -b main "$work/repo"
cd "$work/repo"
git config user.name test
git config user.email test@example.com
git config commit.gpgsign false
git config tag.gpgsign false
mkdir -p Scripts docs/releases
cp "$scripts/release-notes.sh" Scripts/

commit() { git commit -q --allow-empty -m "$1"; }
notes() { Scripts/release-notes.sh "$@"; }

failures=0
check() { # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1"
    diff <(echo "$2") <(echo "$3") | sed 's/^/      /' || true
    failures=$((failures + 1))
  fi
}
refused() { # refused <name> <command…>: the command fails
  local name=$1
  shift
  if "$@" > /dev/null 2>&1; then
    echo "FAIL  $name (it succeeded)"
    failures=$((failures + 1))
  else
    echo "ok    $name"
  fi
}

git add Scripts
commit "chore: the beginning"
commit "feat(logbook): an old feature (#1)"
git tag v0.1.0
commit "feat(logbook): rate every session's GPS (#10)"
commit "ci: run the tests on a faster runner (#11)"
commit "fix(editor): the gear no longer sits on the speedometer (#12)"
commit "test(ui): a journey for the garage (#13)"
commit "docs: say what the import report means (#14)"
commit "feat: export a session's telemetry (#15)"
commit "refactor(importers): one reader for both CSV versions (#16)"
commit "fix!: a project saved by 0.1 opens as it rendered (#17)"
commit "chore(release): v0.2.0"

# --- A feature release must have its written notes ---------------------------------------
refused "a feature release with no written notes is refused" notes v0.2.0
refused "and so is the check for it" notes --check v0.2.0
: > docs/releases/v0.2.0.md
refused "an empty file is not written notes" notes --check v0.2.0
printf '<!-- What the release adds, for someone who drives.\n     Delete this. -->\n' > docs/releases/v0.2.0.md
refused "nor is the template's comment alone" notes --check v0.2.0

cat > docs/releases/v0.2.0.md <<'NOTES'
<!-- A comment the template left. -->
## What's New

**Every session's GPS is rated**, so you know which brake points to trust.
NOTES
check "the check passes once they are written" \
  "release-notes: docs/releases/v0.2.0.md opens the page for v0.2.0." "$(notes --check v0.2.0)"

# --- The page: the written notes, then features and fixes, newest first --------------------
expected="## What's New

**Every session's GPS is rated**, so you know which brake points to trust.

## Every feature and fix

### New

- Export a session's telemetry (#15)
- Rate every session's GPS (#10)

### Fixed

- A project saved by 0.1 opens as it rendered (#17)
- The gear no longer sits on the speedometer (#12)

**Everything that changed:** https://github.com/owner/repo/compare/v0.1.0...v0.2.0"
check "before the tag exists, the page is read from what is checked out" "$expected" "$(notes v0.2.0)"
git tag v0.2.0
commit "feat(coaching): something for the release after (#20)"
check "once tagged, it is the tag's, whatever came after" "$expected" "$(notes v0.2.0)"

# --- A fix release and a pre-release may go without ----------------------------------------
commit "fix(logbook): a day's date can be changed (#21)"
git tag v0.2.1
check "a fix release with no written notes opens with the list" \
  "## Every feature and fix

### New

- Something for the release after (#20)

### Fixed

- A day's date can be changed (#21)

**Everything that changed:** https://github.com/owner/repo/compare/v0.2.0...v0.2.1" "$(notes v0.2.1)"
check "and its check says so" \
  "release-notes: no written notes for v0.2.1; its page opens with the list." "$(notes --check v0.2.1)"

commit "feat(replay): a lap replayed beside another (#30)"
git tag v0.3.0-rc1
commit "fix(replay): the second lap starts with the first (#31)"
git tag v0.3.0-rc2
check "a pre-release lists what changed since the pre-release before" \
  "## Every feature and fix

### Fixed

- The second lap starts with the first (#31)

**Everything that changed:** https://github.com/owner/repo/compare/v0.3.0-rc1...v0.3.0-rc2" "$(notes v0.3.0-rc2)"

echo "## What's New" > docs/releases/v0.3.0.md
echo "Laps replay side by side." >> docs/releases/v0.3.0.md
git tag v0.3.0
check "a release proper lists everything since the last release proper" \
  "## What's New
Laps replay side by side.

## Every feature and fix

### New

- A lap replayed beside another (#30)

### Fixed

- The second lap starts with the first (#31)

**Everything that changed:** https://github.com/owner/repo/compare/v0.2.1...v0.3.0" "$(notes v0.3.0)"

# --- The first release of all has nothing to compare with -----------------------------------
check "the first release lists everything and links no comparison" \
  "## Every feature and fix

### New

- An old feature (#1)" "$(echo '## x' > docs/releases/v0.1.0.md; notes v0.1.0 | sed '1,2d'; rm docs/releases/v0.1.0.md)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"

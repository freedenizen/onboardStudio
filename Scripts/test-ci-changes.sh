#!/bin/bash
# The cases for Scripts/ci-changes.sh, run by Lint (fast) and by the pre-commit hook when either
# file is staged. A wrong answer from that script is a suite that silently did not run, which no
# other check would notice.
#
# Builds a throwaway repository with a bare "origin" beside it, and puts a stand-in for `gh` on
# the PATH that answers the three questions the script asks GitHub:
#
#   FAKE_DRAFT    the pull request's draft flag
#   FAKE_MERGED   "<number> <head sha>" of the merged pull request a commit came from, or empty
#   FAKE_GREEN    how many CI runs passed on that head
#   FAKE_FAIL     set to make every question fail, as a GitHub outage would
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/bin/bash
[ -z "${FAKE_FAIL:-}" ] || exit 1
case "$2" in
  */commits/*/pulls) [ -z "${FAKE_MERGED:-}" ] || echo "$FAKE_MERGED" ;;
  */pulls/*) echo "${FAKE_DRAFT:-false}" ;;
  */actions/workflows/*) echo "${FAKE_GREEN:-0}" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
export GITHUB_REPOSITORY=owner/repo

git init -q --bare "$work/origin.git"
git init -q -b main "$work/repo"
cd "$work/repo"
git config user.name test
git config user.email test@example.com
git config commit.gpgsign false
git remote add origin "$work/origin.git"
mkdir Scripts
cp "$scripts/ci-changes.sh" Scripts/

# write <path> <text>: a file with that text, staged.
write() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
  git add "$1"
}
# branch <name> <from>: a new branch at <from>, checked out.
branch() { git checkout -q -b "$1" "$2"; }
commit() {
  git commit -q -m "$1"
  git rev-parse HEAD
}
# squash <before> <head>: the commit a squash merge of <head> onto <before> leaves when the
# branch was up to date — the branch's tree, with <before> as its only parent.
squash() { git commit-tree "$2^{tree}" -p "$1" -m "squash"; }

write project.yml 'settings:
  base:
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"'
write README.md 'The app is at v1.0.0.'
write Sources/OnboardStudioApp/View.swift 'struct View {}'
write Sources/RenderKit/Draw.swift 'struct Draw {}'
git add Scripts
m0=$(commit "start")

failures=0
# expect <name> <output> <line>...: every line must be in the output, exactly.
expect() {
  local name=$1 output=$2 line
  shift 2
  for line in "$@"; do
    if ! grep -qxF "$line" <<<"$output"; then
      echo "FAILED: $name — wanted \`$line\`, got:" >&2
      sed 's/^/    /' <<<"$output" >&2
      failures=$((failures + 1))
      return
    fi
  done
  echo "ok: $name"
}
classify() { Scripts/ci-changes.sh classify "$1" "$2"; }
on_push() { EVENT=push BEFORE=$1 SHA=$2 Scripts/ci-changes.sh decide; }
on_pull_request() { EVENT=pull_request PR=7 BASE=$1 HEAD=$2 Scripts/ci-changes.sh decide; }

# --- what a change needs -------------------------------------------------------------------

branch docs "$m0"
write docs/user-guide.md 'How to.'
write README.md 'The app is at v1.0.0. More.'
write .claude/rules/appui.md 'A rule.'
write CONTRIBUTING.md 'Welcome.'
docs=$(commit "docs")
expect "documentation needs no Mac" "$(classify "$m0" "$docs")" code=false app=false

branch library "$m0"
write Sources/RenderKit/Draw.swift 'struct Draw { let width = 1 }'
library=$(commit "library")
expect "a library needs Lint and Test, not the UI tests" "$(classify "$m0" "$library")" code=true app=false

branch app "$m0"
write Sources/OnboardStudioApp/View.swift 'struct View { let title = "" }'
app=$(commit "app")
expect "the app needs the UI tests" "$(classify "$m0" "$app")" code=true app=true

branch uitest "$m0"
write UITests/OnboardStudioUITests/JourneyUITests.swift 'final class JourneyUITests {}'
uitest=$(commit "ui test")
expect "a UI test needs the UI tests" "$(classify "$m0" "$uitest")" code=true app=true

branch workflow "$m0"
write .github/workflows/ci.yml 'name: CI'
workflow=$(commit "workflow")
expect "ci.yml needs the UI tests" "$(classify "$m0" "$workflow")" code=true app=true

branch detector "$m0"
printf '# changed\n' >>Scripts/ci-changes.sh
git add Scripts/ci-changes.sh
detector=$(commit "detector")
expect "this script needs the UI tests" "$(classify "$m0" "$detector")" code=true app=true
git checkout -q "$m0" -- Scripts/ci-changes.sh

branch bump "$m0"
write project.yml 'settings:
  base:
    MARKETING_VERSION: "1.1.0"
    CURRENT_PROJECT_VERSION: "1"'
write README.md 'The app is at v1.1.0.'
write Sources/ProjectModel/Version.swift 'let marketing = "1.1.0"'
bump=$(commit "chore: 1.1.0")
expect "a version bump needs Lint and Test, not the UI tests" "$(classify "$m0" "$bump")" code=true app=false

branch target "$m0"
write project.yml 'settings:
  base:
    MARKETING_VERSION: "1.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_HARDENED_RUNTIME: YES'
target=$(commit "project")
expect "any other change to project.yml needs the UI tests" "$(classify "$m0" "$target")" code=true app=true

branch nested "$m0"
write Sources/ProjectModel/Resources/Tracks/README.md 'Read by a test.'
write Tests/Fixtures/notes.md 'A fixture.'
nested=$(commit "nested markdown")
expect "markdown under Sources or Tests is code" "$(classify "$m0" "$nested")" code=true app=false

# main moves on with a change to the app; the documentation branch stays where it was.
git checkout -q main
git merge -q --ff-only app
m1=$(git rev-parse HEAD)
expect "a branch behind main answers for its own change only" "$(classify "$m1" "$docs")" code=false app=false

# --- pull requests -------------------------------------------------------------------------

expect "a draft waits" "$(FAKE_DRAFT=true on_pull_request "$m0" "$app")" draft=true code=false app=false
expect "a ready pull request is classified" "$(on_pull_request "$m0" "$app")" draft=false code=true app=true
if FAKE_FAIL=1 on_pull_request "$m0" "$app" >/dev/null 2>&1; then
  echo "FAILED: a pull request GitHub will not describe must fail, not pass" >&2
  failures=$((failures + 1))
else
  echo "ok: a pull request GitHub will not describe fails the job"
fi

# --- pushes to main ------------------------------------------------------------------------

# A branch that was up to date with main (m1) when it merged: the merge commit has its tree.
branch feature "$m1"
write Sources/OnboardStudioApp/View.swift 'struct View { let title = "Logbook" }'
feature=$(commit "feature")
git push -q origin "$feature:refs/pull/1/head"
merged=$(squash "$m1" "$feature")

expect "a tree its pull request tested is not run again" \
  "$(FAKE_MERGED="1 $feature" FAKE_GREEN=1 on_push "$m1" "$merged")" draft=false code=false app=false
expect "no green run on the branch: run it" \
  "$(FAKE_MERGED="1 $feature" FAKE_GREEN=0 on_push "$m1" "$merged")" code=true app=true
expect "no pull request behind the commit: run it" \
  "$(FAKE_GREEN=1 on_push "$m1" "$merged")" code=true app=true
expect "GitHub does not answer: run it" \
  "$(FAKE_FAIL=1 on_push "$m1" "$merged")" code=true app=true
expect "a head commit the fetch did not bring: run it" \
  "$(FAKE_MERGED="1 1111111111111111111111111111111111111111" FAKE_GREEN=1 on_push "$m1" "$merged" 2>/dev/null)" \
  code=true app=true

# The same tree on main, but main's previous tip (m2) was never in the branch: the pull request's
# run tested the branch merged into an older main, which need not be this tree.
git checkout -q main
write Sources/RenderKit/Draw.swift 'struct Draw { let height = 2 }'
m2=$(commit "main moves on")
behind=$(squash "$m2" "$feature")
expect "a branch that merged behind main is run" \
  "$(FAKE_MERGED="1 $feature" FAKE_GREEN=1 on_push "$m2" "$behind")" code=true app=true

# Up to date, but the commit on main is not the branch's tree.
git checkout -q -b extra "$feature"
write Sources/OnboardStudioApp/View.swift 'struct View { let title = "Other" }'
extra=$(commit "extra")
different=$(squash "$m1" "$extra")
expect "a commit that is not the branch's tree is run" \
  "$(FAKE_MERGED="1 $feature" FAKE_GREEN=1 on_push "$m1" "$different")" code=true app=true

# Documentation that merged behind main is not "already tested", and is classified like any
# other change: main's tree plus the branch's own.
git push -q origin "$docs:refs/pull/2/head"
git checkout -q -b docs-landed "$m1"
git cherry-pick "$docs" >/dev/null
docs_merged=$(git rev-parse HEAD)
expect "documentation merged behind main still needs no Mac" \
  "$(FAKE_MERGED="2 $docs" FAKE_GREEN=1 on_push "$m1" "$docs_merged")" code=false app=false

expect "a push with nothing before it runs everything" \
  "$(on_push 0000000000000000000000000000000000000000 "$merged")" code=true app=true

if [ "$failures" -gt 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi

#!/bin/bash
# Which of CI's macOS jobs a change needs (#646). At most five macOS jobs run at once for the
# whole account, so a job that a change cannot affect costs every other run a wait for a runner.
#
#   Scripts/ci-changes.sh decide                  what this CI run needs, read from the workflow's
#                                                 environment (the `changes` job in ci.yml)
#   Scripts/ci-changes.sh classify <base> <head>  what the change from <base> to <head> needs
#
# Both print `key=value` lines, the form $GITHUB_OUTPUT takes:
#
#   code   true when Lint and Test must run: anything changed outside the documentation
#   app    true when the UI tests must run: the app, the tests or their plumbing changed
#   draft  true for a draft pull request, which waits for all of them (#237)
#   why    the reason, for the log
#
# A wrong "false" here is a suite that silently did not run, so every rule errs towards running:
# a path this file does not know is code, and a question GitHub does not answer is "not tested".
# Scripts/test-ci-changes.sh holds the cases; Lint (fast) runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

# What neither Lint nor Test reads. Kept short on purpose: nothing under Sources/, Tests/,
# Scripts/ or .github/ belongs here, whatever its extension.
documentation='^(docs/|\.claude/|[^/]+\.md$|LICENSE$)'

# What the UI tests are built from. ci.yml and this script are in the list because the
# build-once/shard plumbing and the decision to run it live in them: a change to either that
# skipped the suite would be a change to the UI tests that the UI tests never saw (#142).
app='^(Sources/OnboardStudioApp/|UITests/|project\.yml$|\.github/workflows/ci\.yml$|Scripts/ci-changes\.sh$)'

# True when project.yml changed between the two commits in its version line and nowhere else.
# A release's version bump is that one line, and the app the UI tests drive does not differ by
# it: before this, a three-line release commit ran the whole suite (#536).
only_the_version_changed() {
  local lines
  lines=$(git diff -U0 "$1" "$2" -- project.yml | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' || true)
  [ -n "$lines" ] && ! grep -qvE '^[+-][[:space:]]*MARKETING_VERSION:' <<<"$lines"
}

# `base...head`, not `base..head`: what the branch itself changed. Against a base that has moved
# on, two dots would also list everything main gained since, and a documentation change would
# look like a change to the code.
classify() {
  local base=$1 head=$2 paths code=false needs_app=false why
  paths=$(git diff --name-only "$base...$head")
  if grep -qvE "$documentation" <<<"$paths"; then code=true; fi
  if [ -z "$paths" ]; then code=true; fi
  if grep -E "$app" <<<"$paths" | grep -qv '^project\.yml$'; then
    needs_app=true
  elif grep -q '^project\.yml$' <<<"$paths" && ! only_the_version_changed "$base" "$head"; then
    needs_app=true
  fi
  if [ "$needs_app" = true ]; then
    why="the app, the UI tests or their plumbing changed"
  elif [ "$code" = true ]; then
    why="nothing the UI tests are built from changed"
  else
    why="only the documentation changed"
  fi
  printf 'code=%s\napp=%s\nwhy=%s\n' "$code" "$needs_app" "$why"
}

# True when the tree at <sha> is one a merged pull request's green run already tested, so a
# second run on main would repeat it job for job. Three things must hold:
#
#   - main's previous tip is in the pull request's history. A pull_request run tests the merge of
#     the branch into main as it was then; when the branch already contained main, that merge is
#     the branch itself, whichever earlier tip main was at.
#   - the commit on main has the branch's tree: nothing arrived with the merge.
#   - CI passed on the branch's head commit.
#
# The ruleset does not require a branch to be up to date, so a pull request that merges behind
# main fails the first test and main is run in full, as it always was.
tested() {
  local before=$1 sha=$2 found number head green
  found=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" \
    --jq '[.[] | select(.merged_at != null)][0] | select(. != null) | "\(.number) \(.head.sha)"') || return 1
  [ -n "$found" ] || return 1
  read -r number head <<<"$found"
  # The branch is deleted on merge; the pull request's own ref still holds its head commit.
  git fetch --quiet origin "refs/pull/$number/head" || return 1
  git merge-base --is-ancestor "$before" "$head" || return 1
  [ "$(git rev-parse "$sha^{tree}")" = "$(git rev-parse "$head^{tree}")" ] || return 1
  green=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$head&event=pull_request&status=success&per_page=1" \
    --jq .total_count) || return 1
  [ "$green" -gt 0 ] || return 1
  echo "$number"
}

decide() {
  local draft number
  if [ "$EVENT" = "pull_request" ]; then
    # Asked of the pull request as it is now, not the event's payload: a push and "ready" a
    # second apart fire two runs, and the one that survives may carry a payload that still says
    # draft (#239).
    draft=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR" --jq .draft)
    echo "draft=$draft"
    if [ "$draft" = "true" ]; then
      printf 'code=false\napp=false\nwhy=a draft waits until it is marked ready for review\n'
    else
      classify "$BASE" "$HEAD"
    fi
    return
  fi
  echo "draft=false"
  # A push with nothing before it to compare with (a new branch) runs everything.
  if ! git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
    printf 'code=true\napp=true\nwhy=there is no earlier commit to compare with\n'
  elif number=$(tested "$BEFORE" "$SHA"); then
    printf 'code=false\napp=false\nwhy=pull request #%s tested this tree, and CI passed on it\n' "$number"
  else
    classify "$BEFORE" "$SHA"
  fi
}

case "${1:-}" in
  decide) decide ;;
  classify) classify "$2" "$3" ;;
  *)
    echo "usage: $0 decide | classify <base> <head>" >&2
    exit 2
    ;;
esac

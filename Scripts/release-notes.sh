#!/usr/bin/env bash
# The body of a release's page on GitHub (#702): What's New as it was written for drivers in
# docs/releases/<tag>.md, then every feature and fix since the release before, read from the
# subjects of the commits on main. The page GitHub generates is every pull request's title,
# `ci:`, `test:` and `chore:` among them, and nothing on it is in a driver's words.
#
#   Scripts/release-notes.sh v0.38.0            the page's body, on stdout
#   Scripts/release-notes.sh --check v0.38.0    only whether the written notes are there
#
# A release that adds features (vX.Y.0) must have its written notes, and the release workflow
# checks for them before it builds anything. A fix release (vX.Y.Z) or a pre-release (v…-rc1)
# may go without, and then its page opens with the list.
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK=1
  shift
fi
TAG=${1:?usage: release-notes.sh [--check] <tag>}
WRITTEN="docs/releases/$TAG.md"
REPOSITORY=${GITHUB_REPOSITORY:-freedenizen/onboardStudio}

# The words of the file, without the comments a template leaves in it.
written() {
  awk '
    /^<!--/ { if ($0 !~ /-->[ \t]*$/) hidden = 1; next }
    hidden { if ($0 ~ /-->[ \t]*$/) hidden = 0; next }
    { print }' "$WRITTEN"
}

if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.0$ ]]; then
  if [[ ! -f "$WRITTEN" ]]; then
    echo "release-notes: $TAG adds features and has no $WRITTEN." >&2
    echo "Write What's New for drivers there first: docs/releases/README.md says how." >&2
    exit 1
  fi
  if [[ -z "$(written | tr -d '[:space:]')" ]]; then
    echo "release-notes: $WRITTEN has nothing in it." >&2
    exit 1
  fi
fi
if [[ $CHECK == 1 ]]; then
  if [[ -f "$WRITTEN" ]]; then
    echo "release-notes: $WRITTEN opens the page for $TAG."
  else
    echo "release-notes: no written notes for $TAG; its page opens with the list."
  fi
  exit 0
fi

# The tag itself once it exists, else what is checked out: the page can be read before tagging.
REF=HEAD
if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then REF="refs/tags/$TAG"; fi
# The release before: for a release proper, the last one that was not a pre-release.
EXCLUDE=()
if [[ "$TAG" != *-* ]]; then EXCLUDE=(--exclude '*-*'); fi
PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' ${EXCLUDE[@]+"${EXCLUDE[@]}"} "$REF^" 2> /dev/null || true)
RANGE="$REF"
if [[ -n "$PREVIOUS" ]]; then RANGE="$PREVIOUS..$REF"; fi

# "feat(logbook): rate every session's GPS (#610)" is "- Rate every session's GPS (#610)" under
# New; `fix` goes under Fixed; every other kind of change is left out.
changes() {
  git log --first-parent --format=%s "$RANGE" | awk -v kind="$1" '
    {
      type = $0
      sub(/[(!:].*/, "", type)
      if (type != kind || $0 !~ /^[a-z]+(\([^)]*\))?!?: /) next
      text = $0
      sub(/^[a-z]+(\([^)]*\))?!?: /, "", text)
      print "- " toupper(substr(text, 1, 1)) substr(text, 2)
    }'
}

if [[ -f "$WRITTEN" ]]; then
  written
  echo
fi
ADDED=$(changes feat)
FIXED=$(changes fix)
if [[ -n "$ADDED$FIXED" ]]; then
  echo "## Every feature and fix"
  echo
  if [[ -n "$ADDED" ]]; then printf '### New\n\n%s\n\n' "$ADDED"; fi
  if [[ -n "$FIXED" ]]; then printf '### Fixed\n\n%s\n\n' "$FIXED"; fi
fi
if [[ -n "$PREVIOUS" ]]; then
  echo "**Everything that changed:** https://github.com/$REPOSITORY/compare/$PREVIOUS...$TAG"
fi

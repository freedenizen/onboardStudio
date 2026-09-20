#!/bin/bash
# Checks that every XCUITest class runs on exactly one shard of the "UI tests" matrix.
#
# The shards select tests with -only-testing: by class name, so a class that nobody added to the
# matrix is selected by no shard: it runs nowhere, every shard still passes, and the coverage hole
# is invisible. This turns that silent gap into a Lint failure.
set -euo pipefail
cd "$(dirname "$0")/.."

workflow=".github/workflows/ci.yml"
status=0

fail() {
  echo "error: $1" >&2
  status=1
}

# Declared: every class under UITests/ whose name ends in UITests. The shared base class is
# OnboardStudioUITestCase, which deliberately does not match — it holds no tests of its own.
declared=$(grep -rhoE '^(final )?class [A-Za-z0-9_]+UITests\b' UITests | awk '{print $NF}' | sort -u)

# Listed: the words on the matrix's `classes:` lines.
listed=$(awk '/^ +classes: /{sub(/^ +classes: /, ""); print}' "$workflow" | tr ' ' '\n' | grep -v '^$' | sort)

[ -n "$declared" ] || fail "found no XCUITest classes under UITests/ — has the layout changed?"
[ -n "$listed" ] || fail "found no shard \`classes:\` lines in $workflow — has the matrix changed?"

while read -r class; do
  [ -n "$class" ] && fail "$class is listed on more than one shard in $workflow"
done <<<"$(echo "$listed" | uniq -d)"

# comm needs each side deduplicated, or a class listed twice also reads as a class that only the
# workflow knows about — one fault reported as two, the second of them wrong.
while read -r class; do
  [ -n "$class" ] && fail "$class runs on no shard — add it to a \`classes:\` line in $workflow"
done <<<"$(comm -23 <(echo "$declared") <(echo "$listed" | uniq))"

while read -r class; do
  [ -n "$class" ] && fail "$workflow shards $class, which no longer exists under UITests/"
done <<<"$(comm -13 <(echo "$declared") <(echo "$listed" | uniq))"

if [ "$status" -eq 0 ]; then
  echo "UI test shards OK: $(echo "$declared" | wc -l | tr -d ' ') classes, each on exactly one shard."
fi
exit "$status"

#!/bin/bash
# Which CI shard each XCUITest class runs on, and a check that every class runs on exactly one.
#
#   Scripts/check-ui-test-shards.sh             check (Lint (fast) and the pre-commit hook)
#   Scripts/check-ui-test-shards.sh --shard 2   print shard 2's classes, space-separated (CI)
#
# A class says its shard in a `// ci-shard: N` line above its declaration (above its doc comment,
# if it has one). The shard lives with the test rather than in ci.yml so that adding a class edits
# only its own file: when the lists lived in ci.yml, every PR that added a class edited the same
# three lines, and each merge left the other open PRs in conflict (#237).
#
# A class with no line runs on no shard: every shard still passes and the hole is invisible. That
# is what the check turns into a failure.
set -euo pipefail
cd "$(dirname "$0")/.."

shards=3

# "Class shard" for every XCUITest class; shard is "-" when the class has no ci-shard line. The
# shared base class OnboardStudioUITestCase does not end in UITests and holds no tests.
assignments() {
  awk '
    /^\/\/ ci-shard: / { shard = $3; next }
    /^(final )?class [A-Za-z0-9_]+UITests[:[:space:]]/ {
      name = ($1 == "final") ? $3 : $2
      sub(/:.*/, "", name)
      print name, (shard == "" ? "-" : shard)
      shard = ""
    }
  ' UITests/OnboardStudioUITests/*.swift | sort
}

if [ "${1:-}" = "--shard" ]; then
  assignments | awk -v n="$2" '$2 == n { printf "%s%s", sep, $1; sep = " " } END { print "" }'
  exit 0
fi

status=0
fail() {
  echo "error: $1" >&2
  status=1
}

all=$(assignments)
[ -n "$all" ] || fail "found no XCUITest classes under UITests/ — has the layout changed?"

while read -r class shard; do
  [ -z "$class" ] && continue
  if [ "$shard" = "-" ]; then
    fail "$class runs on no shard — put a \`// ci-shard: N\` line (1–$shards) above its declaration"
  elif ! [[ "$shard" =~ ^[0-9]+$ ]] || [ "$shard" -lt 1 ] || [ "$shard" -gt "$shards" ]; then
    fail "$class names shard $shard; there are shards 1 to $shards"
  fi
done <<<"$all"

while read -r class; do
  [ -n "$class" ] && fail "two classes are called $class"
done <<<"$(echo "$all" | awk '{print $1}' | uniq -d)"

if [ "$status" -eq 0 ]; then
  echo "UI test shards OK: $(echo "$all" | wc -l | tr -d ' ') classes, each on exactly one shard" \
    "($(for n in $(seq 1 $shards); do printf '%s ' "$(echo "$all" | awk -v n="$n" '$2 == n' | wc -l | tr -d ' ')"; done | sed 's/ $//' | tr ' ' '/'))."
fi
exit "$status"

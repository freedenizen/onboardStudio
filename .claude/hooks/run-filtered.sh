#!/bin/bash
# Runs a Swift/Xcode build or test command, keeps the full log on disk, and prints only the
# parts worth spending context on. Exits with the command's real exit code.
#
# This project's unit tests use swift-testing (`import Testing`, `@Suite`), so the interesting
# lines are its "Test run with N tests …" / "✘ … recorded an issue" markers, NOT the XCTest
# harness's "Executed 0 tests" line, which is always present and always misleading here.
# The UITests target does use XCTest, so both vocabularies are matched.
#
# Invoked by .claude/hooks/filter-swift-output.sh, which only rewrites commands it has already
# checked for shell metacharacters. CC_BUILD_LOG_DIR picks the log directory.

set -u

cmd="$*"
dir="${CC_BUILD_LOG_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$dir" 2>/dev/null
log="$dir/build-$(date +%H%M%S)-$$.log"

# Subshell so an `exit` or `cd` in the command cannot escape into this script.
( eval "$cmd" ) >"$log" 2>&1
rc=$?

total=$(wc -l <"$log" | tr -d ' ')
emit() { head -c 8000; }

# Result lines worth seeing on success. "Executed [1-9]…" skips XCTest's always-zero line.
OK_RE='^\*\* (BUILD|TEST) SUCCEEDED \*\*|^Build complete|Test run with [0-9]+ tests?.*passed|Executed [1-9][0-9]* tests?,'
# Anything that indicates a real problem, in either test vocabulary.
BAD_RE='error:|^\*\* (BUILD|TEST) FAILED \*\*|Testing failed:|Failing tests:|✘|recorded an issue|Issue recorded|XCTAssert|Fatal error|Assertion failed|Test Case .* failed|Test run with [0-9]+ tests?.*failed'

if [ "$rc" -eq 0 ]; then
  echo "== OK (exit 0) — $total lines, full log: $log"
  grep -E "$OK_RE" "$log" | tail -6 | emit
  warn=$(grep -c 'warning:' "$log" | tr -d ' ')
  if [ "${warn:-0}" -gt 0 ]; then
    echo "-- $warn warning line(s), unique, first 15:"
    grep 'warning:' "$log" | sed 's|^.*/\([^/]*\.swift\)|\1|' | sort -u | head -15 | emit
  fi
else
  echo "== FAILED (exit $rc) — $total lines, full log: $log"
  echo "-- errors and failures:"
  grep -E "$BAD_RE" "$log" | sort -u | head -60 | emit
  # Only worth the tail when the log is long enough that the grep may have missed the summary.
  if [ "$total" -gt 40 ]; then
    echo "-- last 20 lines:"
    tail -20 "$log" | emit
  fi
  echo "-- grep the full log at $log for anything else."
fi

exit $rc

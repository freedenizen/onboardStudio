#!/bin/bash
# The local test loop.
#
#   Scripts/test.sh quick   # everything except the two-hour session and the fuzz suites
#   Scripts/test.sh full    # everything, as CI runs it
#
# `quick` skips by suite *name* — `swift test --skip` matches names, not swift-testing tags — so a
# slow suite must keep "LongSession" or "Fuzz" in its name to stay out of the quick loop.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-quick}" in
  quick) exec swift test --parallel --skip 'LongSessionTests|Fuzz' ;;
  full) exec swift test --parallel ;;
  *)
    echo "usage: $0 [quick|full]" >&2
    exit 2
    ;;
esac

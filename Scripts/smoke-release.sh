#!/usr/bin/env bash
# Runs the optimised build's own code on the paths a release is used for (#675). Every other test
# builds Debug, and #653 — the released app crashing whenever a folder already in the logbook was
# added again — showed only in an optimised build: two releases shipped with it.
#
#   Scripts/smoke-release.sh cli    the release-built `onboard` adds a day's folder to a logbook,
#                                   then adds it again
#   Scripts/smoke-release.sh app    one XCUITest class against a Release build of the app
#                                   (CLASS=TrackDayUITests by default: it adds a day, twice)
#
# The nightly runs both. `app` takes the screen, as every XCUITest run does.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "smoke-release: $*" >&2
  exit 1
}

cli() {
  swift build -c release --product onboard
  local bin logbook first second before after
  bin="$(swift build -c release --show-bin-path)/onboard"
  logbook=$(mktemp -d)
  # Expanded now: the variable is the function's own and is gone when the script exits.
  # shellcheck disable=SC2064
  trap "rm -rf '$logbook'" EXIT

  first=$("$bin" logbook add Tests/Fixtures --logbook "$logbook")
  before=$(find "$logbook" -name '*.onboardsession' | wc -l | tr -d ' ')
  [[ "$before" -gt 0 ]] || fail "the first import added no session:"$'\n'"$first"

  # The second time is the one that crashed: every file is in the logbook already.
  second=$("$bin" logbook add Tests/Fixtures --logbook "$logbook") || fail "adding the folder again failed"
  after=$(find "$logbook" -name '*.onboardsession' | wc -l | tr -d ' ')
  [[ "$after" == "$before" ]] || fail "adding the folder again changed $before sessions to $after"
  grep -q 'already in the logbook' <<< "$second" || fail "no session was said to be there already:"$'\n'"$second"
  # The clip's line is the lookup that read freed memory (#653).
  grep -q 'video already on the day' <<< "$second" || fail "no clip was said to be there already:"$'\n'"$second"
  echo "Release onboard: $before sessions added, and all of them known the second time"
}

app() {
  command -v xcodegen > /dev/null || fail "xcodegen is required (brew install xcodegen)"
  xcodegen generate --quiet
  local class=${CLASS:-TrackDayUITests} status=0
  export ONBOARD_TEST_EXPORT_DIR="${ONBOARD_TEST_EXPORT_DIR:-$(mktemp -d)}"
  rm -rf build/ReleaseSmoke.xcresult
  # One architecture: Release builds both by default, and the runner runs one.
  set +e
  caffeinate -dis xcodebuild test -project OnboardStudio.xcodeproj -scheme OnboardStudio \
    -configuration Release -destination 'platform=macOS' -derivedDataPath build/ReleaseSmoke \
    -only-testing:"OnboardStudioUITests/$class" -resultBundlePath build/ReleaseSmoke.xcresult \
    -retry-tests-on-failure -test-iterations 2 CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES 2>&1 \
    | grep --line-buffered -E "error:|Test Case|Executed|TEST |BUILD "
  status=${PIPESTATUS[0]}
  set -e
  git checkout -- Package.resolved 2> /dev/null || true
  [[ "$status" -eq 0 ]] || fail "$class failed against the Release build (build/ReleaseSmoke.xcresult)"
  echo "Release app: $class passed"
}

case "${1:-}" in
  cli) cli ;;
  app) app ;;
  *)
    echo "usage: $0 cli | app" >&2
    exit 2
    ;;
esac

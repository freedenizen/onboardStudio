#!/bin/bash
# Stops a UI test run whose runner's WindowServer has stopped answering (#588).
#
#   windowserver-watchdog.sh <marker-file>
#
# Runs beside xcodebuild. Every WATCHDOG_INTERVAL seconds it asks the WindowServer for the main
# display and the login session, the same connection an app makes before its first line of code.
# If two probes in a row get no answer within WATCHDOG_TIMEOUT seconds, it writes <marker-file>
# and stops xcodebuild, so the step fails in minutes and says why.
#
# The macOS 27 runner's paravirtualized GPU driver can deadlock WindowServer. From then on, every
# app launch blocks in NSApplication's init and the test fails with "does not have a process ID".
# The retry blocks the same way until the step's timeout, and nothing on that machine recovers.
# The rerun belongs on a fresh runner: .github/workflows/rerun-runner-hang.yml.
#
# WATCHDOG_PROBE and WATCHDOG_STOP replace the probe and the process to stop, for testing.
set -uo pipefail

marker=${1:?marker file}
interval=${WATCHDOG_INTERVAL:-30}
timeout=${WATCHDOG_TIMEOUT:-60}
stop=${WATCHDOG_STOP:-xcodebuild}
probe_script='ObjC.import("CoreGraphics");
var session = ObjC.castRefToObject($.CGSessionCopyCurrentDictionary());
"display " + $.CGMainDisplayID() + ", on console " + ObjC.unwrap(session.objectForKey("kCGSSessionOnConsoleKey"))'

probe() {
  if [ -n "${WATCHDOG_PROBE:-}" ]; then
    bash -c "$WATCHDOG_PROBE"
  else
    osascript -l JavaScript -e "$probe_script"
  fi
}

# Runs the probe in the background and waits up to $timeout seconds for it. Prints the probe's
# answer; returns 2 when there is none in time and 1 when the probe failed quickly. A quick
# failure is not a hang (a stuck WindowServer makes the probe wait, not fail), so only 2 counts.
answered() {
  local out pid waited=0
  out=$(mktemp)
  probe >"$out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      kill -9 "$pid" 2>/dev/null
      rm -f "$out"
      return 2
    fi
    sleep 1
    waited=$((waited + 1))
  done
  local status=0
  wait "$pid" || status=1
  cat "$out"
  rm -f "$out"
  return "$status"
}

# A first answer shows the probe reaches this session's WindowServer. Without one, the watchdog
# could not tell a hang from a probe that never worked, so it stands down rather than guess.
if ! first=$(answered); then
  echo "::warning title=WindowServer watchdog::The WindowServer probe failed before the tests started; the watchdog is off for this shard. ${first}"
  exit 0
fi
echo "WindowServer watchdog: ${first}; probing every ${interval} s"

missed=0
while sleep "$interval"; do
  answered >/dev/null
  if [ $? -ne 2 ]; then
    missed=0
    continue
  fi
  missed=$((missed + 1))
  echo "WindowServer watchdog: no answer in ${timeout} s (${missed} in a row)"
  if [ "$missed" -ge 2 ]; then
    date -u +%FT%TZ >"$marker"
    # TERM first, so xcodebuild can close the result bundle; it may itself be waiting on the
    # stuck test runner, so KILL if it is still there 20 s later.
    pkill -x "$stop"
    for _ in $(seq 20); do pgrep -x "$stop" >/dev/null || exit 0; sleep 1; done
    pkill -9 -x "$stop"
    exit 0
  fi
done

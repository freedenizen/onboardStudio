#!/bin/bash
# PreToolUse(Bash) hook: routes Onboard Studio build/test commands through run-filtered.sh so a
# failing build costs a few hundred tokens of context instead of ~8k of compiler chatter.
#
# Conservative by design — it only rewrites a command that starts with a known build/test
# invocation and contains no shell metacharacters, so semantics are unchanged. Anything else
# passes through untouched (exit 0, no decision).

set -u
input=$(cat)

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false')
scratch=$(printf '%s' "$input" | jq -r '.scratchpad_dir // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

[ -z "$cmd" ] && exit 0
[ "$bg" = "true" ] && exit 0                         # would break streaming output

# Already wrapped, or composed of several commands / pipes / redirections / substitutions.
case "$cmd" in
  *run-filtered.sh*) exit 0 ;;
  *'|'*|*'>'*|*'<'*|*'&'*|*';'*|*'$('*|*'`'*) exit 0 ;;
esac

# Only the slow, noisy commands.
case "$cmd" in
  "swift build"*|"swift test"*|"swift format"*|\
  "xcodebuild "*|"caffeinate "*xcodebuild*|\
  "swiftlint"*|\
  "Scripts/ui-tests.sh"*|"./Scripts/ui-tests.sh"*|\
  "Scripts/bundle-app.sh"*|"./Scripts/bundle-app.sh"*) ;;
  *) exit 0 ;;
esac

runner="${cwd:-.}/.claude/hooks/run-filtered.sh"
[ -x "$runner" ] || exit 0

logdir="${scratch:-${TMPDIR:-/tmp}}"

jq -n --arg c "CC_BUILD_LOG_DIR=$logdir $runner $cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { command: $c }
  }
}'

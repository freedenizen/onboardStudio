#!/bin/bash
# Keeps one open issue per kind of CI failure, so a red `main` or a red nightly is a ticket
# rather than a run nobody looked at.
#
#   report-ci-issue.sh open  <label> <title> <body>   # open the issue, or comment on the open one
#   report-ci-issue.sh close <label> <comment>        # close the open one, if any
#
# Deduplicates by label: while an issue carrying <label> is open, further failures are comments
# on it and a later success closes it. Needs GH_TOKEN with issues: write, and GH_REPO (or a
# checkout gh can read the remote from).
set -euo pipefail

mode=${1:?open|close}
label=${2:?label}

current() {
  gh issue list --label "$label" --state open --limit 1 --json number --jq '.[0].number // empty'
}

case "$mode" in
  open)
    title=${3:?title}
    body=${4:?body}
    if existing=$(current) && [ -n "$existing" ]; then
      gh issue comment "$existing" --body "$body"
      echo "commented on #$existing"
    else
      gh issue create --label "$label" --title "$title" --body "$body"
    fi
    ;;
  close)
    comment=${3:?comment}
    if existing=$(current) && [ -n "$existing" ]; then
      gh issue close "$existing" --comment "$comment"
      echo "closed #$existing"
    else
      echo "nothing open with label $label"
    fi
    ;;
  *)
    echo "usage: $0 open <label> <title> <body> | close <label> <comment>" >&2
    exit 2
    ;;
esac

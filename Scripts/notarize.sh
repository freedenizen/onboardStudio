#!/usr/bin/env bash
# Notarizes and staples a DMG. Requires NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY_PATH (.p8).
# Submits, reports the submission id immediately, waits up to NOTARY_TIMEOUT (default 90m),
# then prints Apple's notary log on anything other than Accepted.
set -euo pipefail
DMG="$1"
AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
TIMEOUT="${NOTARY_TIMEOUT:-90m}"

SUBMIT=$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --output-format json)
ID=$(echo "$SUBMIT" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null || true)
[[ -n "$ID" ]] || { echo "::error::notarytool submit returned no submission id: $SUBMIT"; exit 1; }
echo "Submitted $(basename "$DMG") as $ID at $(date -u +%H:%M:%SZ); waiting up to $TIMEOUT for Apple…"

xcrun notarytool wait "$ID" "${AUTH[@]}" --timeout "$TIMEOUT" || true
INFO=$(xcrun notarytool info "$ID" "${AUTH[@]}" --output-format json)
STATUS=$(echo "$INFO" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || echo "unknown")
echo "Submission $ID status: $STATUS at $(date -u +%H:%M:%SZ)"

if [[ "$STATUS" != "Accepted" ]]; then
  echo "::group::Notary log"
  xcrun notarytool log "$ID" "${AUTH[@]}" || true
  echo "::endgroup::"
  echo "::error::Notarization was not accepted (status: $STATUS). See the notary log above."
  exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

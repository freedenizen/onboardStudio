#!/usr/bin/env bash
# Notarizes and staples a DMG. Requires NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY_PATH (.p8).
# On rejection, prints Apple's notary log (the actual reasons) and fails.
set -euo pipefail
DMG="$1"
AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
RESULT=$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --output-format json)
ID=$(echo "$RESULT" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null || echo "$RESULT" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)
STATUS=$(echo "$RESULT" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || echo "$RESULT" | sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p' | head -1)
echo "notarization submission $ID: $STATUS"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "::group::Notary log"
  xcrun notarytool log "$ID" "${AUTH[@]}" || true
  echo "::endgroup::"
  echo "::error::Notarization was not accepted (status: $STATUS). See the notary log above."
  exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

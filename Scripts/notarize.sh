#!/usr/bin/env bash
# Notarizes and staples a DMG. Requires NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY_PATH (.p8).
set -euo pipefail
DMG="$1"
xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$DMG"

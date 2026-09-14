#!/usr/bin/env bash
# Signs the DMG(s) in dist/ with the Sparkle EdDSA key and writes dist/appcast.xml.
# Requires SPARKLE_PRIVATE_KEY (base64 or raw key from generate_keys -x) or the key in the login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=$(find build/DerivedData/SourcePackages/artifacts .build/artifacts -type d -path '*Sparkle/bin' 2>/dev/null | head -1)
[[ -n "$BIN" ]] || BIN=$(find ~/Library/Developer/Xcode/DerivedData -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)
[[ -n "$BIN" ]] || { echo "Sparkle tools not found; run 'swift package resolve' or an Xcode build first" >&2; exit 1; }
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/freedenizen/overlayGen/releases/download/v$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OverlayGen.app/Contents/Info.plist)/}"
ARGS=(--download-url-prefix "$DOWNLOAD_PREFIX" -o dist/appcast.xml)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  KEYFILE=$(mktemp); echo -n "$SPARKLE_PRIVATE_KEY" > "$KEYFILE"; ARGS+=(--ed-key-file "$KEYFILE")
fi
"$BIN/generate_appcast" "${ARGS[@]}" dist/
echo "Wrote dist/appcast.xml"

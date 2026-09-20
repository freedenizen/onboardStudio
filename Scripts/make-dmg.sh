#!/usr/bin/env bash
# Packages dist/OnboardStudio.app into dist/OnboardStudio-<version>.dmg (requires create-dmg).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/OnboardStudio.app
[[ -d "$APP" ]] || { echo "Run Scripts/bundle-app.sh first" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="dist/OnboardStudio-$VERSION.dmg"
rm -f "$OUT"
command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
create-dmg \
  --volname "Onboard Studio $VERSION" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "OnboardStudio.app" 140 180 \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "$OUT" "$APP"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --sign "$SIGNING_IDENTITY" --timestamp "$OUT"
fi
echo "Built $OUT"

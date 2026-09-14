#!/usr/bin/env bash
# Builds dist/OverlayGen.app via the XcodeGen project (requires Xcode + xcodegen).
# Signs with Developer ID if SIGNING_IDENTITY is set, otherwise ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST=dist
rm -rf "$DIST" build
mkdir -p "$DIST"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] && SIGN_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

xcodebuild -project OverlayGen.xcodeproj -scheme OverlayGen -configuration Release \
  -derivedDataPath build/DerivedData -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${SIGN_ARGS[@]}" \
  build | grep -E '^(error|warning: .*unresolved|\*\* BUILD)' || true

APP=$(find build/DerivedData/Build/Products/Release -maxdepth 1 -name 'OverlayGen.app' | head -1)
[[ -d "$APP" ]] || { echo "Build failed: OverlayGen.app not found" >&2; exit 1; }
cp -R "$APP" "$DIST/OverlayGen.app"
codesign --verify --deep --strict "$DIST/OverlayGen.app"
echo "Built $DIST/OverlayGen.app ($VERSION build $BUILD_NUMBER)"

#!/usr/bin/env bash
# Local end-to-end release: app bundle -> DMG -> (notarize) -> appcast -> the `onboard` archive.
# Mirrors .github/workflows/release.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle-app.sh
if [[ -n "${NOTARY_KEY_ID:-}" ]]; then Scripts/notarize.sh dist/OnboardStudio.app; fi
Scripts/make-dmg.sh
if [[ -n "${NOTARY_KEY_ID:-}" ]]; then Scripts/notarize.sh dist/OnboardStudio-*.dmg; fi
Scripts/make-appcast.sh
# Signed when SIGNING_IDENTITY is set and notarized when the notary's key is as well (#683).
Scripts/make-cli-archive.sh "v${VERSION:-$(git describe --tags --abbrev=0 | sed 's/^v//')}"
ls -la dist/

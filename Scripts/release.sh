#!/usr/bin/env bash
# Local end-to-end release: app bundle -> DMG -> (notarize) -> appcast. Mirrors .github/workflows/release.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle-app.sh
Scripts/make-dmg.sh
if [[ -n "${NOTARY_KEY_ID:-}" ]]; then Scripts/notarize.sh dist/OverlayGen-*.dmg; fi
Scripts/make-appcast.sh
ls -la dist/

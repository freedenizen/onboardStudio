#!/bin/bash
# Runs the XCUITest suite against the app: Scripts/ui-tests.sh [TestClass[/testMethod]]
# The app is launched with the Testing menu enabled and exports go to a temporary directory.
set -euo pipefail
cd "$(dirname "$0")/.."

only="OnboardStudioUITests${1:+/$1}"
export_dir="$(mktemp -d "${TMPDIR:-/tmp}/onboard-uitests.XXXXXX")"
result="build/UITests.xcresult"
rm -rf "$result"

command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

echo "Exports: $export_dir"
set +e
ONBOARD_TEST_EXPORT_DIR="$export_dir" caffeinate -dis xcodebuild test \
  -project OnboardStudio.xcodeproj -scheme OnboardStudio -destination 'platform=macOS' \
  -only-testing:"$only" -derivedDataPath build/DerivedData -resultBundlePath "$result" \
  CODE_SIGN_IDENTITY="-" 2>&1 | grep -E "error:|Test Case|Executed|TEST |warning: .*UITests"
status=${PIPESTATUS[0]}
set -e
git checkout -- Package.resolved 2>/dev/null || true
exit "$status"

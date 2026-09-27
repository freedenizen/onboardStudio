#!/bin/bash
# Takes the documentation screenshots (#304) from the real app into docs/images/.
#
#   TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT=/path/to/Project.onboardproj \
#   TEST_RUNNER_ONBOARD_SCREENSHOT_TIME=687 Scripts/screenshots.sh
#
# The project is opened, laid out with the Cockpit with Graph template and shown at the given
# project time (seconds); it is never saved. Only publish screenshots of footage you may publish.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT:?Set TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT to a project}"
export TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT TEST_RUNNER_ONBOARD_SCREENSHOT_TIME
width="${SCREENSHOT_WIDTH:-1600}"
result="build/Screenshots.xcresult"
attachments="$(mktemp -d "${TMPDIR:-/tmp}/onboard-screenshots.XXXXXX")"
rm -rf "$result"

command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet
set +e
caffeinate -dis xcodebuild test \
  -project OnboardStudio.xcodeproj -scheme OnboardStudio -destination 'platform=macOS' \
  -only-testing:OnboardStudioUITests/DocumentationScreenshots -derivedDataPath build/DerivedData \
  -resultBundlePath "$result" CODE_SIGN_IDENTITY="-" 2>&1 | grep -E "error:|Test Case|skipped|TEST "
status=${PIPESTATUS[0]}
set -e
git checkout -- Package.resolved 2>/dev/null || true
[[ $status -eq 0 ]] || exit "$status"

xcrun xcresulttool export attachments --path "$result" --output-path "$attachments" >/dev/null
mkdir -p docs/images
# The manifest maps each exported file to the name the test gave it.
python3 - "$attachments" "$width" <<'EOF'
import json, subprocess, sys, pathlib
folder, width = pathlib.Path(sys.argv[1]), sys.argv[2]
for test in json.loads((folder / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment["suggestedHumanReadableName"].split("_0_")[0].removesuffix(".png")
        if name.startswith(("App UI hierarchy", "UI Snapshot", "Debug description")):
            continue
        # Windows without footage stay PNG; the ones showing video are a quarter the size as JPEG.
        flat = name in {"welcome", "attributes"}
        target = pathlib.Path("docs/images") / f"{name}.{'png' if flat else 'jpg'}"
        options = [] if flat else ["-s", "format", "jpeg", "-s", "formatOptions", "85"]
        subprocess.run(
            ["sips", "--resampleWidth", width, *options, str(folder / attachment["exportedFileName"]),
             "--out", str(target)],
            check=True, capture_output=True)
        print(target)
EOF

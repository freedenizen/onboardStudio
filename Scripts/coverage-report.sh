#!/usr/bin/env bash
# Writes the coverage of the last `swift test --enable-code-coverage` to coverage.txt (per file,
# the total on its last line) and coverage.lcov, in the current directory. CI runs it on the push
# to main.
#
# Swift 6.3 linked every test target into one OnboardStudioPackageTests.xctest; Swift 6.4 builds
# an .xctest per target, and looking for the one bundle found nothing (#510). llvm-cov is given
# every bundle in the build's products: the first as the binary, the rest as `-object`.
set -euo pipefail

products=$(swift build --show-bin-path)
codecov=$(swift test --show-codecov-path)
profdata="$(dirname "$codecov")/default.profdata"
[ -f "$profdata" ] || {
  echo "No $profdata: run swift test --enable-code-coverage first" >&2
  exit 1
}

objects=()
while IFS= read -r bundle; do
  binary="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
  [ -x "$binary" ] || continue
  if [ ${#objects[@]} -eq 0 ]; then objects+=("$binary"); else objects+=(-object "$binary"); fi
done < <(find "$products" -maxdepth 1 -name '*.xctest' -type d | sort)
[ ${#objects[@]} -gt 0 ] || {
  echo "No test bundles in $products" >&2
  exit 1
}

ignore='(\.build|Tests)/'
xcrun llvm-cov report "${objects[@]}" -instr-profile "$profdata" -ignore-filename-regex="$ignore" | tee coverage.txt
xcrun llvm-cov export "${objects[@]}" -instr-profile "$profdata" -format=lcov -ignore-filename-regex="$ignore" \
  > coverage.lcov

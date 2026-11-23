#!/usr/bin/env bash
# Packs the `onboard` command-line tool as a release publishes it, and proves the archive works:
#
#   Scripts/make-cli-archive.sh <name>      # → dist/onboard-cli-<name>-macos.tar.gz
#
# The archive holds one folder, `onboard-cli-<name>-macos`, with `onboard` and the resource bundles
# SwiftPM builds beside it. `onboard` finds them next to itself, so the folder stays together; a
# symbolic link to `onboard` from a folder on the PATH works.
#
# The release used to pack `onboard` alone (#662). It then stopped at the first thing it read from
# a bundle — the circuit catalogue, so on every file — and two releases shipped it that way,
# because nothing ran the archive. So this script unpacks what it made somewhere else and runs it,
# and the nightly runs this script.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=${1:?usage: Scripts/make-cli-archive.sh <name, such as v1.2.3>}
FOLDER="onboard-cli-$NAME-macos"
OUT="dist/$FOLDER.tar.gz"

swift build -c release --product onboard
BUILT=$(swift build -c release --show-bin-path)

STAGE=$(mktemp -d)
CHECK=$(mktemp -d)
trap 'rm -rf "$STAGE" "$CHECK"' EXIT
mkdir "$STAGE/$FOLDER"
cp "$BUILT/onboard" "$STAGE/$FOLDER/"

# Every bundle the tool names is packed, and a bundle it names that was not built stops the
# release: a target that gains resources is then in the archive without anyone remembering it.
bundles=$(strings -a "$BUILT/onboard" | grep -o 'OnboardStudio_[A-Za-z0-9]*' | sort -u)
[[ -n "$bundles" ]] || { echo "onboard names no resource bundle: has the package been renamed?" >&2; exit 1; }
for bundle in $bundles; do
  [[ -d "$BUILT/$bundle.bundle" ]] || { echo "onboard reads $bundle.bundle, which was not built" >&2; exit 1; }
  cp -R "$BUILT/$bundle.bundle" "$STAGE/$FOLDER/"
done

mkdir -p dist
rm -f "$OUT"
tar -C "$STAGE" -czf "$OUT" "$FOLDER"

# What someone who downloaded it does: unpack it away from the build, and read a file.
tar -C "$CHECK" -xzf "$OUT"
"$CHECK/$FOLDER/onboard" --version
probed=$("$CHECK/$FOLDER/onboard" probe "$PWD/Tests/Fixtures/coaching-laps.csv")
grep -q '^Format:' <<< "$probed" || { echo "the packed onboard did not read the fixture:" >&2; echo "$probed" >&2; exit 1; }
# Through a link from another folder, as it is put on the PATH.
mkdir "$CHECK/bin"
ln -s "$CHECK/$FOLDER/onboard" "$CHECK/bin/onboard"
"$CHECK/bin/onboard" probe "$PWD/Tests/Fixtures/coaching-laps.csv" > /dev/null

echo "Built $OUT ($(echo "$bundles" | wc -l | tr -d ' ') resource bundles), and read a file with it"

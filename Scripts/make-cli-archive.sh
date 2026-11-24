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
#
# With SIGNING_IDENTITY set (a Developer ID Application identity, as for Scripts/bundle-app.sh),
# `onboard` is signed with it and the hardened runtime; with NOTARY_KEY_ID, NOTARY_ISSUER_ID and
# NOTARY_KEY_PATH set as well, it is notarized before it is packed. Without them it carries only
# the linker's ad-hoc signature, which Gatekeeper refuses on a downloaded copy: an archive fetched
# with a browser hands its quarantine to what `tar` unpacks from it, and two releases shipped a
# tool that would have been stopped at its first run (#683). The nightly and a fork have no
# identity and pack it unsigned; the checks below still run.
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

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  # The hardened runtime and a secure timestamp are what notarization asks of every binary. The
  # resource bundles hold no code, so there is nothing in them to sign.
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$STAGE/$FOLDER/onboard"
  codesign --verify --strict --verbose=2 "$STAGE/$FOLDER/onboard"
  signed=$(codesign -dvv "$STAGE/$FOLDER/onboard" 2>&1)
  grep -q '^Authority=Developer ID Application' <<< "$signed" \
    || { echo "onboard is not signed with a Developer ID Application identity:" >&2; echo "$signed" >&2; exit 1; }
  grep -Eq 'flags=0x[0-9a-f]+\(.*runtime' <<< "$signed" \
    || { echo "onboard was signed without the hardened runtime:" >&2; echo "$signed" >&2; exit 1; }
  if [[ -n "${NOTARY_KEY_ID:-}" ]]; then
    # Apple's notary takes a zip, not a tar. What it approves is the signed binary, whichever
    # archive later carries it; and a bare tool has nowhere to staple the ticket, so Gatekeeper
    # asks Apple for it the first time the tool is run.
    ditto -c -k --keepParent "$STAGE/$FOLDER" "$CHECK/$FOLDER.zip"
    Scripts/notarize.sh "$CHECK/$FOLDER.zip"
    rm "$CHECK/$FOLDER.zip"
    # For whoever reads the first release's log: what Gatekeeper makes of it. Not a check,
    # because the notary's "Accepted" above already was.
    spctl --assess --type execute -vv "$STAGE/$FOLDER/onboard" || true
  else
    echo "Signed, not notarized: NOTARY_KEY_ID is not set"
  fi
else
  echo "Not signed: SIGNING_IDENTITY is not set, so onboard keeps the linker's ad-hoc signature"
fi

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
# The signature survived the packing: a tool signed above and unsigned here would be published
# looking signed in this log.
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --verify --strict "$CHECK/$FOLDER/onboard"
fi

echo "Built $OUT ($(echo "$bundles" | wc -l | tr -d ' ') resource bundles), and read a file with it"

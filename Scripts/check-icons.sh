#!/bin/bash
# Checks the icon assets are complete and correctly sized.
#
# Deliberately structural rather than a byte-exact re-render diff: SVG rasterisation can shift
# between macOS releases, so comparing bytes against a freshly generated set would fail the
# moment GitHub bumps the runner image, for no real fault.
set -euo pipefail
cd "$(dirname "$0")/.."

set_dir="App/Assets.xcassets/AppIcon.appiconset"
contents="$set_dir/Contents.json"
status=0

fail() {
  echo "error: $1" >&2
  status=1
}

for source in Design/AppIcon.svg Design/AppIcon-small.svg Design/DocumentIcon.svg; do
  [ -f "$source" ] || fail "missing vector source $source"
done

count=$(/usr/bin/plutil -extract images raw -o - "$contents")
[ "$count" = "10" ] || fail "$contents lists $count images, expected the 10 macOS slots"

for i in $(seq 0 $((count - 1))); do
  size=$(/usr/bin/plutil -extract "images.$i.size" raw -o - "$contents")
  scale=$(/usr/bin/plutil -extract "images.$i.scale" raw -o - "$contents")
  name=$(/usr/bin/plutil -extract "images.$i.filename" raw -o - "$contents" 2>/dev/null || true)

  if [ -z "$name" ]; then
    fail "slot $size@$scale has no filename — run Scripts/make-icons.sh"
    continue
  fi
  if [ ! -f "$set_dir/$name" ]; then
    fail "slot $size@$scale points at missing $name"
    continue
  fi

  points=${size%%x*}
  expected=$((points * ${scale%x}))
  actual=$(/usr/bin/sips -g pixelWidth "$set_dir/$name" | awk '/pixelWidth/ {print $2}')
  [ "$actual" = "$expected" ] || fail "$name is ${actual}px, expected ${expected}px"
done

[ -f App/DocumentIcon.icns ] || fail "missing App/DocumentIcon.icns — run Scripts/make-icons.sh"
grep -q "CFBundleTypeIconFile: DocumentIcon" project.yml ||
  fail "project.yml no longer points the .onboardproj document type at DocumentIcon"

if [ "$status" -eq 0 ]; then
  echo "Icons OK: 10 app icon slots, document icon present and wired up."
fi
exit "$status"

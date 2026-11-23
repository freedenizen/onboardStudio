#!/usr/bin/env bash
# The copy of a release that the new-user review drives (docs/new-user-review.md). It has its own
# bundle identifier, so its preferences start empty, and its own home folder, so its Logbook, track
# library and templates do: the app behaves as it does for someone who has never run it, and the
# real app's settings and logbook are neither read nor written.
#
#   Scripts/review-copy.sh make   <version> <OnboardStudio.app | OnboardStudio-x.y.z.dmg>
#   Scripts/review-copy.sh stage  <version> <folder>...   # the data, as APFS clones: no bytes copied
#   Scripts/review-copy.sh launch <version>
#   Scripts/review-copy.sh info   <version>               # where things are; window frames in points
#   Scripts/review-copy.sh clean  <version>               # the copy, its home, its clones; notes stay
#
# Everything lives in $ONBOARD_REVIEW_DIR/v<version> (default ~/OnboardStudioReview), outside the
# checkout: Scripts/bundle-app.sh empties build/, and a worktree does not outlive its session.
# Compatible with the bash 3.2 that ships with macOS.
set -euo pipefail

REVIEW_ID=com.freedenizen.onboardstudio.review
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

[[ $# -ge 2 ]] || usage
command=$1
version=${2#v}
shift 2
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a version: $version (want 0.37.0)" >&2; exit 64; }

base=${ONBOARD_REVIEW_DIR:-$HOME/OnboardStudioReview}
root="$base/v$version"
app="$root/OnboardStudio.app"
home="$root/home"
data="$root/Track Days"

running() { pgrep -f "$app/Contents/MacOS/" >/dev/null 2>&1; }

make_copy() {
  [[ $# -eq 1 ]] || usage
  local source=$1 mount=""
  [[ -e "$source" ]] || { echo "No such file: $source" >&2; exit 66; }
  [[ ! -e "$app" ]] || { echo "$app exists already: Scripts/review-copy.sh clean $version first" >&2; exit 73; }
  mkdir -p "$root" "$home"

  if [[ "$source" == *.dmg ]]; then
    # What Gatekeeper makes of the download is the first thing a new user meets, and it can only
    # be asked of the file as published — before anything below changes the app inside it.
    {
      echo "## $(basename "$source")"
      spctl --assess --type open --context context:primary-signature --verbose=2 "$source" 2>&1 || true
      xcrun stapler validate "$source" 2>&1 || true
    } > "$root/install-check.txt"
    mount=$(mktemp -d)
    hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mount" "$source"
    source=$(find "$mount" -maxdepth 1 -name '*.app' | head -1)
    if [[ -z "$source" ]]; then
      hdiutil detach -quiet "$mount"
      echo "No app in the disk image" >&2
      exit 65
    fi
    {
      echo "## $(basename "$source")"
      spctl --assess --type execute --verbose=2 "$source" 2>&1 || true
      xcrun stapler validate "$source" 2>&1 || true
    } >> "$root/install-check.txt"
  fi

  ditto "$source" "$app"
  if [[ -n "$mount" ]]; then
    hdiutil detach -quiet "$mount"
    rmdir "$mount" 2>/dev/null || true
  fi

  # The entitlements have to be read before the identifier changes: that edit breaks the seal.
  local entitlements="$root/entitlements.plist" sign=(codesign --force --sign -)
  codesign -d --entitlements - --xml "$app" > "$entitlements" 2>/dev/null || true
  [[ -s "$entitlements" ]] && sign+=(--entitlements "$entitlements")
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $REVIEW_ID" "$app/Contents/Info.plist"
  # Ad hoc and without the hardened runtime, so the frameworks inside keep the signatures they
  # shipped with and still load.
  "${sign[@]}" "$app" 2>&1 | grep -v 'replacing existing signature' || true
  codesign --verify --strict "$app"

  local short
  short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
  [[ "$short" == "$version" ]] || echo "warning: the app says it is $short, not $version" >&2
  echo "Review copy of $short at $app"
  [[ ! -f "$root/install-check.txt" ]] || { echo "Gatekeeper on the download:"; sed 's/^/  /' "$root/install-check.txt"; }
}

stage_data() {
  [[ $# -ge 1 ]] || usage
  mkdir -p "$data"
  local folder name device
  for folder in "$@"; do
    [[ -d "$folder" ]] || { echo "Not a folder: $folder" >&2; exit 66; }
    name=$(basename "$folder")
    [[ ! -e "$data/$name" ]] || { echo "Already staged: $name" >&2; continue; }
    # cp -c quietly copies in full when it cannot clone, and a day of video is tens of gigabytes.
    device=$(df "$data" | awk 'NR == 2 { print $1 }')
    if [[ "$(stat -f %d "$folder")" != "$(stat -f %d "$data")" ]] || ! mount | grep -q "^$device on .*(apfs"; then
      echo "$folder is not on the same APFS volume as $data, so it cannot be cloned." >&2
      echo "Set ONBOARD_REVIEW_DIR to a folder on the volume the data is on." >&2
      exit 73
    fi
    cp -Rc "$folder" "$data/$name"
    echo "Staged $name ($(find "$data/$name" -type f ! -name .DS_Store | wc -l | tr -d ' ') files)"
  done
}

launch() {
  [[ -d "$app" ]] || { echo "No review copy: Scripts/review-copy.sh make $version <app or dmg>" >&2; exit 66; }
  # -didMigrateFromOverlayGen stops LegacyMigration copying the real settings of the app's former
  # name into the empty preferences. No -uiTesting: the real panels, tour and menus are the point.
  open -n "$app" --env "CFFIXED_USER_HOME=$home" --args -didMigrateFromOverlayGen YES
  echo "Launched $REVIEW_ID with its home at $home"
}

info() {
  echo "Review folder   $root"
  echo "App             $app$([[ -d "$app" ]] || echo ' (not made)')"
  echo "Home            $home"
  echo "Data            $data"
  echo "Preferences     $REVIEW_ID"
  echo "Running         $(running && echo yes || echo no)"
  # Window sizes for a finding come from here, in points, never from the pixels of a screenshot.
  defaults read "$REVIEW_ID" 2>/dev/null | grep 'NSWindow Frame' || echo "No saved window frames yet"
}

clean() {
  if running; then
    osascript -e "tell application id \"$REVIEW_ID\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      running || break
      sleep 1
    done
    ! running || { echo "The review copy is still running: quit it, then clean again" >&2; exit 75; }
  fi
  # The copy exports the project file types; left registered, a stale path can claim them.
  [[ ! -d "$app" ]] || "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
  defaults delete "$REVIEW_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Preferences/$REVIEW_ID.plist" \
    "$HOME/Library/Saved Application State/$REVIEW_ID.savedState" \
    "$HOME/Library/Caches/$REVIEW_ID" \
    "$HOME/Library/HTTPStorages/$REVIEW_ID"
  rm -rf "$app" "$home" "$data" "$root/entitlements.plist"
  echo "Removed the review copy, its home and the staged data. What is left in $root:"
  ls -1 "$root" 2>/dev/null || true
}

case "$command" in
  make) make_copy "$@" ;;
  stage) stage_data "$@" ;;
  launch) launch ;;
  info) info ;;
  clean) clean ;;
  *) usage ;;
esac

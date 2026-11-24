#!/bin/bash
# Checks for Scripts/make-help-book.py, run against the real user guide: builds the Help Book into
# a temporary directory and looks for the faults a reader would meet in Help Viewer: a missing
# page, a link or image that goes nowhere, Markdown that was never converted, a bad Info.plist,
# a missing search index. Also checks that a broken link in the guide fails the build.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$scripts")
guide="$repo/docs/user-guide.md"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | head -n 15 | sed 's/^/        /'
  failures=$((failures + 1))
}
# check <name> <problems>: passes when <problems> is empty.
check() {
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "$2"; fi
}

out="$work/out"
bundle="$out/OnboardStudio.help"
lproj="$bundle/Contents/Resources/en.lproj"

# 1. The generator runs and the bundle has its basic parts.
status=0
log=$("$scripts/make-help-book.py" --out "$out" --version 9.8.7 2>&1) || status=$?
if [ "$status" -ne 0 ]; then
  fail "the generator exits 0" "$log"
  echo "$failures failed" >&2
  exit 1
fi
missing=""
for f in "$bundle/Contents/Info.plist" "$lproj/index.html" "$lproj/style.css"; do
  [ -s "$f" ] || missing="$missing missing or empty: ${f#"$out"/}"$'\n'
done
check "the generator exits 0 and writes Info.plist, index.html and style.css" "$missing"

# 2. One page per `## ` heading (headings inside fenced code do not count).
want=$(awk '/^```/ { fence = !fence } !fence && /^## / { n++ } END { print n + 0 }' "$guide")
have=$(find "$lproj" -maxdepth 1 -name '*.html' ! -name index.html | wc -l | tr -d ' ')
if [ "$want" = "$have" ] && [ "$want" -gt 0 ]; then
  pass "one page per section ($have pages for $want '## ' headings)"
else
  fail "one page per section" "the guide has $want '## ' headings, the bundle has $have section pages"
fi

# 3 to 6 share a python helper that reads the generated pages.
pycheck() {
  python3 -I - "$lproj" "$guide" "$1" <<'PY'
import os, re, sys, urllib.parse

lproj, guide, which = sys.argv[1], sys.argv[2], sys.argv[3]
pages = {f: open(os.path.join(lproj, f), encoding="utf-8").read() for f in os.listdir(lproj) if f.endswith(".html")}
names = {f: set(re.findall(r'<a name="([^"]+)"></a>', t)) for f, t in pages.items()}
problems = []

def strip_code(t):
    t = re.sub(r"<pre\b.*?</pre>", "", t, flags=re.S)
    return re.sub(r"<code\b.*?</code>", "", t, flags=re.S)

if which == "anchors":
    # every (#anchor) in the guide, outside fenced code, exists as <a name> somewhere
    fence = False
    all_names = set().union(*names.values())
    for no, line in enumerate(open(guide, encoding="utf-8"), 1):
        if line.startswith("```"):
            fence = not fence
        if fence:
            continue
        for a in re.findall(r"\]\(#([^)\s]+)\)", line):
            if a not in all_names:
                problems.append("line %d: (#%s) has no <a name>" % (no, a))
elif which == "hrefs":
    for f, t in pages.items():
        for h in re.findall(r'<a href="([^"]*)"', t):
            h = h.replace("&amp;", "&")
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", h):
                continue
            path, _, frag = h.partition("#")
            path = urllib.parse.unquote(path) or f
            frag = urllib.parse.unquote(frag)
            if not path.endswith(".html"):
                problems.append("%s: href %r is not a local page" % (f, h))
            elif path not in pages:
                problems.append("%s: href %r: no such page" % (f, h))
            elif frag and frag not in names[path]:
                problems.append("%s: href %r: no such anchor in %s" % (f, h, path))
elif which == "images":
    for f, t in pages.items():
        for s in re.findall(r'<img src="([^"]*)"', t):
            if not os.path.isfile(os.path.join(lproj, urllib.parse.unquote(s))):
                problems.append("%s: image %r is not in the bundle" % (f, s))
elif which == "markdown":
    for f, t in pages.items():
        for no, line in enumerate(strip_code(t).split("\n"), 1):
            if "**" in line:
                problems.append("%s:%d: '**' left over: %s" % (f, no, line[:100]))
            if "](" in line:
                problems.append("%s:%d: '](' left over: %s" % (f, no, line[:100]))
            if re.match(r"^#+ ", line.strip()):
                problems.append("%s:%d: heading marker left over: %s" % (f, no, line[:100]))
            if "```" in line:
                problems.append("%s:%d: code fence left over: %s" % (f, no, line[:100]))
print("\n".join(problems))
PY
}

check "every (#anchor) link in the guide exists as an <a name> in some page" "$(pycheck anchors)"
check "every local href in the pages points at a file and anchor that exist" "$(pycheck hrefs)"
check "every <img src> points at a file in the bundle" "$(pycheck images)"
check "no raw Markdown is left in the pages" "$(pycheck markdown)"

# 7. Info.plist has the keys the brief lists.
plist="$bundle/Contents/Info.plist"
problems=$(python3 -I - "$plist" <<'PY'
import plistlib, sys
want = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleIdentifier": "com.freedenizen.onboardstudio.help",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Onboard Studio Help",
    "CFBundlePackageType": "BNDL",
    "CFBundleShortVersionString": "9.8.7",
    "CFBundleVersion": "9.8.7",
    "CFBundleSignature": "hbwr",
    "HPDBookAccessPath": "index.html",
    "HPDBookIndexPath": "search.helpindex",
    "HPDBookCSIndexPath": "search.cshelpindex",
    "HPDBookTitle": "Onboard Studio Help",
    "HPDBookType": "3",
}
with open(sys.argv[1], "rb") as f:
    got = plistlib.load(f)
for k, v in want.items():
    if got.get(k) != v:
        print("%s: wanted %r, got %r" % (k, v, got.get(k)))
PY
)
if command -v plutil >/dev/null 2>&1; then
  lint=$(plutil -lint "$plist" 2>&1) || problems="$problems"$'\n'"plutil -lint: $lint"
  for key in CFBundleIdentifier HPDBookType HPDBookAccessPath; do
    plutil -extract "$key" raw -o - "$plist" >/dev/null 2>&1 || problems="$problems"$'\n'"plutil cannot read $key"
  done
fi
check "Info.plist is valid and has the keys" "$(printf '%s' "$problems" | sed '/^$/d')"

# 8. The search indexes, where hiutil exists.
if command -v hiutil >/dev/null 2>&1; then
  problems=""
  for f in search.helpindex search.cshelpindex; do
    [ -s "$lproj/$f" ] || problems="$problems$f is missing or empty"$'\n'
  done
  check "both search indexes exist and are not empty" "$problems"
else
  pass "both search indexes exist and are not empty (skipped: no hiutil)"
fi

# 9. A broken link in the source fails the build.
cat >"$work/broken.md" <<'EOF'
# A guide

Intro text.

## First

See [nowhere](#no-such-heading) for details.
EOF
if broken=$("$scripts/make-help-book.py" --source "$work/broken.md" --out "$work/broken-out" 2>&1); then
  fail "a link to a missing heading fails the build" "the generator exited 0"
elif printf '%s' "$broken" | grep -q 'no-such-heading'; then
  pass "a link to a missing heading fails the build, naming the link"
else
  fail "a link to a missing heading fails the build, naming the link" "$broken"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "all passed"

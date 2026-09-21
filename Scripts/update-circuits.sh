#!/bin/bash
# Refreshes Sources/TelemetryKit/Resources/circuits.csv from Wikidata.
#
# The list is every item that is a motorsport racing track (Q2338524) or a subclass of one, with a
# coordinate. Wikidata is CC0, so the file carries no attribution obligation and no share-alike —
# which is the whole reason it was chosen over OpenStreetMap. See docs/tracks-and-sectors.md.
#
# Labels fall back through several languages before giving up: asking only for English drops ~130
# circuits to a bare "Q12345", which is worse than a native name nobody on this machine can read.
#
# Run it rarely and review the diff: circuits close and get renamed, and a bad refresh would
# silently stop identifying somebody's home track.
set -euo pipefail
cd "$(dirname "$0")/.."

out="Sources/TelemetryKit/Resources/circuits.csv"
agent="OnboardStudio/circuit-list (https://github.com/freedenizen/onboardStudio)"
query='SELECT ?item ?itemLabel ?lat ?lon ?countryCode WHERE {
  ?item wdt:P31/wdt:P279* wd:Q2338524 .
  ?item p:P625 ?coordStatement .
  ?coordStatement psv:P625 ?coordNode .
  ?coordNode wikibase:geoLatitude ?lat ; wikibase:geoLongitude ?lon .
  OPTIONAL { ?item wdt:P17 ?country . ?country wdt:P297 ?countryCode . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,ja,ru,zh,de,fr,es,it,pt,nl,pl,sv,fi,cs,hu,tr,ko,ar,mul". }
}'

raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT
echo "Querying Wikidata…"
curl -sS -G https://query.wikidata.org/sparql \
  --data-urlencode "query=$query" -H "Accept: text/csv" -H "User-Agent: $agent" \
  --max-time 180 -o "$raw"

python3 - "$raw" "$out" <<'PY'
import csv, os, re, sys

source, destination = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(source)))
if len(rows) < 800:
    raise SystemExit(f"Only {len(rows)} rows came back; refusing to overwrite the list.")

kept, unnamed = {}, 0
for row in rows:
    qid = row["item"].rsplit("/", 1)[-1]
    name = row["itemLabel"].strip()
    if re.fullmatch(r"Q\d+", name):          # no label in any language we asked for
        unnamed += 1
        continue
    try:
        lat, lon = float(row["lat"]), float(row["lon"])
    except ValueError:
        continue
    if not (-90 <= lat <= 90 and -180 <= lon <= 180) or qid in kept:
        continue                              # a second coordinate statement for the same venue
    kept[qid] = (name, lat, lon, row.get("countryCode", "").strip())

with open(destination, "w", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["id", "name", "latitude", "longitude", "country"])
    # By name, then by id: Wikidata lists three separate Brazilian circuits all called
    # "Autódromo Internacional Ayrton Senna", so without the id the order is not reproducible.
    for qid, (name, lat, lon, country) in sorted(kept.items(), key=lambda kv: (kv[1][0].lower(), kv[0])):
        writer.writerow([qid, name, f"{lat:.5f}", f"{lon:.5f}", country])

print(f"{len(rows)} rows → {len(kept)} circuits ({unnamed} had no usable label), "
      f"{os.path.getsize(destination) // 1024} KB")
PY

echo "Wrote $out — review the diff, then run: swift test --filter Circuit"

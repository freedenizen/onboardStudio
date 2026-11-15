#!/usr/bin/env python3
"""Turns LapViz's circuits.json into the .onboardtrack files that ship with the app (#584).

LapViz (https://github.com/lapviz/LapViz.Telemetry, MIT, (c) Mengal SRL) publishes a start/finish
line for 196 mostly European layouts, and sector gates for some. This reads its
src/LapViz.Telemetry/Resources/circuits.json, keeps the layouts at circuits our catalogue
(Sources/TelemetryKit/Resources/circuits.csv) knows, and writes one definition per layout into
Sources/ProjectModel/Resources/Tracks, replacing the ones it wrote before. It never touches a file
it did not write (those are CC0 contributions), and it rewrites the LapViz part of that folder's
README.

    curl -sL https://raw.githubusercontent.com/lapviz/LapViz.Telemetry/main/src/LapViz.Telemetry/Resources/circuits.json -o /tmp/lapviz/circuits.json
    python3 -I Scripts/import-lapviz-tracks.py /tmp/lapviz/circuits.json

A circuit with one LapViz layout gets it as its usual layout; at a circuit with several, a
bracketed name is the configuration ("Silverstone (National)" is National), and so are an
unbracketed name's own words beyond the circuit's ("Nürburgring Nordschleife" is Nordschleife).
A kart track only matches a catalogue venue that is a kart track too.

A LapViz gate is two end points. Ours is a point and a heading, and a missing heading lays the line
across the track wherever a lap crosses it (`FinishLine`), so a gate becomes its midpoint, no
heading, and half its length as the line's half-width. No turns: LapViz has none.
Deterministic: run it again on the same file and nothing changes.
"""
import csv
import json
import math
import os
import re
import sys
import unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOGUE = os.path.join(ROOT, "Sources", "TelemetryKit", "Resources", "circuits.csv")
TRACKS = os.path.join(ROOT, "Sources", "ProjectModel", "Resources", "Tracks")
README = os.path.join(TRACKS, "README.md")
CREDIT = "LapViz (Mengal SRL), MIT"
PREFIX = "lapviz-"  # not part of any file name: files are named by id; this marks the README rows
BEGIN, END = "<!-- lapviz:begin -->", "<!-- lapviz:end -->"

# How far a layout's centre may be from the catalogue's point for its circuit, and the words that
# say nothing about which circuit a name is.
REACH_METRES = 3000
SAME_PLACE_METRES = 400
FILLER = {
    "circuit", "circuito", "raceway", "motor", "motorsport", "motorsports", "park", "speedway",
    "autodrome", "autodromo", "track", "international", "racing", "race", "kart", "karting", "ring",
    "the", "and", "del", "des", "de", "la", "le", "di", "du", "national", "club", "grand", "prix",
}


def slug(text):
    """TrackDefinition.slug: folded, lowercased, runs of anything else one '-', 64 at most."""
    folded = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)).casefold()
    out, pending = "", False
    for c in folded:
        if c.isalnum():
            if pending and out:
                out += "-"
            pending = False
            out += c
        else:
            pending = True
    return out[:64] if out else "track"


def words(name):
    return {w for w in re.findall(r"[a-z0-9]+", slug(name).replace("-", " ")) if len(w) >= 4 and w not in FILLER}


def latin(text):
    """Whether a name is written in the Latin script, as the rest of a title around it is."""
    return all(not c.isalpha() or "LATIN" in unicodedata.name(c, "") for c in text)


def metres(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


def gate(segment):
    _, a, b = segment
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    return {
        "latitude": round(mid[0], 7),
        "longitude": round(mid[1], 7),
        "halfWidthMeters": round(max(12.0, metres(a, b) / 2), 1),
        "headingToleranceDegrees": 60,
        "ignoreFirstCrossings": 0,
    }


def main(source):
    with open(CATALOGUE, newline="", encoding="utf-8") as f:
        catalogue = [(r["id"], r["name"], float(r["latitude"]), float(r["longitude"])) for r in csv.DictReader(f)]
    with open(source, encoding="utf-8") as f:
        layouts = json.load(f)

    # Forget what this script wrote last time; leave every other file alone.
    for name in os.listdir(TRACKS):
        path = os.path.join(TRACKS, name)
        if name.endswith(".onboardtrack"):
            with open(path, encoding="utf-8") as f:
                if json.load(f).get("credit") == CREDIT:
                    os.remove(path)

    def is_kart(text):
        return "kart" in slug(text)

    def circuit_of(layout, venue):
        centre = layout["center"]
        # A kart track beside a car circuit is not that circuit: it matches a kart venue only.
        near = [c for c in catalogue if not is_kart(layout["name"]) or is_kart(c[1])]
        def within(reach):
            return [c for c in near if metres(centre, (c[2], c[3])) <= reach]

        # Best first: a circuit nearby sharing a word of the layout's own name; then one close
        # enough to be the place whatever the catalogue calls it ("ドニントン・パーク", "Masaryk
        # Circuit" for Brno); then one sharing a word of the layout's town. Distance alone never
        # beats a name: the catalogue has entries a few metres from a circuit under another name.
        candidates = (
            [c for c in within(REACH_METRES) if words(c[1]) & words(venue)]
            or within(SAME_PLACE_METRES)
            or [c for c in within(REACH_METRES) if words(c[1]) & words(layout["location"])]
        )
        return min(candidates, key=lambda c: metres(centre, (c[2], c[3]))) if candidates else None

    # How many layouts each circuit has, so an unbracketed name at a circuit with several can be
    # told apart from the circuit's usual layout by its own words ("Nürburgring Nordschleife").
    per_circuit = {}
    for layout in layouts:
        bare = re.sub(r"\s*\([^)]*\)\s*$", "", layout["name"])
        found = circuit_of(layout, bare)
        if found:
            per_circuit[found[0]] = per_circuit.get(found[0], 0) + 1

    written, skipped = [], []
    for layout in sorted(layouts, key=lambda l: l["name"]):
        centre = layout["center"]
        name = layout["name"]
        configuration = None
        match = re.match(r"^(.*?)\s*\(([^)]+)\)\s*$", name)
        venue = match.group(1) if match else name
        if match:
            configuration = match.group(2).strip()
        circuit = circuit_of(layout, venue)
        if not circuit or not layout["segments"]:
            skipped.append(name)
            continue
        if per_circuit.get(circuit[0], 0) == 1:
            # The circuit's only layout here is its usual one: a bracket on a lone layout names a
            # place more often than a layout ("(Imola)", "(Le Mans)"), and a line with no heading
            # works whichever way the circuit is driven.
            configuration = None
        elif configuration is None:
            own = [w for w in re.findall(r"[^\s]+", venue) if words(w) and not words(w) & words(circuit[1])]
            configuration = " ".join(own) or None
        key = circuit[0] + ("|" + configuration if configuration else "")
        filename = slug(key) + ".onboardtrack"
        if any(w[0] == filename for w in written):
            skipped.append(name + " (a second layout under the same key)")
            continue
        if os.path.exists(os.path.join(TRACKS, filename)):
            # Only contributed files are left after the clear-out above: a driver's own
            # definition of this layout, which LapViz's lines do not replace.
            skipped.append(name + " (a contributed definition is there)")
            continue
        segments = sorted(layout["segments"], key=lambda s: s[0])
        sectors = [gate(s) for s in segments[1:]]
        definition = {
            "circuitID": circuit[0],
            "configuration": configuration,
            "name": circuit[1] if latin(circuit[1]) else venue,
            "latitude": circuit[2],
            "longitude": circuit[3],
            "startFinish": gate(segments[0]),
            "sectors": {"mode": "manual", "count": len(sectors) + 1, "lines": sectors}
            if sectors else {"mode": "equalDistance", "count": 3, "lines": []},
            "cornerLabels": [],
            "turnNames": [],
            "modified": re.sub(r"\.\d+", "", layout["updated"]).replace("+00:00", "Z"),
            "credit": CREDIT,
        }
        if configuration is None:
            del definition["configuration"]
        with open(os.path.join(TRACKS, filename), "w", encoding="utf-8") as f:
            json.dump(definition, f, indent=2, sort_keys=True, ensure_ascii=False)
            f.write("\n")
        written.append((filename, definition["name"] + (" — " + configuration if configuration else ""), name,
                        "sectors" if sectors else "start/finish"))

    rows = "\n".join(
        f"| `{file}` | {title} | LapViz, “{source_name}” | {what} from LapViz’s published gates, MIT |"
        for file, title, source_name, what in sorted(written)
    )
    with open(README, encoding="utf-8") as f:
        text = f.read()
    block = f"{BEGIN}\n{rows}\n{END}"
    text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), block, text, flags=re.S) if BEGIN in text else text.rstrip("\n") + "\n" + block + "\n"
    with open(README, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {len(written)} definitions; skipped {len(skipped)} layouts no catalogue circuit matched:")
    for name in skipped:
        print("  " + name)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: import-lapviz-tracks.py <LapViz circuits.json>")
    main(sys.argv[1])

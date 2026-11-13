#!/usr/bin/env python3
"""Writes an invented season of RaceChrono CSV v3 sessions for the guide's Logbook pictures (#542).

    Scripts/make-screenshot-logbook.py <folder>

Every number is made up: a closed loop of about 3 km drawn beside Thunderhill Raceway Park, so
the circuit catalogue recognises it, driven by a simple lap simulation — grip-limited corners,
braking and acceleration limits — on six days through 2026 that get quicker as the driver brakes
later and carries more speed, plus one visit to WeatherTech Raceway Laguna Seca. Nothing comes
from a real logger file. Deterministic: run it again and the files do not change.

Import them with `onboard logbook add <folder> --car Miata --logbook <scratch logbook>`; never
into your own logbook.
"""
import math
import os
import random
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

ZONE = ZoneInfo("America/Los_Angeles")
G = 9.81
HZ = 10

# Control points of a periodic cubic B-spline, in metres east/north of the venue.
LOOP = [
    (0, 0), (420, -20), (640, 60), (700, 260), (560, 380), (380, 330), (250, 470),
    (330, 650), (180, 760), (-60, 700), (-150, 520), (-60, 380), (-220, 250), (-260, 70),
]

CIRCUITS = {
    "Thunderhill Raceway Park": (39.54033, -122.33069, 1.0),
    "WeatherTech Raceway Laguna Seca": None,  # filled from the catalogue below
}

# (date, circuit, sessions, skill 0…1 — how much of the grip and braking the driver uses)
DAYS = [
    ("2026-03-14", "Thunderhill Raceway Park", 2, 0.00),
    ("2026-04-25", "Thunderhill Raceway Park", 2, 0.22),
    ("2026-06-06", "Thunderhill Raceway Park", 2, 0.38),
    ("2026-07-18", "Thunderhill Raceway Park", 2, 0.47),
    ("2026-08-22", "WeatherTech Raceway Laguna Seca", 2, 0.30),
    ("2026-09-19", "Thunderhill Raceway Park", 2, 0.66),
    ("2026-10-31", "Thunderhill Raceway Park", 2, 0.78),
]


def catalogue(name):
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "Sources", "TelemetryKit", "Resources", "circuits.csv")
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split(",")
            if len(parts) >= 4 and parts[1] == name:
                return float(parts[2]), float(parts[3])
    raise SystemExit(f"{name} is not in the circuit catalogue")


def spline(points, per_segment=400):
    n = len(points)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = (points[(i + k) % n] for k in range(4))
        for j in range(per_segment):
            t = j / per_segment
            b0 = (1 - t) ** 3 / 6
            b1 = (3 * t**3 - 6 * t**2 + 4) / 6
            b2 = (-3 * t**3 + 3 * t**2 + 3 * t + 1) / 6
            b3 = t**3 / 6
            out.append((
                b0 * p0[0] + b1 * p1[0] + b2 * p2[0] + b3 * p3[0],
                b0 * p0[1] + b1 * p1[1] + b2 * p2[1] + b3 * p3[1],
            ))
    return out


def resample(path, step=1.0):
    """Points every `step` metres round the closed path, with their heading."""
    pts = path + [path[0]]
    out = []
    carried = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        d = carried
        while d < seg:
            f = d / seg
            out.append((x0 + f * (x1 - x0), y0 + f * (y1 - y0)))
            d += step
        carried = d - seg
    headings = []
    for i in range(len(out)):
        (xa, ya), (xb, yb) = out[i - 1], out[(i + 1) % len(out)]
        headings.append(math.atan2(yb - ya, xb - xa))
    return out, headings


def curvature(headings, window=15):
    n = len(headings)
    raw = []
    for i in range(n):
        d = headings[(i + window) % n] - headings[i - window]
        d = (d + math.pi) % (2 * math.pi) - math.pi
        raw.append(abs(d) / (2 * window))
    return raw


def corners(kappa, threshold=0.004):
    """Index ranges where the loop turns, each with its tightest point."""
    n = len(kappa)
    start = next(i for i in range(n) if kappa[i] < threshold)
    found, inside, begin = [], False, 0
    for k in range(n):
        i = (start + k) % n
        if kappa[i] >= threshold and not inside:
            inside, begin = True, i
        elif kappa[i] < threshold and inside:
            inside = False
            span = [(begin + m) % n for m in range((i - begin) % n)]
            found.append(max(span, key=lambda j: kappa[j]))
    return found


def speed_profile(kappa, apexes, grip, brake, accel=3.2, top=52.0):
    """Speed at each metre: grip-limited in corners, then braking and acceleration limits."""
    n = len(kappa)
    limit = []
    for i in range(n):
        g = 1.0
        for apex, factor in zip(apexes, grip):
            if min((i - apex) % n, (apex - i) % n) < 120:
                g = factor
        lateral = 1.05 * G * g
        limit.append(min(top, math.sqrt(lateral / max(kappa[i], 1e-6))))
    v = limit[:]
    for _ in range(2):  # backwards: braking into each corner, at that corner's own rate
        for k in range(2 * n, 0, -1):
            i, j = k % n, (k + 1) % n
            b = brake[min(range(len(apexes)), key=lambda c: (apexes[c] - i) % n)]
            v[i] = min(v[i], math.sqrt(v[j] ** 2 + 2 * b * G))
    for _ in range(2):  # forwards: accelerating out, less at speed
        for k in range(2 * n):
            i, j = k % n, (k + 1) % n
            a = accel * max(0.15, 1 - v[i] / (top * 1.1))
            v[j] = min(v[j], math.sqrt(v[i] ** 2 + 2 * a))
    return v


def session(path, headings, kappa, apexes, origin, skill, rng, start, title, laps=8):
    lat0, lon0, scale = origin
    m_lat = 110_540.0
    m_lon = 111_320.0 * math.cos(math.radians(lat0))
    n = len(path)
    rows = []
    t, travelled, lap = 0.0, 0.0, 0
    s = n - 400.0  # leave the pits 400 m before the line
    v = 12.0
    profiles = []
    for _ in range(laps):
        off = rng.uniform(0.0, 0.05)  # a scrappy lap now and then
        grip = [0.80 + 0.17 * skill - off + rng.uniform(-0.06, 0.03) for _ in apexes]
        brake = [0.55 + 0.35 * skill - 2 * off + rng.uniform(-0.15, 0.06) for _ in apexes]
        profiles.append(speed_profile(kappa, apexes, grip, brake))
    profile = profiles[0]
    previous = None
    total_laps = laps
    while True:
        i = int(s) % n
        target = min(profile[i], 14.0 + t * 1.5) if lap == 0 else profile[i]
        # no faster than 1.2 G either way, where one lap's driving hands over to the next
        v = target if previous is None else max(previous - 1.2 * G / HZ, min(target, previous + 0.4 * G / HZ))
        x, y = path[i]
        lat = lat0 + y * scale / m_lat
        lon = lon0 + x * scale / m_lon
        bearing = (90 - math.degrees(headings[i])) % 360
        lon_acc = 0.0 if previous is None else (v - previous) * HZ / G
        lat_acc = v * v * kappa[i] / G
        epoch = start + t
        rows.append((epoch, "" if lap == 0 else lap, t, travelled, lat, lon, bearing, v,
                     math.hypot(lat_acc, lon_acc), lat_acc, lon_acc))
        previous = v
        t += 1 / HZ
        step = v / HZ
        travelled += step
        before = s
        s += step * (1 / scale)
        if int(before // n) != int(s // n):
            lap += 1
            if lap > total_laps:
                break
            profile = profiles[lap - 1]
    return rows


def write(folder, name, title, start, rows):
    created = datetime.fromtimestamp(start, ZONE)
    lines = [
        "This file is created using RaceChrono Pro v9.1.3 ( http://racechrono.com/ ).",
        "Format,3",
        f'Session title,"{title}"',
        "Session type,Lap timing",
        f'Track name,"{title}"',
        'Driver name,"Alex"',
        f"Created,{created:%d/%m/%Y},{created:%H:%M}",
        'Note,"invented for the documentation pictures"',
        "",
        "timestamp,fragment_id,lap_number,elapsed_time,distance_traveled,latitude,longitude,"
        "bearing,speed,combined_acc,lateral_acc,longitudinal_acc",
        "unix time,,,s,m,deg,deg,deg,m/s,G,G,G",
        ",,,,,100: gps,100: gps,100: gps,100: gps,calc,calc,calc",
    ]
    for r in rows:
        lines.append(
            f"{r[0]:.2f},0,{r[1]},{r[2]:.2f},{r[3]:.1f},{r[4]:.7f},{r[5]:.7f},{r[6]:.1f},"
            f"{r[7]:.2f},{r[8]:.3f},{r[9]:.3f},{r[10]:.3f}")
    with open(os.path.join(folder, name), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    laguna = catalogue("WeatherTech Raceway Laguna Seca")
    CIRCUITS["WeatherTech Raceway Laguna Seca"] = (laguna[0], laguna[1], 0.85)
    path, headings = resample(spline(LOOP))
    kappa = curvature(headings)
    apexes = corners(kappa)
    rng = random.Random(542)
    for date, circuit, count, skill in DAYS:
        for number in range(count):
            day = datetime.fromisoformat(date).replace(hour=9 + 2 * number, minute=20, tzinfo=ZONE)
            start = day.timestamp()
            rows = session(path, headings, kappa, apexes, CIRCUITS[circuit],
                           skill + 0.06 * number, rng, start, circuit)
            name = f"{date} {circuit.split()[0]} session {number + 1}.csv"
            write(folder, name, circuit, start, rows)
            print(name, f"{len(rows) / HZ / 60:.1f} min")
    print(f"{len(apexes)} corners")


if __name__ == "__main__":
    main()

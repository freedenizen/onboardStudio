#!/usr/bin/env python3
"""Writes Tests/Fixtures/performance.d/drag.vbo: two standing starts and two stops on a straight,
level road at 10 Hz in Racelogic VBO, so performance runs (#553) can be timed from a file alone.

Every phase has a constant acceleration, so every answer is arithmetic (t = v / a, d = a t² / 2):

- Start 1 pulls 4 m/s² for 14 s (56 m/s), then brakes at 8 m/s² to standing still.
- Start 2 pulls 5 m/s² for 13 s (65 m/s), then brakes at 10 m/s² to standing still.

So start 2 is the quicker: 0–60 mph in 26.8224 / 5 = 5.364 s (start 1: 6.706 s), and the
quarter mile, with a 1-ft rollout, in 12.342 s. Stop 2 is the shorter: 60–0 mph in
26.8224² / 20 = 35.97 m, 118 ft (stop 1: 44.96 m). The file carries a distance column, the
distance along the road, so nothing depends on how GPS positions are turned into metres. It has no
laps and no gates: a session that is measured on its own. Positions run north from 47° N, 8° E, a
place with no circuit to be recognised. It lives in a folder with an extension, which a
whole-folder import skips, so the UI tests that add every fixture as a track day do not gain a
session. Deterministic: run it again and the file does not change."""
import os

ORIGIN_LAT, ORIGIN_LON = 47.0, 8.0
M_PER_DEG_LAT = 111_195.0
HZ = 10

# (seconds standing, acceleration m/s², seconds accelerating, deceleration m/s²)
STARTS = [(5, 4.0, 14, 8.0), (5, 5.0, 13, 10.0)]
TAIL = 5


def phases():
    """(duration, initial speed, acceleration) pieces, in order."""
    for standing, accel, pulling, decel in STARTS:
        yield standing, 0.0, 0.0
        yield pulling, 0.0, accel
        top = accel * pulling
        yield top / decel, top, -decel
    yield TAIL, 0.0, 0.0


def samples():
    """(seconds, metres along the road, m/s) at HZ, exact at every sample."""
    pieces = []
    t0, d0 = 0.0, 0.0
    for duration, v0, a in phases():
        pieces.append((t0, d0, duration, v0, a))
        d0 += v0 * duration + a * duration * duration / 2
        t0 += duration
    total = t0
    index = 0
    while index / HZ <= total + 1e-9:
        t = index / HZ
        for start, distance, duration, v0, a in pieces:
            if t <= start + duration + 1e-9:
                dt = t - start
                yield t, distance + v0 * dt + a * dt * dt / 2, max(0.0, v0 + a * dt)
                break
        index += 1


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lines = [
        "File created on 14/11/2026 at 10:00:00",
        "",
        "[header]",
        "satellites",
        "time",
        "latitude",
        "longitude",
        "velocity kmh",
        "heading",
        "height",
        "distance",
        "",
        "[comments]",
        "Synthetic OnboardStudio fixture: two standing starts and stops (Scripts/make-performance-fixture.py).",
        "Log Rate (Hz) : 10.00",
        "",
        "[column names]",
        "sats time lat long velocity heading height distance",
        "",
        "[data]",
    ]
    for t, metres, speed in samples():
        seconds = 10 * 3600 + t
        clock = f"{int(seconds // 3600):02d}{int(seconds % 3600 // 60):02d}{seconds % 60:06.3f}"
        lat = (ORIGIN_LAT + metres / M_PER_DEG_LAT) * 60
        long = -ORIGIN_LON * 60
        lines.append(
            f"012 {clock} {lat:+012.6f} {long:+013.6f} {speed * 3.6:08.4f} 000.000 +00450.00 {metres:010.4f}"
        )
    folder = os.path.join(root, "Tests", "Fixtures", "performance.d")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "drag.vbo"), "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

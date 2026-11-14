#!/usr/bin/env python3
"""Writes Tests/Fixtures/runs.d/autocross.vbo: three runs of a synthetic autocross course at 5 Hz in
Racelogic VBO, with the start and finish gates in its [laptiming] section, so a point-to-point
course can be timed in runs (#552) from a file alone.

The course is the one in Tests/TelemetryKitTests/RunDetectorTests.swift: staged at (-10, 0),
start line at x = 0 crossed going east, finish line at x = 100 on the top straight crossed going
west. The course passes the finish once mid-run, going the same way, and the start too; only the
last finish crossing ends a run. Runs 1 and 2 finish (1,040 m at 20 and 16 m/s: 52 s and 65 s);
run 3 turns off before the finish and stops, a DNF. Between runs the car drives back to the grid
round the outside, crossing neither line. Positions are metres east and north of 47° N, 8° E, a
place with no circuit to be recognised. It lives in a folder with an extension, which a whole-folder
import skips as it skips a package, so the UI tests that add every fixture as a track day do not
gain a session. Deterministic: run it again and the file does not change."""
import math
import os

ORIGIN_LAT, ORIGIN_LON = 47.0, 8.0
M_PER_DEG_LAT = 110_540.0
M_PER_DEG_LON = 111_320.0 * math.cos(math.radians(ORIGIN_LAT))
HZ = 5


def course(speed):
    return [
        ("drive", 200, 0, speed), ("drive", 200, 100, speed), ("drive", -20, 100, speed),
        ("drive", -20, 0, speed), ("drive", 200, 0, speed), ("drive", 200, 100, speed),
        ("drive", 50, 100, speed), ("stop", 5),
    ]


BACK_TO_GRID = [
    ("drive", 50, 150, 8), ("drive", -60, 150, 8), ("drive", -60, 0, 8), ("drive", -10, 0, 5), ("stop", 10),
]
OFF_COURSE = [("drive", 200, 0, 20), ("drive", 200, 100, 20), ("drive", 150, 100, 20), ("stop", 5)]
STEPS = [("stop", 10)] + course(20) + BACK_TO_GRID + course(16) + BACK_TO_GRID + OFF_COURSE


def samples():
    x, y = -10.0, 0.0
    heading = 90.0
    for step in STEPS:
        if step[0] == "stop":
            for _ in range(int(step[1] * HZ)):
                yield x, y, 0.0, heading
            continue
        _, tx, ty, speed = step
        dx, dy = tx - x, ty - y
        length = math.hypot(dx, dy)
        count = max(1, round(length / (speed / HZ)))
        heading = math.degrees(math.atan2(dx, dy)) % 360
        for _ in range(count):
            x += dx / count
            y += dy / count
            yield x, y, speed, heading


def minutes_lat(y):
    return (ORIGIN_LAT + y / M_PER_DEG_LAT) * 60


def minutes_long(x):
    # VBO longitude is west-positive.
    return -(ORIGIN_LON + x / M_PER_DEG_LON) * 60


def gate(kind, x, y0, y1, label):
    return (
        f"{kind:<12} {minutes_long(x):+013.6f} {minutes_lat(y0):+012.6f} "
        f"{minutes_long(x):+013.6f} {minutes_lat(y1):+012.6f} ¬  {label}"
    )


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lines = [
        "File created on 13/11/2026 @ 10:00:00",
        "",
        "[header]",
        "satellites",
        "time",
        "latitude",
        "longitude",
        "velocity kmh",
        "heading",
        "height",
        "",
        "[laptiming]",
        gate("Start", 0, -10, 10, "Start"),
        gate("Finish", 100, 90, 110, "Finish"),
        "",
        "[comments]",
        "Synthetic OnboardStudio fixture: three autocross runs (Scripts/make-runs-fixture.py).",
        "Log Rate (Hz) : 5.00",
        "",
        "[column names]",
        "sats time lat long velocity heading height",
        "",
        "[data]",
    ]
    for index, (x, y, speed, heading) in enumerate(samples()):
        seconds = 10 * 3600 + index / HZ
        clock = f"{int(seconds // 3600):02d}{int(seconds % 3600 // 60):02d}{seconds % 60:06.3f}"
        lines.append(
            f"012 {clock} {minutes_lat(y):+012.6f} {minutes_long(x):+013.6f} "
            f"{speed * 3.6:07.3f} {heading:07.3f} +00450.00"
        )
    with open(os.path.join(root, "Tests", "Fixtures", "runs.d", "autocross.vbo"), "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

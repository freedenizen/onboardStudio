#!/usr/bin/env bash
# Generates the small synthetic media fixtures committed under Tests/Fixtures (requires ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."
# 3 s H.264/AAC test pattern.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t 3 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 \
  -c:a aac -b:a 64k -movflags +faststart \
  Tests/Fixtures/test-3s.mp4
# 1 s MPEG transport stream (AVCHD-style) that AVFoundation cannot open directly.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=320x180:rate=25" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -an -f mpegts \
  Tests/Fixtures/test-1s.mts
# 1 s stereo clip with a 440 Hz tone on the left channel only and 880 Hz on the right.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=160x90:rate=25" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000" \
  -filter_complex "[1:a][2:a]join=inputs=2:channel_layout=stereo[a]" -map 0:v -map "[a]" \
  -t 1 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 128k \
  Tests/Fixtures/stereo-1s.mp4
ls -la Tests/Fixtures/test-3s.mp4 Tests/Fixtures/test-1s.mts Tests/Fixtures/stereo-1s.mp4
# 1 s clip whose display matrix says "rotate 180°" (like an upside-down mounted camera).
# The rotation is an input-side option, so encode first and then remux with the matrix.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=320x180:rate=25" -t 1 \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -an \
  "$TMPDIR/overlaygen-rot-src.mp4"
ffmpeg -y -hide_banner -loglevel error -display_rotation 180 -i "$TMPDIR/overlaygen-rot-src.mp4" -c copy \
  Tests/Fixtures/test-rot180.mp4
rm -f "$TMPDIR/overlaygen-rot-src.mp4"
ls -la Tests/Fixtures/test-rot180.mp4

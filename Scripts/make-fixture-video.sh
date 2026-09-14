#!/usr/bin/env bash
# Generates the small synthetic test video committed under Tests/Fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t 3 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 \
  -c:a aac -b:a 64k -movflags +faststart \
  Tests/Fixtures/test-3s.mp4
ls -la Tests/Fixtures/test-3s.mp4

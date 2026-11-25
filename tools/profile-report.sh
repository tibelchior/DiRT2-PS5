#!/bin/bash
# Shows where the game's threads spend their time, from a log made with the "profile" switch
# file (see README.md). The log must come from the same build as the last ./build.sh run.
# Usage: tools/profile-report.sh path/to/dirt2.log [--min-busy=80]   (80: only the busy, race-like reports)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ -f "${1:-}" ] || { echo "usage: tools/profile-report.sh path/to/dirt2.log" >&2; exit 2; }
LOG=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
docker run --rm -v dirt2ps5-build-data:/build:ro -v "$HERE/ps5":/tools:ro -v "$LOG":/log/dirt2.log:ro \
    dirt2ps5-build python3 /tools/profile_report.py /log/dirt2.log "${@:2}"

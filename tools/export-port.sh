#!/bin/bash
# For developers: writes the changes in a working clone of the upstream recompilation back into
# this repository, as ps5/patches/dirt2/0001-ps5-port.patch (changed upstream files) and
# ps5/overlay/Dirt2 (new files). Usage: tools/export-port.sh <path to the Dirt2 clone>
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:?usage: tools/export-port.sh <path to the Dirt2 clone>}
source "$HERE/tools/pins.env"
[ "$(git -C "$SRC" rev-parse HEAD)" = "$DIRT2_COMMIT" ] || { echo "the clone is not at the pinned commit $DIRT2_COMMIT" >&2; exit 1; }
git -C "$SRC" diff HEAD --binary > "$HERE/ps5/patches/dirt2/0001-ps5-port.patch"
rm -rf "$HERE/ps5/overlay/Dirt2"
git -C "$SRC" ls-files --others --exclude-standard | while read -r f; do
    mkdir -p "$HERE/ps5/overlay/Dirt2/$(dirname "$f")"
    cp "$SRC/$f" "$HERE/ps5/overlay/Dirt2/$f"
done
echo "patch: $(wc -l < "$HERE/ps5/patches/dirt2/0001-ps5-port.patch") lines; overlay: $(find "$HERE/ps5/overlay" -type f | wc -l | tr -d ' ') files"

#!/bin/bash
# Packs the port kit into dist/DiRT2-PS5-v<version>.zip: sources and scripts only. No game files and no
# built title: the title holds the game's code recompiled from the player's own dirt2_game.exe, so each
# player builds their own. The shader cache, when present in cache/, goes into its own zip.
#   tools/package-release.sh 1.0.0
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: tools/package-release.sh <version>}
NAME=DiRT2-PS5-v$VERSION
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" "$HERE/dist"
cd "$HERE"
# what git tracks or would track: .gitignore keeps the game, the art, the cache and the builds out
git ls-files -co --exclude-standard -z | rsync -a --files-from=- --from0 ./ "$STAGE/$NAME/"
bad=$(cd "$STAGE/$NAME" && find . \( -path './dist' -o -iname '*.exe' -o -name eboot.bin -o -name '*.prx' \
      -o -name 'dirt2.*' -o -path './art/*.png' -o -path './art/*.jpg' \))
[ -z "$bad" ] || { echo "error: files that must not ship:" >&2; echo "$bad" >&2; exit 1; }
find "$STAGE" -name .DS_Store -delete
OUT=$HERE/dist/$NAME.zip
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" "$NAME")
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"

if [ -f cache/dirt2.dxvk.bin ] && [ -f cache/dirt2.dxvk.lut ] && [ -f cache/dirt2.pipelines ]; then
    OUT=$HERE/dist/DiRT2-PS5-shader-cache-v$VERSION.zip
    rm -f "$OUT"
    zip -qj "$OUT" cache/dirt2.dxvk.bin cache/dirt2.dxvk.lut cache/dirt2.pipelines
    echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
fi

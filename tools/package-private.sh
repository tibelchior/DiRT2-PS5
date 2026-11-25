#!/bin/bash
# Packs the built title into dist/DiRT2-PS5-v<version>-private.zip: the title only, without the game's data.
# FOR YOUR OWN USE: eboot.bin holds the game's code recompiled from your dirt2_game.exe (and your art), so do
# not share this zip (the shareable one is tools/package-release.sh).
#   tools/package-private.sh 1.0.0 [built title folder, default dist/PPSA99777]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
source "$HERE/tools/pins.env"
VERSION=${1:?usage: tools/package-private.sh <version> [title folder]}
SRC=${2:-$HERE/dist/$TITLE_ID}
[ -f "$SRC/eboot.bin" ] || { echo "error: no title in $SRC: run ./build.sh first" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
T=$STAGE/$TITLE_ID
mkdir -p "$T/Dirt 2"
cp "$SRC/eboot.bin" "$T/"
cp -R "$SRC/sce_sys" "$SRC/sce_module" "$T/"
for f in dirt2.dxvk.bin dirt2.dxvk.lut dirt2.pipelines; do [ ! -f "$SRC/$f" ] || cp "$SRC/$f" "$T/"; done
cat > "$T/Dirt 2/PUT_THE_GAME_FILES_HERE.txt" <<'TXT'
Copy everything from your Colin McRae: DiRT 2 (PC, version 1.1) game folder into this folder: the one that
holds dirt2_game.exe. Use the same dirt2_game.exe this title was built from.
TXT
find "$STAGE" -name .DS_Store -delete
OUT=$HERE/dist/DiRT2-PS5-v$VERSION-private.zip
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" "$TITLE_ID")
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
unzip -l "$OUT" | tail -n +4

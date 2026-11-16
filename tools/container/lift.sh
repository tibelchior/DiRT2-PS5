#!/bin/bash
# Recompiles the user's dirt2_game.exe (mounted at /game) into C, with the upstream recompiler.
source "$(dirname "$0")/common.sh"
cd "$TREE/Dirt2"
exe=/game/dirt2_game.exe
log "recompiler"
cmake -S . -B build/host-tools -G Ninja -DCMAKE_BUILD_TYPE=Release -DDIRT2_TOOLS_ONLY=ON > "$OUT.lift-cmake.log" 2>&1 ||
    { tail -20 "$OUT.lift-cmake.log"; exit 1; }
cmake --build build/host-tools --target recomp -j"$(nproc)" > "$OUT.lift-build.log" 2>&1 || { tail -30 "$OUT.lift-build.log"; exit 1; }

want="$(sha256sum "$exe" | cut -c1-64) $(cat tools/recomp/config/*.txt | sha256sum | cut -c1-16) $(cat .ps5-port-stamp)"
if [ -f generated/.lift-stamp ] && [ "$(cat generated/.lift-stamp)" = "$want" ] && [ -f generated/sources.txt ]; then
    echo "lift: already done"; exit 0
fi
log "recompiling the game (about 5 minutes)"
rm -rf generated
build/host-tools/tools/recomp/recomp lift "$exe" --out generated \
    --entries tools/recomp/config/entries.txt --hooks tools/recomp/config/hooks.txt --include-dead > "$OUT.lift.log" 2>&1 ||
    { tail -30 "$OUT.lift.log"; exit 1; }
echo "$want" > generated/.lift-stamp
rm -rf "$OUT/ps5-obj/gen"      # lifted code changed: its objects are stale
echo "lift: $(ls generated/src/*.c | wc -l) source files"

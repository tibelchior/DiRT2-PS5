#!/bin/bash
# Builds the PS5 title for DiRT 2 from your own copy of the game.
#
#   ./build.sh            everything: toolchain (first time only), recompile, build, package
#   ./build.sh toolchain  only the PS5 toolchain (first time: 1 to 2 hours)
#   ./build.sh lift       only recompile the game executable
#   ./build.sh title      only build the title (needs the steps above)
#
# Options (environment):
#   GAME_DIR=<folder>     the folder that holds dirt2_game.exe (default: gamedata/Dirt 2)
#   NO_GAME=1             leave the game files out of dist/ (copy them to the console yourself)
#   ALLOW_OTHER_EXE=1     do not stop when dirt2_game.exe is not the known v1.1 file
#   BUILD_VOLUME=<name>   Docker volume holding the toolchain and build trees (default dirt2ps5-build-data)
#
# Needs: Docker (Docker Desktop on macOS or Windows+WSL, or Docker on Linux), about 60 GB free,
# and the game: Colin McRae: DiRT 2, PC version 1.1 (Steam). Nothing from the game is uploaded.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/tools/pins.env"
STEP=${1:-all}
IMAGE=dirt2ps5-build VOLUME=${BUILD_VOLUME:-dirt2ps5-build-data} NAME=dirt2ps5
die() { echo "error: $*" >&2; exit 1; }

command -v docker > /dev/null || die "Docker is not installed (https://www.docker.com/products/docker-desktop/)."
docker info > /dev/null 2>&1 || die "Docker is installed but not running. Start it and try again."

# --- the game ---------------------------------------------------------------------------
GAME=${GAME_DIR:-}
if [ -z "$GAME" ]; then
    for d in "$HERE/gamedata/Dirt 2" "$HERE/gamedata"; do
        [ -f "$d/dirt2_game.exe" ] && { GAME=$d; break; }
    done
fi
if [ "$STEP" = toolchain ]; then GAME=$HERE/gamedata; fi
[ -n "$GAME" ] || die "no game found. Copy your DiRT 2 folder (the one with dirt2_game.exe) into gamedata/, or set GAME_DIR."
if [ "$STEP" != toolchain ]; then
    [ -f "$GAME/dirt2_game.exe" ] || die "$GAME/dirt2_game.exe not found."
    sha=$( (shasum -a 256 "$GAME/dirt2_game.exe" 2> /dev/null || sha256sum "$GAME/dirt2_game.exe") | cut -d' ' -f1)
    if [ "$sha" != "$GAME_EXE_SHA256" ] && [ "${ALLOW_OTHER_EXE:-0}" != 1 ]; then
        die "dirt2_game.exe is not the expected v1.1 file (sha256 $sha). The recompiler only fits that version; set ALLOW_OTHER_EXE=1 to try anyway."
    fi
    echo "game: $GAME"
fi

# --- the container ----------------------------------------------------------------------
echo "== build image"
docker build -q -t "$IMAGE" "$HERE/docker" > /dev/null
docker volume create "$VOLUME" > /dev/null
docker rm -f "$NAME" > /dev/null 2>&1 || true
mkdir -p "$HERE/dist" "$HERE/art" "$HERE/cache"
docker run -d --name "$NAME" -v "$VOLUME":/build -v "$HERE":/work -v "$GAME":/game:ro "$IMAGE" sleep infinity > /dev/null
trap 'docker rm -f "$NAME" > /dev/null 2>&1 || true' EXIT
run() { docker exec -e VOL=/build "$NAME" bash "/work/tools/container/$1.sh"; }

case $STEP in
    toolchain) run toolchain ;;
    lift) run sources; run lift ;;
    title) run toolchain; run sources; run lift; run title ;;
    all) run toolchain; run sources; run lift; run title ;;
    *) die "unknown step '$STEP' (all, toolchain, lift, title)" ;;
esac
[ "$STEP" = toolchain ] || [ "$STEP" = lift ] || {
    OUTDIR=$HERE/dist/$TITLE_ID
    [ -f "$OUTDIR/eboot.bin" ] || die "the build did not produce $OUTDIR/eboot.bin"
    if [ "${NO_GAME:-0}" != 1 ]; then
        echo "== copying the game files into the title (about 10 GB)"
        mkdir -p "$OUTDIR/Dirt 2"
        rsync -a --exclude '*.lnk' --exclude '_dxmt.log' "$GAME/" "$OUTDIR/Dirt 2/"
    fi
    echo
    echo "Done: $OUTDIR"
    echo "Copy it to the console as /data/homebrew/$TITLE_ID (see Install on the console in README.md)."
}

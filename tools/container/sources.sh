#!/bin/bash
# The upstream recompilation at its pinned commit, with this repository's PS5 port applied
# (ps5/patches/dirt2 and ps5/overlay), DXVK prepared, and the third-party libraries fetched.
source "$(dirname "$0")/common.sh"
mkdir -p "$TREE" && cd "$TREE"

log "upstream sources"
[ -d Dirt2/.git ] || git clone -q "$DIRT2_REPO" Dirt2
cd Dirt2
want=$( { find /work/ps5/overlay -type f | sort | xargs cat; cat /work/ps5/patches/dirt2/*.patch; } | sha256sum | cut -c1-16)
want="$DIRT2_COMMIT $want"
if [ ! -f .ps5-port-stamp ] || [ "$(cat .ps5-port-stamp)" != "$want" ]; then
    git -c advice.detachedHead=false checkout -q --force "$DIRT2_COMMIT" 2>/dev/null ||
        { git fetch -q origin && git -c advice.detachedHead=false checkout -q --force "$DIRT2_COMMIT"; }
    git reset -q --hard "$DIRT2_COMMIT"
    git clean -fdq -e build -e generated -e .ps5-port-stamp
    log "applying the PS5 port"
    for p in /work/ps5/patches/dirt2/*.patch; do git apply --whitespace=nowarn "$p"; done
    cp -R /work/ps5/overlay/Dirt2/. .
    echo "$want" > .ps5-port-stamp
fi

log "DXVK"
git submodule update --init --recursive -q third_party/dxvk
bash tools/scripts/prepare_sources.sh --dxvk-only

log "libraries (SDL3, OpenAL Soft, Ogg, Vorbis, FFmpeg)"
# The script was written for macOS: GNU tar cannot detect compression on a pipe, bsdtar can.
mkdir -p "$TREE/.shim" && ln -sf "$(command -v bsdtar)" "$TREE/.shim/tar"
rm -rf build/deps/src.tmp build/deps/src.lock     # left behind if an earlier run was interrupted
PATH="$TREE/.shim:$PATH" bash tools/scripts/build_deps.sh --fetch-only

log "build scripts"
mkdir -p "$TREE/ps5-spike"
rsync -a --exclude title/sce_sys --exclude shipped /work/ps5/ "$TREE/ps5-spike/"
mkdir -p "$TREE/ps5-spike/shipped"
rm -f "$TREE"/ps5-spike/shipped/*
for f in dirt2.dxvk.bin dirt2.dxvk.lut dirt2.pipelines; do
    [ -f "/work/cache/$f" ] && cp "/work/cache/$f" "$TREE/ps5-spike/shipped/$f"
done
echo "shader cache: $(ls "$TREE/ps5-spike/shipped" | wc -l) of 3 files found in cache/"

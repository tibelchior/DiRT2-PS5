#!/bin/bash
# Rebuilds the payload SDK's platform library (libps5platform.a) with this port's patches from
# ps5/patches/payloadsdk. PS5_Vulkan installs the library from its own pinned SDK revision; the
# patches go on that revision's sources and the rebuilt library replaces the installed one.
# Does nothing when the installed library already carries the current patches.
source "$(dirname "$0")/common.sh"
patches=(/work/ps5/patches/payloadsdk/*.patch)
want=$(cat "${patches[@]}" | sha256sum | cut -d' ' -f1)
stamp=$PS5_SDK_DIR/.dirt2-platform-patches
[ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ] && { echo "sdk patches: already applied"; exit 0; }

rev=$(sed -n 's/^sdk_revision=//p' "$VK/tools/setup-native-dependencies.sh")
[ -n "$rev" ] || { echo "sdk-patch: no sdk_revision in PS5_Vulkan's setup script" >&2; exit 1; }
log "payload SDK platform library with patches ($rev)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$VOL/PS5_PayloadSDK" cat-file -e "$rev^{commit}" 2>/dev/null || git -C "$VOL/PS5_PayloadSDK" fetch -q origin
git -C "$VOL/PS5_PayloadSDK" archive "$rev" | tar -x -C "$tmp"
for p in "${patches[@]}"; do (cd "$tmp" && git apply "$p") || { echo "sdk-patch: $p does not apply" >&2; exit 1; }; done
export PATH=$PS5_SDK_DIR/bin:$PATH
make -s -C "$tmp/platform" install DESTDIR="$tmp/out" > "$VOL/sdk-patch.log" 2>&1 || { tail -20 "$VOL/sdk-patch.log"; exit 1; }
cp "$tmp/out/target/lib/libps5platform.a" "$PS5_SDK_DIR/target/lib/libps5platform.a"
echo "$want" > "$stamp"

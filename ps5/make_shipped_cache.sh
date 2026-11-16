#!/bin/bash
# Turns the shader cache and pipeline list the title recorded on the console into the set that
# ships with it (ps5-spike/shipped, copied next to eboot.bin by build_headless.sh --title).
#
# 1. Play: menus, every track type, a race or two, the garage and shop. The title writes
#    dirt2.dxvk.bin, dirt2.dxvk.lut and dirt2.pipelines to its data folder (PPSA99777/data).
# 2. Copy those three files off the console into one folder, or into several (one per play session).
# 3. ps5-spike/make_shipped_cache.sh <folder of dirt2.dxvk.* and dirt2.pipelines> [more folders]
#    The shader cache and pipeline list of the LAST folder given are used, merged with the
#    pipeline lists of the others; the report says how many pipelines can be warmed up with it.
# 4. Rebuild the title.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/ps5-spike/shipped
[ $# -ge 1 ] || { sed -n '2,12p' "$0" >&2; exit 2; }
last=${!#}
for f in dirt2.dxvk.bin dirt2.dxvk.lut dirt2.pipelines; do
    [ -f "$last/$f" ] || { echo "missing $last/$f" >&2; exit 1; }
done
mkdir -p "$OUT"
lists=()
for d in "$@"; do [ -f "$d/dirt2.pipelines" ] && lists+=("$d/dirt2.pipelines"); done
python3 "$ROOT/Dirt2/tools/scripts/merge_pipelines.py" -o "$OUT/dirt2.pipelines" --lut "$last/dirt2.dxvk.lut" "${lists[@]}"
cp "$last/dirt2.dxvk.bin" "$last/dirt2.dxvk.lut" "$OUT/"
ls -la "$OUT"

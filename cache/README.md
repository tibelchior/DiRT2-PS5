# Shader cache (optional)

Without these files the game still runs. It builds its shader cache while you play, so the
first races stutter a little until it has seen every shader.

The three files here were recorded on a PS5 while playing and are copied next to `eboot.bin`
by `build.sh` when present:

- `dirt2.dxvk.bin` and `dirt2.dxvk.lut`: DXVK's shader cache
- `dirt2.pipelines`: the list of graphics pipelines to prepare while the game loads

They are generated from DiRT 2's own shaders and only fit DiRT 2 v1.1 on this build. They are
published as a separate download next to the release, not inside this repository, and are
listed in `.gitignore`.

To make your own: play for a while, copy the three files from
`/data/homebrew/PPSA99777/data/` on the console into a folder, then run
`ps5/make_shipped_cache.sh <folder>` and copy the result back into this folder.

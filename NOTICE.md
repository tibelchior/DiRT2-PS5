# Notices

This repository contains only the changes and build scripts for the PS5 port. It contains no game
data, no Sony software and no keys.

- **DiRT 2 recompilation** (runtime, recompiler, shims): XITRIX/Dirt-2-Recomp, fetched at the
  commit pinned in `tools/pins.env`. That repository had no licence file at the pinned commit, so
  this repository does not copy its code: `build.sh` downloads it, and only our changes are
  included (the patch in `ps5/patches/dirt2` and the new files in `ps5/overlay`). Ask its author
  before redistributing built binaries.
- **PS5 toolchain, payload SDK and Vulkan driver**: mihawk-99/PS5_Vulkan, PS5_PayloadSDK and
  PS5_Mesa, fetched at pinned commits (GPL-3.0 and Mesa's licences). A finished title links their
  code, so share built titles only together with the source obligations those licences require.
- **DXVK** (zlib licence), **SDL3** (zlib), **OpenAL Soft** (LGPL), **FFmpeg** (LGPL),
  **Ogg/Vorbis** (BSD): fetched during the build and linked statically.
- **Colin McRae: DiRT 2** is the property of Codemasters. This project is not affiliated with or
  endorsed by Codemasters, Electronic Arts or Sony. You need your own legal copy of the game.
- The shader cache, if you download it, was generated from the game's own shaders.

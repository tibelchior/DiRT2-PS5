# DiRT 2 on PS5

Colin McRae: DiRT 2 (PC, v1.1) running natively on a jailbroken PS5, built from
[XITRIX's static recompilation](https://github.com/XITRIX/Dirt-2-Recomp), with
[mihawk-99's PS5 Vulkan stack](https://github.com/mihawk-99/PS5_Vulkan) and DXVK.

**You bring your own game files. Nothing from the game is in this repository.** The build
recompiles your `dirt2_game.exe` on your own computer and packages the result as a PS5 title.

## What you need

- A PS5 with homebrew enabled and a way to launch titles from `/data/homebrew` (tested on
  firmware 11.20 with ShadowMountPlus), and FTP access to the console.
- A computer with **Docker** (macOS, Linux, or Windows with WSL2), about **60 GB** free disk space
  and 16 GB of memory. Apple silicon and x86-64 both work.
- **Colin McRae: DiRT 2**, PC version **1.1** (Steam). The folder that holds `dirt2_game.exe`.

## Build

1. Get this repository:

   ```bash
   git clone <this repository's URL> DiRT2-PS5
   cd DiRT2-PS5
   ```

2. Copy your game folder into `gamedata/`, so that `gamedata/Dirt 2/dirt2_game.exe` exists.
3. Optional: put `icon.png` and `wallpaper.png` in `art/` for your own home-screen art, and the
   shader cache files in `cache/` (see the READMEs in those folders).
4. Build:

   ```bash
   ./build.sh
   ```

   The first run downloads and builds the PS5 toolchain (1 to 2 hours), recompiles the game
   (about 5 minutes) and builds the title. Later runs reuse all of that. The result is
   `dist/PPSA99777/`, with your game files already inside it as `Dirt 2/`.

   Steps can also be run alone: `./build.sh toolchain`, `./build.sh lift`, `./build.sh title`.
   Set `NO_GAME=1` to leave the game files out of `dist/`.

## Install on the console

1. Copy `dist/PPSA99777` to `/data/homebrew/PPSA99777` with FTP (about 10 GB).
2. Let ShadowMountPlus rescan, then start **DiRT 2 Recompiled** from the home screen.

Your profile, settings and log are in `/data/homebrew/PPSA99777/data/` (`dirt2.log` is the log).

## Using it

- DualSense: buttons, sticks, triggers and rumble. Menus show PlayStation button icons.
- Creating a profile opens an on-screen keyboard: Cross types, L2 switches capitals,
  Triangle is space, Square deletes, R2 confirms, Circle cancels.
- Options > Graphics > STATISTICS shows frame rate and frame-time graphs.
- Quitting from the van or the pause menu closes the game cleanly.
- The game outputs at the resolution you pick in the options (1440p works natively).

Optional switch files, empty files or one-line files in the `data/` folder:

| File | Effect |
|---|---|
| `novsync` | turn vertical sync off |
| `fpscap` | frame cap, the number inside the file (for example `30`) |
| `output` | output height: `1080`, `1440` or `2160` |
| `bench` | log extra frame-time detail |
| `profile` | write a CPU profile to the log |

## Known limits

- Races run at about 40 fps: the game's main thread is the limit, not the GPU.
- Without the shader cache, the first races stutter while shaders compile.
- No system keyboard (the console does not let titles use it); the on-screen keyboard is our own.

## How it is built

`build.sh` runs a Fedora container: it builds the PS5 toolchain from pinned revisions
(`tools/pins.env`), fetches the upstream recompilation at its pinned commit and applies the PS5
port (`ps5/patches/dirt2`, `ps5/overlay`), recompiles your executable, builds SDL3, OpenAL Soft,
FFmpeg and DXVK (`ps5/patches/dxvk`) for the console and links everything with RADV into a signed title.

See [NOTICE.md](NOTICE.md) for licences and credits.

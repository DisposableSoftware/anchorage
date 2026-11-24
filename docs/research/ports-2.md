# HarbourMasters Linux ports, part 2: Ghostship, PaperBoat, Lighthouse

Date checked: 2026-11-23. Same method as [ports.md](ports.md) and [first-run-extraction.md](first-run-extraction.md): release data from `gh api` (`releases/latest` and the last 10 releases), the Linux assets downloaded with `gh release download` into empty folders, zips listed and unpacked, AppImage squashfs unpacked with `unsquashfs -o <offset>` (static, nothing run), and source read from the release tag tarballs (`gh api repos/<repo>/tarball/<tag>`). The libultraship (LUS) and Torch files were read at the commits each tag pins. Work dir: `/tmp/claude-1000/-home-weston-Developer-disposable/c99b45bc-1f45-4751-a314-fb523b5d8f4e/scratchpad/ports-research2/`. Afterwards, the three releases were installed and started through Anchorage in the sandboxed end-to-end run (`scripts/manual/e2e.sh`, see the end).

## Summary

- All three are LUS ports. On Linux `SHIP_HOME=<dir>` sets the data folder (LUS `Context::GetAppDirectoryPath`, checked at each pin); without it the data folder is the working directory, except Lighthouse 1.2.x from an AppImage, which then uses `$XDG_DATA_HOME/lighthouse` (or `~/.local/share/lighthouse`) unless the AppImage's folder already has `lighthouse.cfg.json` or `bk.o2r`. Lighthouse also changes its working directory to `SHIP_HOME` when it is set.
- None reads a ROM from a zip, and none byte-swaps: the ROM SHA1 is taken over the raw file (Torch `Companion::CalculateHash`, a plain SHA1), and the folder scans look for `*.z64` only. Lighthouse rejects `.v64`/`.n64` data outright ("Convert it to .z64"). Anchorage's rule (always write a big-endian `.z64`, `ROM-8`) fits all three.
- Only Lighthouse uses ROM paths on the command line on Linux (`extractStep = args.empty() ? ES_EXTRACT : ES_EXTRACT_ARGS`, as SoH). Ghostship 3.0.0 and PaperBoat 1.0.3 collect argv but reach `ES_EXTRACT_ARGS` only through the Windows-only `ES_WINDOWS` steps, so on Linux an argument is ignored. Both scan the app bundle folder and the data folder for `*.z64` files with a supported SHA1 after "Generate one now?".
- Generated archives: `sm64.o2r` (Ghostship), `pm64.o2r` (PaperBoat), `bk.o2r` (Lighthouse), all in the data folder. Bundled port archives: `ghostship.o2r`, `paperboat.o2r`, `lighthouse.o2r` (inside the AppImages).
- Every prompt is an ImGui popup. Gamepad navigation in popups needs the CVar `gSettings.ControlNav` (default 0 on Linux) in PaperBoat's and Lighthouse's LUS; Ghostship's older LUS pin only enables gamepad navigation while the menu is open, never for popups. So a fresh install needs a mouse or keyboard once for Ghostship and PaperBoat; Lighthouse extracts without asking when given the ROM, then asks "Run Lighthouse?".
- Every asset of the three latest releases has a `sha256:` digest in the API.

## Release and asset table

| | Ghostship (Super Mario 64) | PaperBoat (Paper Mario) | Lighthouse (Banjo-Kazooie) |
|---|---|---|---|
| Repo | `HarbourMasters/Ghostship` | `HarbourMasters/PaperBoat` | `HarbourMasters/Lighthouse` |
| Latest tag (latest endpoint) | `3.0.0` (2026-09-07) | `1.0.3` (2026-10-11) | `1.2.2` (2026-10-30) |
| Linux asset | `Nautilus-Alfa-Linux.zip` (18060413 B) | `Paperboat-Mulberry-Delta-Linux.zip` (21437464 B) | `lighthouse.appimage` (bare AppImage, 13669568 B) |
| Digest | `sha256:f295cb24bfd78660a9caa834e267cc009b4ccdb4ebe68005ab677dc5e4417e83` (matches the download) | `sha256:f6c72564e8c1485df6022aed24e33c5122815c9c6c90589411f3fbd23e56ffa2` (matches) | `sha256:f5edff0f690e476eedff7c05ad9fefeb4de173466af6de61c2729d9276aa73b6` (matches) |
| Name history | 3.0.0 `Nautilus-Alfa-*`, 2.0.0 `Mary-Celeste-Alfa-*`, 1.0.1/1.0.2 `Ghostship-Dutchman-*-Linux.zip`; 1.0.0 had no Linux asset. The product name is not in the 2.0.0+ names. | `Paperboat-Mulberry-<Greek>-Linux.zip` for 1.0.0 .. 1.0.3 | 1.2.0 .. 1.2.2 bare `lighthouse.appimage`; 1.0.x and 1.1.0 were `Lighthouse-<Codename>-<Greek>-Linux.zip` |
| Suffix to match | `-linux.zip` (one match per release) | `-linux.zip` | `.appimage` (the only `.appimage`; Mac and Win64 are zips). A return to `-Linux.zip` would need a catalog change, as for SoH. |
| Other assets | Android, iOS, Mac, Win64 zips (Switch in 2.0.0) | Mac, Win64 | Mac, Win64 zips |
| Prerelease/draft | none in the last 10 | none | none |
| Tag style | no `v` | no `v` | no `v` |

## Archive contents and AppImages

| | Ghostship 3.0.0 | PaperBoat 1.0.3 | Lighthouse 1.2.2 |
|---|---|---|---|
| Download | zip, 859 entries: `ghostship.appimage` (0755), `config.yml`, `gamecontrollerdb.txt`, `readme.txt`, `assets/` (842 yaml files), `.tcc/` (13 files: TinyCC headers and libs for its C scripting) | zip, 3 entries: `Paperboat.AppImage` (mode 0644: NOT executable in the zip), `gamecontrollerdb.txt`, `readme.txt` | AppImage directly |
| Inside the AppImage `usr/bin` | `Ghostship`, `ghostship.o2r`, `assets/`, `config.yml`, `.tcc/`, `include/`, `lib/` (no `gamecontrollerdb.txt`) | `Paperboat`, `paperboat.o2r`, `assets/`, `config.yml`, `include/`, `lib/` (no `gamecontrollerdb.txt`) | `Lighthouse`, `lighthouse.o2r`, `assets/`, `config.yml`, `gamecontrollerdb.txt`, `include/`, `lib/` |
| `AppRun` | symlink to `usr/bin/Ghostship` | `usr/bin/Paperboat` | `usr/bin/Lighthouse` |
| Version in the AppImage | `X-AppImage-Version=3.0.0` | `1.0.3` | `1.2.2` |
| Runtime | old AppImageKit type 2 (dlopens `libfuse.so.2`), squashfs at 193728 | static type2-runtime (no libfuse2 string), squashfs at 944632, like SpaghettiKart | old AppImageKit type 2, squashfs at 193728 |
| `APPIMAGE_EXTRACT_AND_RUN` | supported by both runtime kinds (as for the first four) | | |

Ghostship's zip also carries `config.yml`, `assets/` and `.tcc/` next to the AppImage, but the AppImage bundles all three and the code reads them from the bundle (`GetAppBundlePath()`; `.tcc` from the data folder first, then the bundle), so unlike Starship nothing but `gamecontrollerdb.txt` needs copying. PaperBoat finds `assets` and `config.yml` in the bundle as well.

## ROM handling

| | Ghostship | PaperBoat | Lighthouse |
|---|---|---|---|
| Accepted SHA1 (copied from source) | `src/port/GameExtractor.cpp` `mGameList` and `config.yml`: US `9bef1128717f958171a4afac3ed78ee2bb4e86ce` ("Super Mario 64 (US)"), JP `8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51` ("Super Mario 64 (JP)"). The README says the same two. | `config.yml` (the only list; the extractor accepts any hash with a recipe there): US `3837f44cda784b466c9a2d99df70d77c322b97a0` ("pm64"). README: "US SHA1 Hash" same value. | `src/port/Extractor/GameExtractor.cpp` `mGameList` and `config.yml`: US 1.0 `1fe1632098865f639e22c11b9a81ee8f29c75d7a` ("Banjo-Kazooie (U) (V1.0)", config "USA (Rev0)"), US 1.1 `ded6ee166e740ad1bc810fd678a84b48e245ab80` ("(U) (V1.1)", "USA (Rev1)"), PAL `bb359a75941df74bf7290212c89fbc6e2c5601fe`, JP `90726d7e7cd5bf6cdfd38f45c9acbf4d45bd9fd8`. The README lists the same four. |
| Byte order | z64 only (raw SHA1, `*.z64` scans; README: "Your ROM needs to be in .z64 format") | z64 only for the scan (raw SHA1 of `*.z64`). Its file picker offers `.n64`/`.v64`, but the SHA1 lookup is raw, so those fail | z64 only; `.v64`/`.n64` data is refused with a message |
| Zip | no | no | no |
| Where it looks | After "Generate one now?": `FindSupportedRoms` over the app bundle folder (inside the AppImage mount) and the data folder, `*.z64` with a supported SHA1; one found gives "Found Super Mario 64 (US). Generate game files from it?"; several give a picker; none gives a file picker (pfd: zenity or kdialog) | After "Generate one now?": the same scan of bundle and data folder; "ROMs found ... Generate the game files from them?"; none gives a picker: pfd, or the in-game ImGui file browser when `GAMESCOPE_WAYLAND_DISPLAY` is set or no pfd backend exists | argv (any argument that is not one of its own flags) on Linux. Without argv: "Generate one now?", then `*.z64` in the bundle and data folders, then `baserom.us.z64` and similar names in the data folder, then pfd (no fallback to the in-game browser on x86_64 Linux) |
| Output | `sm64.o2r` in the data folder | `pm64.o2r` in the data folder | `bk.o2r` in the data folder |
| After extraction | goes straight on to the game (no "Run?" popup) | "Run PaperBoat? All files have been processed" (Yes/No; No exits) | "Run Lighthouse? All files have been processed" (Yes/No; No exits) |
| Archive version check | `sm64.o2r` carries the port version; an incompatible one shows "Outdated ROM Archives", is deleted and extraction starts again (and the menu's "Regenerate Game Assets" leaves a `regenerate_o2r` marker) | none in 1.0.3: an old `pm64.o2r` is used as it is | `bk.o2r` carries the port version; an incompatible one is deleted after an "Outdated ROM Archives" popup |
| With argv and an archive present | (argv ignored on Linux) | (argv ignored on Linux) | "Confirm Re-extract" popup, as SoH (so `PORT-16` must not pass the ROM while an archive is there) |

Real ROMs in the sandbox (`sha1sum` of the zip entries): `Super Mario 64 (USA).z64` = `9bef1128...` (US), `Paper Mario (USA).z64` = `3837f44c...`, `Banjo-Kazooie (USA) (Rev-A).z64` = `ded6ee16...` (US 1.1). All three are big-endian (`80 37 12 40`). None of the seven ports' hash lists share a hash.

## Data folder, config, launch

| | Ghostship | PaperBoat | Lighthouse |
|---|---|---|---|
| LUS pin | Kenix3/libultraship `6b861a6` | JeodC/libultraship `7f1bd60` (branch `lus-converge`, a fork) | Kenix3/libultraship `e175b95` |
| Torch pin | `106621f` | `72960ca` | `7f5d55f` |
| Data folder | `SHIP_HOME`, else cwd | `SHIP_HOME`, else cwd | `SHIP_HOME`; else from an AppImage `$XDG_DATA_HOME/lighthouse` (see summary); else the executable's folder. It `chdir`s to the data folder |
| cwd needs | none with `SHIP_HOME` | none | none (it changes it itself) |
| Extra files | `gamecontrollerdb.txt` (not bundled) | `gamecontrollerdb.txt` (not bundled) | none (bundled) |
| CLI flags | none found besides argv | none found | its own `IsLaunchHackFlag`/frame-host flags; everything else is a ROM path |
| Env vars read | `SHIP_HOME` (LUS), `TEMP`/`USERPROFILE` on Windows | `SHIP_HOME`, `GAMESCOPE_WAYLAND_DISPLAY` (picker choice) | `SHIP_HOME`, `APPIMAGE`, `XDG_DATA_HOME`, `HOME` |
| Config file | `ghostship.cfg.json` (README calls it `Ghostship.cfg.json`) | `paperboat.cfg.json` | `lighthouse.cfg.json` |

Catalog consequences: all three run with `cwd: data` and `SHIP_HOME` = the data folder. Ghostship and PaperBoat get the ROM in the data folder (`rom_place: data_dir`), Lighthouse as an argument (`rom_place: argv`). Ghostship and PaperBoat copy `gamecontrollerdb.txt` (`extra_files`).

## First launch, gamepad and Steam Deck

- Ghostship 3.0.0 (ROM in the data folder): "No O2R Files: Generate one now?" then "ROM found: Found Super Mario 64 (US). Generate game files from it?", both ImGui; then extraction with a progress popup and straight into the game. LUS `6b861a6` `Gui.cpp` sets `NavEnableGamepad` only when `ControlNav` is on AND the menu is visible, so even a pre-set CVar does not make these popups gamepad-driven. Needs a mouse, trackpad or keyboard once.
- PaperBoat 1.0.3 (ROM in the data folder): "Generate one now?", "ROMs found ... Generate the game files from them?", extraction, "Run PaperBoat?". Its LUS `UpdateGamepadNavigation` turns gamepad navigation on for any open popup when `gSettings.ControlNav` is 1 (default 0). Needs a mouse, trackpad or keyboard once unless the CVar is pre-set (not done, unverified, as for SoH).
- Lighthouse 1.2.2 (ROM as argument): extracts at once with a progress popup, then "Run Lighthouse?" (same LUS popup rule as PaperBoat). Same note as Shipwright: close it and press Play again.
- All three LUS pins have the Steam Deck game-mode detection (`/etc/os-release` `VARIANT_ID` contains `steamdeck` and `XDG_CURRENT_DESKTOP=gamescope`: fullscreen at 1280×800 by default).
- PaperBoat avoids the native file picker under gamescope (`GAMESCOPE_WAYLAND_DISPLAY`) and opens LUS's in-game ImGui file browser instead; Ghostship and Lighthouse would call zenity/kdialog. With the ROM placed or passed, no picker is reached.

## Card text for `first_run` (PORT-17)

- Ghostship: "The first launch needs a mouse or keyboard once (the trackpad works): answer Yes twice\nLater launches do not"
- PaperBoat: "The first launch needs a mouse or keyboard once (the trackpad works) to answer its questions\nLater launches do not"
- Lighthouse: the Shipwright note, "The first launch makes the game files from your ROM\nIf it then asks to run the game, close it and press Play again"

## End-to-end run through Anchorage

`ONLY="ghostship paperboat lighthouse" LAUNCH_SECONDS=240 ANSWERS=4 RUNNER=steam-run scripts/manual/headless.sh scripts/manual/e2e.sh` at 1920×1080, 2026-11-23, with the ROM zips copied from the sandbox (0 checks failed). On this NixOS host binfmt hands every AppImage to `appimage-run`, so `APPIMAGE_EXTRACT_AND_RUN` itself was not exercised.

- Install: Ghostship first, PaperBoat and Lighthouse queued behind it; all three downloaded from GitHub with their digests, unpacked, executables 755 (PaperBoat's AppImage, 0644 in the zip, too), no `download/` left, `gamecontrollerdb.txt` in Ghostship's and PaperBoat's data folders. The real cover art loaded on all three cards; the row scrolled to the focused card.
- ROM matching: Anchorage's scan of the ROM folder (all eight zips) matched each of the seven ports to exactly its own game (`Super Mario 64 (USA).z64` → Ghostship US, `Paper Mario (USA).z64` → PaperBoat US, `Banjo-Kazooie (USA) (Rev-A).z64` → Lighthouse US 1.1, and the first four to theirs); no port claimed another's ROM. The placed copies (`sm64.z64`, `pm64.z64`, `bk.z64`) had the listed SHA1 and the `80 37 12 40` header.
- Lighthouse 1.2.2: started with `<data>/bk.z64` as its only argument, extracted at once with no question, wrote `bk.o2r` (25900760 bytes) in the data folder, then showed "Run Lighthouse? All files have been processed" (screenshot `15-lighthouse-c-after`). Anchorage deleted its placed ROM copy after the run.
- Ghostship 3.0.0 and PaperBoat 1.0.3: both started in their data folder with the ROM placed there and showed the ImGui popup "No O2R Files: No O2R files found. Generate one now?" (log: `O2R file not found at path: ./sm64.o2r`). Neither Return nor clicks on Yes (wlrctl virtual pointer, also with `XDG_CURRENT_DESKTOP=gamescope`, which turns off ImGui viewports) reached the popup in headless sway, so their extraction was not seen. Return is expected to fail (LUS never sets `NavEnableKeyboard`); the click failing is a limit of this headless setup, which has never answered an ImGui popup (the earlier runs did not either). After stopping each port, Anchorage came back with focus on its card and kept the placed ROM, because no archive was made.

## Not verified

- Ghostship's and PaperBoat's extraction (the popups could not be answered headless); the second Ghostship popup and PaperBoat's "ROMs found" and "Run PaperBoat?" are from source only.

- Nothing was run outside the sandboxed end-to-end run; no Steam Deck or gamescope session was available, so game-mode fullscreen, the gamescope file-browser switch of PaperBoat and Steam Input are from source only.
- Whether `{"CVars":{"gSettings":{"ControlNav":1}}}` pre-seeded in `paperboat.cfg.json`/`lighthouse.cfg.json` makes the popups gamepad-driven (same open question as for SoH).
- The JeodC LUS fork pinned by PaperBoat was read only for `Context.cpp`, `Gui.cpp` and `Fast3dWindow.cpp`.
- Ghostship's JP ROM, PaperBoat's only US ROM and Lighthouse's PAL and JP ROMs were not tried: only the three US ROMs in the sandbox.
- Lighthouse builds a config for romhacks it recognises (`TrySynthesizeRomConfig`) from the in-game menu; Anchorage lists only the four retail hashes.

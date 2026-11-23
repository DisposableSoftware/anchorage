# HarbourMasters Linux ports: research for Anchorage

Date checked: 2026-11-23. Release data from `gh api`; zips downloaded and listed; AppImage squashfs listed with unsquashfs (static, nothing run); source read from the release tags (Starship, SpaghettiKart, 2ship) or `develop`/`main` (SoH, noted below). Work dir: `/tmp/claude-1000/-home-weston-Developer-disposable/c99b45bc-1f45-4751-a314-fb523b5d8f4e/scratchpad/ports-research/`.

## Summary

- All four use libultraship (LUS). On Linux, `SHIP_HOME=<dir>` sets the data dir (config, o2r, saves, mods). It is honored by the LUS commit pinned in every latest release (checked each). Without it the data dir is the cwd ("."), except SoH 9.3+ AppImage, which defaults to `$XDG_DATA_HOME/soh`.
- No port accepts a ROM zip. Only SoH and 2ship byte-swap v64/n64. Starship and SpaghettiKart need big-endian .z64. Anchorage must unzip, check the extension, and convert to z64 if needed.
- No port has a "extract this ROM and exit" flag. SoH and 2ship take ROM paths as argv, then still show GUI popups. Starship v2.0.0 only has a GTK/Qt file picker (zenity or kdialog). SpaghettiKart auto-scans the cwd for `*.z64`.
- Anchorage can detect extraction by a file existing in the data dir: `oot.o2r`/`oot-mq.o2r`, `mm.o2r`, `sf64.o2r`, `mk64.o2r`. None writes a version file. Save the release tag yourself.
- Starship has not had a release since 2025-05-25 (v2.0.0). SpaghettiKart's latest is 1.0.0 (2026-02-25). The previous SpaghettiKart releases are prereleases.
- `releases/latest` returned the same tag as the first entry of the full list for all four. No draft or prerelease sits above it (prereleases only exist below Kart 1.0.0).

## Release and asset table

| | Shipwright | 2ship2harkinian | Starship | SpaghettiKart |
|---|---|---|---|---|
| Latest tag (latest endpoint) | `9.3.1` (2026-10-18) | `5.0.1` (2026-08-25) | `v2.0.0` (2025-05-25) | `1.0.0` (2026-02-25) |
| Linux asset | `SoH-Dewey-Bravo.appimage` (bare AppImage, 32113856 B) | `2Ship-Battler-Bravo-Linux.zip` (16262941 B) | `Starship-Barnard-Alfa-Linux.zip` (79980135 B) | `spaghetti-linux.zip` (12395451 B) |
| Name pattern | Changed in 9.3.0: `SoH-<Codename>-<Greek>.appimage`. <=9.2.3 was `SoH-<Codename>-<Greek>-Linux.zip` (e.g. `SoH-Ackbar-Delta-Linux.zip`). Match on `*.appimage` OR `*-Linux.zip`. | `2Ship-<Codename>-<Greek>-Linux.zip` | `Starship-<Codename>-<Greek>-Linux.zip` (also `-Switch.zip`, `-Windows.zip`) | `spaghetti-linux.zip` (fixed name). Prereleases 0.9.9/0.9.9.1 used `Spaghettify-Alfredo-Alfa[-1]-Linux[-Old].zip`. |
| Other assets | Mac.zip, Win64.zip | Mac.zip, Win64.zip | Switch.zip, Windows.zip | mac-arm64, mac-intel-x64, windows zips |
| Prerelease/draft | none in recent 6 | none in recent 6 | none | 0.9.9, 0.9.9.1 are `prerelease=true`, below 1.0.0 |
| Tag style | no `v` prefix | no `v` | `v` prefix (v1.0.0 had Windows only) | no `v` |

Version names do not sort; use the tag/`published_at`, not the asset name. Note the asset name embeds a codename that changes every minor version, so select by suffix, not exact name.

## Archive contents and AppImage facts

| | Shipwright 9.3.1 | 2ship 5.0.1 | Starship v2.0.0 | SpaghettiKart 1.0.0 |
|---|---|---|---|---|
| Download type | AppImage directly (no zip) | zip: `2ship.appimage` (mode 0755), `readme.txt` | zip: `starship.appimage` (0755), `config.yml`, `gamecontrollerdb.txt`, `readme.txt`, `assets/` (yaml extraction trees, 116 entries), `mods/` (empty dir) | zip: `spaghetti.appimage` (0755), `gamecontrollerdb.txt` |
| Zip exec bits | n/a (set chmod +x yourself) | yes, `-rwxr-xr-x` | yes | yes |
| Inside AppImage `usr/bin` | `soh.elf`, `soh.o2r`, `assets/`, `gamecontrollerdb.txt` | `2s2h.elf`, `2ship.o2r`, `assets/`, `gamecontrollerdb.txt` | `Starship`, `starship.o2r` only | `Spaghettify`, `spaghetti.o2r`, `config.yml`, `yamls/us`, `meta/mods.toml` (NO gamecontrollerdb) |
| Runtime | old AppImageKit type2 that dlopens `libfuse.so.2` | same | same | newer static `type2-runtime` (no libfuse2 string) |
| Extractable | yes: type 2, squashfs at offset 193728 (I extracted with `unsquashfs -o`). Runtime also has `APPIMAGE_EXTRACT_AND_RUN` string, and `--appimage-extract` is the standard flag. | same, offset 193728 | same, offset 193728 | yes, offset 944632 |
| Needs FUSE | yes by default (libfuse2 + /dev/fuse). `/dev/fuse` exists here but libfuse2 is not checked. On NixOS set `APPIMAGE_EXTRACT_AND_RUN=1` or extract once and run `AppRun` (symlink to the elf). | same | same | needs fusermount; has extract-and-run too |
| `AppRun` | symlink to `usr/bin/soh.elf` | `usr/bin/2s2h.elf` | `usr/bin/Starship` | `usr/bin/Spaghettify` |
| Version in AppImage | `soh.desktop` has `X-AppImage-Version=9.3.1` | not checked | not checked | not checked |

I did NOT execute any AppImage (the harness blocked it; correct per untrusted-download rule). So extract-and-run behavior, the `APPIMAGE` env value under extract-and-run, and actual launch are unverified. Everything about runtime behavior is from source.

Important Starship quirk: the zip's `config.yml` and `assets/` are NOT inside the AppImage. In v2.0.0 the extractor (Torch) reads `config.yml` and `assets/` from the cwd and writes `sf64.o2r` to the cwd (relative path from config.yml). So for the first run, cwd must be the unzipped folder, and `SHIP_HOME` must be unset or equal to that folder (the game then looks for `sf64.o2r` in `SHIP_HOME`). I confirmed this from v2.0.0 `Engine.cpp` and Torch commit f75facb. Keep the whole zip contents together.

## ROM handling

| | Shipwright (OoT) | 2ship (MM) | Starship (SF64) | SpaghettiKart (MK64) |
|---|---|---|---|---|
| Accepts ROM .zip | NO. Extractor rejects `PK\3\4` ("compressed" error). Also rejects rar/7z. | NO (same `ValidateNotCompressed`) | NO. No unzip code; no byte swap either. | NO (only `*.z64` scanned) |
| Byte order | z64, n64, v64 all OK (`RomToBigEndian`). Size must be 32, 54 or 64 MB. | z64/n64/v64 OK (`RomToBigEndian`) | z64 only. README says convert. SHA1 computed over raw bytes with no swap. | z64 only (same raw SHA1; scan is `*.z64`) |
| Validation | header word at 0x10 ("CRC1") vs table, not SHA1. SHA1 list below is the official one (`docs/supportedHashes.json`). | CRC1 `0x5354631C` (US 1.0), `0xB443EB08` (US GC) | SHA1 of file | SHA1 of file |
| Where it looks | Scans top level of (a) app bundle dir (inside the AppImage mount, so effectively nothing) and (b) the data dir, for `.z64 .n64 .v64`. Else file dialog (pfd). | Same logic (app dir, then data dir), `.z64 .n64 .v64`; else file dialog | File dialog only (`pfd::open_file` starting at "."); no scan. Needs zenity or kdialog. | Scans the CURRENT WORKING DIRECTORY (not SHIP_HOME) for `*.z64`, takes the first one with a valid SHA1; else file dialog |
| CLI ROM arg | YES: every argv entry is treated as a ROM path (`RunFileStandalone`) | YES (same) | no | no |
| Output file | `oot.o2r` (vanilla) / `oot-mq.o2r` (Master Quest) in data dir | `mm.o2r` in data dir | `sf64.o2r` in cwd (see quirk), loaded from SHIP_HOME/cwd | `mk64.o2r` in data dir (`SHIP_HOME` or cwd) |
| Extra archives | `soh.o2r` bundled in AppImage | `2ship.o2r` bundled | `starship.o2r` bundled; JP/EU voice packs are optional, installed from Settings->Language | `spaghetti.o2r` bundled |
| After extraction | Popup "Run SoH?" (needs a click/controller confirm) when launched with ROM args | continues to game once `mm.o2r` exists | prompts "Extract another?" | continues to game |

Supported SHA1 hashes:

- **OoT (19 entries, `docs/supportedHashes.json`)**: PAL 1.0 `328a1f1beba30ce5e178f031662019eb32c5f3b5`; PAL 1.1 `cfbb98d392e4a9d39da8285d10cbef3974c2f012`; PAL GC `0227d7c0074f2d0ac935631990da8ec5914597b4`; PAL MQ `f46239439f59a2a594ef83cf68ef65043b1bffe2`; PAL GC Debug `cee6bc3c2a634b41728f2af8da54d9bf8cc14099`; PAL MQ Debug `079b855b943d6ad8bd1eb026c0ed169ecbdac7da`, `50bebedad9e0f10746a52b07239e47fa6c284d03`, `cfecfdc58d650e71a200c81f033de4e6d617a9f6`; NTSC-U 1.0 `ad69c91157f6705e8ab06c79fe08aad47bb57ba7`; NTSC-U 1.1 `d3ecb253776cd847a5aa63d859d8c89a2f37b364`; NTSC-U 1.2 `41b3bdc48d98c48529219919015a1af22f5057c2`; NTSC-J 1.0 `c892bbda3993e66bd0d56a10ecd30b1ee612210f`; NTSC-J 1.1 `dbfc81f655187dc6fefd93fa6798face770d579d`; NTSC-J 1.2 `fa5f5942b27480d60243c2d52c0e93e26b9e6b86`; NTSC-U GC `b82710ba2bd3b4c6ee8aa1a7e9acf787dfc72e9b`; NTSC-U MQ `8b5d13aac69bfbf989861cfdc50b1d840945fc1d`; NTSC-J GC `0769c84615422d60f16925cd859593cdfa597f84`; NTSC-J GC Collector's `2ce2d1a9f0534c9cd9fa04ea5317b80da21e5e73`; NTSC-J MQ `dd14e143c4275861fe93ea79d0c02e36ae8c6c2f`. The source (`GameVersions.h`) also lists iQue TW/CN CRCs, but they are absent from the SHA1 doc; I did not confirm that iQue is accepted.
- **MM (`docs/supportedHashes.json`)**: NTSC-U 1.0 `d6133ace5afaa0882cf214cf88daba39e266c078`; NTSC-U GC `9743aa026e9269b339eb0e3044cd5830a440c1fd`. Only the US versions.
- **SF64 (source `mGameList`, v2.0.0 plus one HEAD addition)**: US 1.0 `d8b1088520f7c5f81433292a9258c1184afa1457` (and uncompressed `63b69f0e...`); US 1.1 `09f0d105f476b00efa5303a3ebc42e60a7753b7a` (uncompressed `f7475fb1...`); JP 1.0 `9bd71afbecf4d0a43146e4e7a893395e19bf3220`; EU 1.0 `05b307b8804f992af1a1e2fbafbd588501fdf799`; CN 1.1 `c8a10699dea52f4bb2e2311935c1376dfb352e7a`. The README says the base asset archive must come from a US ROM (US 1.0 or 1.1); JP/EU are for voice replacement only. Treat only US 1.0/1.1 as supported for install.
- **MK64**: one hash only, US `579c48e211ae952530ffc8738709f078d5dd215e`.

## Data dir, config, launch

| | Shipwright | 2ship | Starship | SpaghettiKart |
|---|---|---|---|---|
| Data dir | `SHIP_HOME` if set; else (when `APPIMAGE` env is set and none of `shipofharkinian.json`, `oot.o2r`, `oot-mq.o2r` is in the cwd) `$XDG_DATA_HOME/soh` or `~/.local/share/soh`; else cwd | `SHIP_HOME`, else cwd (no AppImage/XDG logic in 5.0.1) | `SHIP_HOME`, else cwd | `SHIP_HOME`, else cwd |
| Config file | `shipofharkinian.json`, `cvars.cfg`-style files in data dir | `2ship2harkinian.json` | `starship.cfg.json` | `spaghettify.cfg.json` |
| Saves | `<data>/Save/` | `<data>/saves/` | not checked | not checked |
| Mods | `<data>/mods/` (`.otr`/`.o2r`) | `<data>/mods/` | `<data>/mods/` | `<data>/mods/` |
| Logs | `<data>/logs/` | same | same | same |
| Env vars | `SHIP_HOME` (also honored when `~` prefixed only on macOS). Other: `XDG_DATA_HOME`. I found NO `SHIP_BIN_DIR` in any source. | `SHIP_HOME` | `SHIP_HOME` | `SHIP_HOME` |
| CLI flags | none except ROM paths | none except ROM paths | none found | none found |
| cwd needed | no, if `SHIP_HOME` set (bundled files come from the AppImage mount) | no | yes for first-run extraction (config.yml, assets/); see quirk | yes for ROM scan (must contain the `.z64`); otherwise no |
| gamecontrollerdb | bundled in AppImage | bundled | NOT bundled; zip has it next to the AppImage | NOT bundled; zip has it |

LUS lookup order for `gamecontrollerdb.txt`, `soh.o2r`-style files: data dir, then app bundle dir (inside AppImage), then `./<name>`. So for Starship and Kart, copy `gamecontrollerdb.txt` into the data dir (or run with that cwd).

Recommended per-port layout under `$XDG_DATA_HOME/anchorage/<port>/`: keep `app/` (the AppImage, and for Starship the zip contents), and `data/` as `SHIP_HOME`. Launch: `cd <dir> && SHIP_HOME=<data> APPIMAGE_EXTRACT_AND_RUN=1 ./x.appimage`. Exception: Starship v2.0.0 first run (cwd = folder with `config.yml`, `assets/`, SHIP_HOME = that same folder, so `sf64.o2r` is found), and Kart extraction (cwd must hold the unzipped `.z64`, and `SHIP_HOME` then gets `mk64.o2r`).

For SoH/2ship, pass the unzipped ROM as argv for first run: `SHIP_HOME=<data> ./soh.appimage /path/rom.z64`. This opens a window and extracts; SoH then shows "Run Ship of Harkinian?" which needs a confirm. Alternative: place the ROM in `<data>` and launch with no args: it shows "ROMs found in application directory. Process them?" The unattended path is not possible. A file dialog (zenity/kdialog via pfd) is the fallback and may not exist on NixOS or gamescope.

## Detection

| | extraction done | installed version |
|---|---|---|
| SoH | `<data>/oot.o2r` or `oot-mq.o2r` | No version file. `X-AppImage-Version` in the AppImage .desktop (9.3.1). The o2r records the port version and SoH deletes outdated `oot*.o2r` itself on major-version change ("Outdated ROM Archives" popup, then re-extract), so after a major update the launcher should expect re-extraction. Use the saved release tag. |
| 2ship | `<data>/mm.o2r` (also auto-regenerated on version mismatch) | saved tag |
| Starship | `sf64.o2r` in SHIP_HOME/cwd | saved tag |
| Kart | `<data>/mk64.o2r` | saved tag |

## Controllers and Steam Deck

- LUS reads `gamecontrollerdb.txt` and uses SDL GameController. Bundled in SoH and 2ship AppImages; for Starship/Kart copy it from the zip.
- LUS has Steam Deck detection: `/etc/os-release` has `VARIANT_ID` containing `steamdeck` AND `XDG_CURRENT_DESKTOP=gamescope`. Then it forces fullscreen at 1280x800 by default ("game mode") and disables ImGui viewports (viewports are also disabled on any `XDG_CURRENT_DESKTOP=gamescope`). On a non-Deck gamescope session, fullscreen is not forced; set `Window.Fullscreen.Enabled` in the port's JSON config or pass gamescope `-f`.
- Default pad maps (Starship/Kart): A=A, B=X, Start=Start, C-buttons on Y/B and right stick, Z/L on shoulders. Kart L on left shoulder, R on right trigger. Menus accept controller input in the extraction prompts (LUS starts SDL game controller early).
- Steam Input in gamescope presents a virtual Xbox-style pad, which works with SDL mappings. Not verified on hardware.
- File dialogs (Starship, Kart fallback) will not be usable from game mode; avoid by pre-placing ROMs (Kart cwd scan; SoH/2ship argv or data dir).

## Not verified

- No binary was run (blocked), so: FUSE failure modes, `APPIMAGE` env under extract-and-run, window/popup behavior, gamescope behavior, and where `X-AppImage` data goes are from source/static inspection only.
- SoH/2ship/Kart source was read from the default branch HEAD for some files (SoH 43 commits and 2ship 128 and Kart 60 ahead of the release tag). I confirmed the key SoH `SetAppImageHome` is present in the 9.3.1 tag, 2ship 5.0.1 lacks it, and Kart's 1.0.0 extractor/engine files were read at the tag. The SoH and 2ship extractors were read at HEAD; hash tables are from the release tag for 2ship and docs at HEAD for SoH.
- Starship save and mod paths were not checked; Kart saves not checked. `SHIP_HOME` semantics for those two are via LUS only.
- iQue OoT acceptance and which SoH hashes exist in older 9.2.x zips were not checked. 2ship hashes at tag 5.0.1 (CRC) match HEAD.
- Whether Starship HEAD (99 commits past v2.0.0, now passes asset/data paths to Torch) will fix the cwd quirk is likely but unreleased.

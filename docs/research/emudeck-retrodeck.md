# EmuDeck and RetroDECK ROM discovery (research, 2026-11-23)

Legend: V = verified in source/doc quoted; U = NOT verified.

| Item | Value | Status | Source |
|---|---|---|---|
| EmuDeck settings file | `$emudeckFolder/settings.sh`; fallback `source "$HOME/emudeck/settings.sh"`; `emudeckFolder` definition not seen (vars.sh 404). Backend in `~/.config/EmuDeck/backend/`. Most likely `~/emudeck/settings.sh` (legacy) or `~/.config/EmuDeck/settings.sh` | path pattern V, exact folder U | emudeck repo functions/helperFunctions.sh, functions/all.sh (raw.githubusercontent.com/dragoonDorise/EmuDeck/main/functions/) |
| EmuDeck syntax | bash, `KEY=value` lines, `#!/usr/bin/env bash` header. Read by `grep "^key="` + `cut -d= -f2`. Written by sed `$a\KEY=value`. Whether values are quoted: U (handle both) | V/U | helperFunctions.sh |
| EmuDeck keys | `emulationPath` (default `$HOME/Emulation`), `romsPath` (default `$HOME/Emulation/roms`); `toolsPath`, `biosPath` etc: U | V for the two | helperFunctions.sh createUpdateSettingsFile |
| Values may contain `$HOME` | Defaults are written as literal `$HOME/...` in the script; whether the file stores expanded paths: U. Expand `$HOME`/`~` defensively | U | |
| EmuDeck internal | `/home/deck/Emulation/roms/<system>` | V | emudeck.github.io/file-management/steamos/file-management |
| EmuDeck SD | `/run/media/mmcblk0p1/Emulation/roms/<system>` (wiki wording "may be"). Community: `/run/media/deck/<label-or-uuid>/Emulation/roms/<system>` | wiki V, deck/<label> secondhand | same page; gardinerbryant.com guide |
| SD detection in EmuDeck | `getSDPath`: for dev in `/dev/mmcblk*p1 /dev/sd*1`, `findmnt -n --raw --evaluate --output=target -S $dev` | V | helperFunctions.sh |
| N64 folder | `n64`; disc drive `n64dd` | V (ROM tree on file-management page) | same page |
| Layout | `Emulation/roms/<system>`; alias symlinks exist (`gc -> gamecube`, `n3ds -> 3ds`) | V | same page |
| `~/Emulation` symlink when on SD | NOT found in source. Wiki says only users may symlink folders (cross-partition ok). Treat `~/Emulation` as a possible symlink; follow it | U | |
| RetroDECK default home | `~/retrodeck` (shipped template: `/home/deck/retrodeck`), roms `~/retrodeck/roms`. Docs call location "dynamic, chosen by user" | template V | github.com/RetroDECK/RetroDECK config/retrodeck/retrodeck.json; retrodeck.readthedocs.io wiki_management/retrodeck-folders |
| RetroDECK SD | user picks at first run or in Configurator "Move RetroDECK folder"; `sdcard` key defaults `/run/media/mmcblk0p1`. Resulting `<sd>/retrodeck/roms` is the expected layout (not seen in docs verbatim) | default V; resulting dir U | retrodeck.json; global-variables doc |
| RetroDECK config, new | `retrodeck.json` exists in repo at config/retrodeck/. JSON: `{"version":"","paths":{"rd_home_path":..., "roms_path":..., "saves_path":..., "bios_path":..., "sdcard":...},"options":{...},"presets":{}}`. Keys are `rd_home_path`, `roms_path`, `sdcard` (NOT `rdhome`/`roms_folder`) | repo template V; installed location U (presumably `~/.var/app/net.retrodeck.retrodeck/config/retrodeck/retrodeck.json`) | raw.githubusercontent.com/RetroDECK/RetroDECK/main/config/retrodeck/retrodeck.json |
| RetroDECK config, old | `~/.var/app/net.retrodeck.retrodeck/config/retrodeck/retrodeck.cfg`, key names `rdhome`, `roms_folder`, `sdcard`; format not documented (historically `key=value`, `[paths]` section: U). Docs still describe `$rd_conf=$XDG_CONFIG_HOME/retrodeck/retrodeck.cfg` | path V, format U | retrodeck.readthedocs.io global-variables, folders-filepaths |
| RetroDECK N64 | `roms/n64` (follows ES-DE structure; folder page cites gb, snes, psx; n64 by ES-DE convention) | ES-DE rule V; literal `n64` not read in a RetroDECK page | retrodeck-folders doc |
| Flatpak sandbox | Config lives under `~/.var/app/net.retrodeck.retrodeck/` (readable unsandboxed). Permissions list not fetched: U | | |
| SD mount name | SteamOS 3.4+ reportedly mounts at `/run/media/deck/<LABEL or UUID>`; old `/run/media/mmcblk0p1` still the default in EmuDeck/RetroDECK docs/defaults. Current stable/beta behaviour NOT verified | U | overkill.wtf SteamOS 3.4; steamcommunity thread 3727323242807450733 |
| Filesystem case | ext4 case-sensitive; exFAT/FAT case-insensitive. Valve formats cards ext4. Not from EmuDeck docs | general knowledge | |
| ROM file types | Zipped `.z64/.n64/.v64` in n64 folders is typical (ES-DE accepts .z64 .n64 .v64 .zip .7z); not verified here | U | |

## Recommended detection algorithm (ordered)
1. Env override / Anchorage config path, if set. Stop.
2. EmuDeck settings: for f in `~/emudeck/settings.sh`, `~/.config/EmuDeck/settings.sh` (first existing). Parse lines matching `^\s*(export\s+)?(romsPath|emulationPath)=(.*)$`; strip one layer of `'`/`"`; expand leading `~` and `$HOME`/`${HOME}`; do NOT source the file. Candidate = `romsPath`, else `emulationPath/roms`. Append `/n64`. Keep if it is a directory (follow symlinks).
3. RetroDECK config in `~/.var/app/net.retrodeck.retrodeck/config/retrodeck/`: try `retrodeck.json` (`.paths.roms_path`, else `.paths.rd_home_path + /roms`), then `retrodeck.cfg` (line `roms_folder=`, else `rdhome=` + `/roms`; tolerate quotes and `key = value`). Append `/n64`. Also check `.paths.sdcard`-derived `<sdcard>/retrodeck/roms/n64`.
4. Default paths (check existence, follow symlinks): `~/Emulation/roms/n64`, `~/retrodeck/roms/n64`.
5. SD card scan: every mount under `/run/media/*/` (both `/run/media/mmcblk0p1` and `/run/media/deck/*`), and `/run/media/<user>/*`; test `<mnt>/Emulation/roms/n64` and `<mnt>/retrodeck/roms/n64`. Optionally parse /proc/self/mountinfo instead of globbing.
6. Collect all hits; prefer the first from steps 2-3; offer the rest in the UI. Match n64 dir name case-insensitively (exFAT-safe) and extensions case-insensitively; also accept `n64dd` only if explicitly wanted.

## Verified later (2026-11-23, from the tools' source on GitHub)
- EmuDeck `vars.sh` line 2: `emudeckFolder="$HOME/.config/EmuDeck"`, so the current settings file is `~/.config/EmuDeck/settings.sh`; `functions/all.sh` still falls back to `source "$HOME/emudeck/settings.sh"`. `~/.config/EmuDeck/backend/` is the backend code (`emudeckBackend`), not the settings. ([vars.sh](https://github.com/dragoonDorise/EmuDeck/blob/main/vars.sh), [functions/all.sh](https://github.com/dragoonDorise/EmuDeck/blob/main/functions/all.sh))
- EmuDeck `createUpdateSettingsFile` builds `"romsPath=$HOME/Emulation/roms"` in double quotes, so `$HOME` is expanded when written, and `setSetting`/`changeLine` write `key=value` unquoted. Quotes and `$HOME` are still accepted, for hand-edited files. ([functions/helperFunctions.sh](https://github.com/dragoonDorise/EmuDeck/blob/main/functions/helperFunctions.sh))
- RetroDECK `functions/all_vars.sh`: `rd_conf="$XDG_CONFIG_HOME/retrodeck/retrodeck.json"`; in the Flatpak that is `~/.var/app/net.retrodeck.retrodeck/config/retrodeck/retrodeck.json`. `functions/global.sh` converts `retrodeck.cfg` to it when only the cfg exists. ([all_vars.sh](https://github.com/RetroDECK/RetroDECK/blob/main/functions/all_vars.sh), [global.sh](https://github.com/RetroDECK/RetroDECK/blob/main/functions/global.sh))
- The old `retrodeck.cfg` is INI: `[section]` lines, `#`/`;` comments, `key=value` with spaces trimmed; `[paths]` holds `rdhome` (-> `rd_home_path`), `roms_folder` (-> `roms_path`), `sdcard`. ([functions/convert_cfg_to_json.sh](https://github.com/RetroDECK/RetroDECK/blob/main/functions/convert_cfg_to_json.sh))

## Not verified
Exact `emudeckFolder` value and quoting in settings.sh (both now verified, above); whether `~/Emulation` symlink is created for SD installs; installed RetroDECK retrodeck.json/cfg location and which version switched from cfg to json; RetroDECK SD path layout; current SteamOS mount path; Flatpak override list.

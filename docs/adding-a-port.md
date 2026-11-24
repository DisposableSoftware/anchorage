# Adding a port

The port list is data: [`app/data/ports.json`](../app/data/ports.json). Adding a port is adding an entry there (`PROD-13`), with no code change. Anchorage fetches that file from `main` at start (at most once an hour) and on Refresh, so a new entry reaches users without a new release (`PORT-18` to `PORT-23`). The format is defined in the header of [`app/src/catalog.gd`](../app/src/catalog.gd); this page is the walkthrough.

**Treat a change to `ports.json` on `main` like a code change.** Every installed Anchorage trusts it: an entry names the GitHub repository whose releases get downloaded and run. Review the `repo` of every new or changed entry, and check that it is the port's real upstream.

## 1. Research the port

Before you write the entry, find out these facts from the port's latest release and source. Write them down in `docs/research/` the way [ports.md](research/ports.md) and [ports-2.md](research/ports-2.md) do.

- The GitHub repository and the Linux release asset. Use `gh api repos/OWNER/NAME/releases/latest` and look at the asset names. Codenames change with each version, so pick the part of the name that stays the same (`-linux.zip`, `.appimage`).
- What is in the asset: a bare AppImage, or a zip. For a zip, list it (`unzip -l`) and note the path of the AppImage and of any file the port needs beside it (often `gamecontrollerdb.txt`).
- Whether the port honours `SHIP_HOME` (all libultraship ports do), and the name of the archive it generates from the ROM (`oot.o2r`, `sm64.o2r`).
- How the port finds the ROM: a path on the command line, a scan of its data folder, a scan of its working directory, or only a file picker.
- What the first launch asks, and whether a gamepad can answer it.
- The accepted ROMs, from the port's source.

## 2. Find the ROM hashes

Anchorage identifies a ROM by the SHA1 of its **big-endian** (`.z64`) data. Copy the hashes from the port's source, not from a ROM you have, so that every accepted version is listed:

- The newer libultraship ports list them in the game extractor (`GameExtractor.cpp`, `mGameList`) or in `config.yml` next to the extraction recipes ([ports-2.md](research/ports-2.md) names the file for each).
- For any other port, search its source at the release tag for 40-character hex strings (`git grep -nE '[0-9a-f]{40}'`) and read the table they are in.

To check a hash against your own dump:

```sh
sha1sum "Game (USA).z64"                     # a .z64 file
unzip -p "Game (USA).zip" "Game (USA).z64" | sha1sum   # inside a zip
```

The first four bytes of big-endian data are `80 37 12 40` (`xxd -l 4 file.z64`). A `.v64` or `.n64` dump has a different byte order: Anchorage converts it before hashing, so list the `.z64` hash only. Hashes are lowercase hex. Several hashes may share one label (`"NTSC-U 1.0"`); the order of the list is the order of preference (`ROM-7`). No two ports may share a hash.

Never commit a ROM. The pre-push hook refuses ROM-like files (`scripts/check-no-roms.sh`).

## 3. Write the entry

Add the object at the end of `ports`. New ports appear after the existing cards.

```json
{
  "id": "demoport",
  "name": "Demo Port",
  "game": "Demo Game: The Subtitle",
  "description": "A PC port of Demo Game with widescreen and high frame rates.",
  "repo": "Owner/DemoPort",
  "asset_suffix": "-linux.zip",
  "archive": ["demo.o2r"],
  "launch": { "executable": "demoport.appimage", "cwd": "data", "args": [] },
  "extra_files": ["gamecontrollerdb.txt"],
  "rom_place": "data_dir",
  "rom_file": "demo.z64",
  "first_run": "First launch only: answer its questions with the trackpad or a mouse",
  "roms": [
    { "label": "US", "sha1": "0123456789abcdef0123456789abcdef01234567" }
  ]
}
```

| Field | What it is |
|---|---|
| `id` | Folder name under `ports/`. At most 32 of `a-z 0-9 _ -`. Never change it once released: installed ports are found by it. |
| `name`, `game`, `description` | Shown on the card and in the detail panel. `game` before a colon becomes the small line above the title. Plain text, no control characters. |
| `repo` | GitHub `owner/name`. Releases come from its `releases/latest`, and only assets of this repo are downloaded (`PORT-13`). |
| `asset_suffix` | The end of the Linux asset's name, compared without case. Exactly one asset of the latest release may match. |
| `archive` | The archive names the port generates. The port counts as set up when any of them is in its data folder. |
| `launch.executable` | Path inside the unpacked release. A bare AppImage asset is saved under this name. |
| `launch.cwd` | `data` (the port's data folder, best for libultraship ports) or `current` (the unpacked folder). |
| `launch.args` | Extra arguments. At most 16, each of letters, digits and `. _ = : , + -`. They are passed as separate arguments, never through a shell. |
| `extra_files` | Files or folders from the unpacked release that the port needs in its data folder. |
| `rom_place` | Where Anchorage writes the ROM before launch: `data_dir` (the data folder), `cwd` (the working directory), or `argv` (the data folder, and the path is passed as an argument until the archive exists; use it when the port extracts without asking when given a path). |
| `rom_file` | File name of the written ROM, ending in `.z64`. |
| `roms` | `{label, sha1}` per accepted ROM, in order of preference. |
| `first_run` | Optional. What the first launch needs, shown until the archive exists. At most three short lines (`\n`), no full stop. |
| `monogram` | Optional. The card's short name when the one built from the title is wrong (`PM64`). At most 5 characters. |
| `art` | Optional. `{url, author, source, style}`: a 920×430 grid from `cdn2.steamgriddb.com` (see [art.md](../spec/art.md)). |

Paths (`executable`, `archive`, `extra_files`, `rom_file`) are plain relative names: letters, digits and `. _ + -`, parts separated by `/`, no part starting with `.` or `-`. Anything else is refused.

## 4. Bump `version`

Raise the top-level `version` by one in the same commit. An app replaces an entry it already knows only when the fetched `version` is higher than the one it uses, so a fix to an existing entry without a bump never arrives. Adding a new port works without a bump, but bump anyway.

Leave `schema` alone. It changes only when the format changes in a way older apps cannot read; then the code change raises `Catalog.SCHEMA` too. An entry with a field or a `rom_place` the running app does not know is skipped there as "needs a newer Anchorage", so new optional fields lock out older apps for that entry only.

## 5. Test it

```sh
scripts/test.sh          # test_catalog: the shipped file is valid; test_catalog_update: the fetched checks
```

To see the new card in a running app before it is on `main`, serve your `ports.json` from this machine and point Anchorage at it with `ANCHORAGE_CATALOG_URL`. This is a test hook: it takes only `http://127.0.0.1:<port>/...` or an `https://raw.githubusercontent.com/...` URL (for a branch on a fork), and the release checks and downloads still go to GitHub.

```sh
python3 -m http.server 8123 --bind 127.0.0.1 --directory app/data &
ANCHORAGE_CATALOG_URL=http://127.0.0.1:8123/ports.json godot --path app
```

Press Refresh (`F5` or <kbd>X</kbd>) if the last fetch was less than an hour ago. The new card appears at the end of the row with a `New` badge, and a short notice names it. Use a scratch `XDG_CACHE_HOME` and `XDG_STATE_HOME` so your own cache and state stay clean. `scripts/manual/catalog.sh` does all of this in a headless sway with a sandboxed HOME, and also checks that a hostile entry is refused.

Then install the port from the card, launch it, and check the first launch and the ROM placement as `scripts/manual/e2e.sh` does for the shipped ports (`ONLY=demoport`).

## 6. Update the docs

Add the port to the README's "Supported ports" table and, if the shipped list in `PORT-1` changes, to that row and `test_catalog`. Commit the catalog change with a `Spec:` trailer naming `PORT-1`.

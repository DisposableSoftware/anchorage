# Roadmap

The order of approved work: `planned` requirements, and `partial` ones with a known bug from `/bug`. Change it here when priorities change. `/implement` works through this file: the verification backlog first, then the requirements in the order listed.

## MVP

1. **Foundation (parallel):**
   - Look and UI shell: `LOOK-2`, `LOOK-3`, `LOOK-5`, `LOOK-6`, `LOOK-8`, `CONF-6`, `CONF-7`, `KEY-6`, `HOME-1`, `HOME-2`, `HOME-3`, `HOME-4`, `HOME-5`, `HOME-6`, `HOME-7`, `HOME-8`, `HOME-9`, `HOME-11`, `HOME-12`, `HOME-13` against `ports_fake.gd`.
   - Catalog, releases, install, update, remove, state: `PORT-1`, `PORT-2`, `PORT-3`, `PORT-4`, `PORT-5`, `PORT-6`, `PORT-7`, `PORT-10`, `PORT-11`, `PORT-13`.
   - ROMs: `CONF-8`, `ROM-1` to `ROM-9`.
2. **Integration:** the real `Ports` service (`PORT-12`, `PORT-14`), `CONF-9`, and the launcher (`PORT-8`, `PORT-9`, `HOME-10`), wired to the screen.
3. **Real-world check:** install each port from GitHub in a sandbox, prepare ROMs from the sandbox copy, launch as far as the machine allows.
4. **AppImage for SteamOS:** `INT-25`, `INT-26`, `PORT-15`. Anchorage must run as an AppImage on SteamOS, so this is part of the MVP.
5. **Cover art:** `ART-1` to `ART-7`. The catalog curation waits for the user's SteamGridDB API key (`STEAMGRIDDB_API_KEY`); the loader and card layout can be built first.
6. **ROM folder chooser:** `ROM-10` to `ROM-13`. Today the folder can only be set in `config.ini`, which a controller-only user cannot do.
7. **More ports (catalog only, `PROD-13`):** Lighthouse (Banjo-Kazooie), PaperBoat (Paper Mario 64) and Ghostship (Super Mario 64) have Linux releases. Each needs its ROM hashes, launch quirks, first-run behaviour and cover art researched, as was done for the first four.
8. **Steam install and artwork:** `INT-27` to `INT-29` and `INT-33`: custom Steam artwork (starting with concepts the user chooses from) and `scripts/install-steamos.sh`, plus the README `curl` install command (`INT-34`). Needs the release AppImage. Untestable on a real Deck from here.
9. **Polish to the family's quality bar:** `INT-42`, `INT-43`, icon, metainfo screenshots, README with screenshots, `docs/`, man-page-equivalent docs, a code review pass.
10. Later: `CONF-4` on Hyprland and gamescope.

## Verification backlog

Built requirements that are not fully verified. Clear these before starting new planned work.

None.

## Backlog

Not approved for the current work. Move an item up and give it rows when it is ready.

- **Township** (Animal Crossing, N64): in-progress HarbourMasters port, no release yet. Add to the catalog (`PROD-13`) when it has a Linux release: research its ROM hashes, launch and first-run behaviour, and curate art as for the other ports.
- **Courage Reborn** (The Legend of Zelda: Twilight Princess): in-progress HarbourMasters port, no release yet. Same steps. Twilight Princess is a GameCube and Wii game, so its ROM folder and file types (ISO, RVZ, WBFS) are not N64's: the ROM scan (`ROM-1`, `ROM-2`) and the `[roms] directory` setting would need per-port folders or extensions first.
- **Self-update of the AppImage:** Anchorage updates itself the way it updates ports, replacing the file in `~/Applications/` so the Steam shortcut and artwork stay valid. Needs rows and the install script first.

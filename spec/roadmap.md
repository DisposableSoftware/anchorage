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
5. **Polish to the family's quality bar:** `INT-42`, `INT-43`, icon, metainfo screenshots, README with screenshots, `docs/`, man-page-equivalent docs, a code review pass.
6. Later: `CONF-4` on Hyprland and gamescope.

## Verification backlog

Built requirements that are not fully verified. Clear these before starting new planned work.

None.

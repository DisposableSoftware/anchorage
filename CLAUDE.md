# Anchorage

A controller-first launcher for the HarbourMasters game ports, for Steam OS game mode. Display name **Anchorage**, binary `anchorage`, app ID `io.github.DisposableSoftware.Anchorage`.

**What the app does is defined in [`spec/`](spec/README.md).** This file covers how to work on it.

## Spec-first workflow (mandatory)

Every change follows these steps, in order. Three skills run them. `/feature` (`.claude/skills/feature/`) turns a request into spec rows, and `/bug` (`.claude/skills/bug/`) reproduces a bug and finds the spec gap that let it happen. Both end by asking the user to **approve and implement** or **approve the spec only**, and neither writes code itself. `/implement` (`.claude/skills/implement/`) builds what is approved: it works through `spec/roadmap.md`, the verification backlog first and then the listed rows in order, with one commit per requirement.

1. **Spec.** Before touching code, update the relevant `spec/*.md`.
   - **New behaviour or a changed requirement:** add or edit a requirement row. A new row gets the next free ID in its prefix, with status `planned`. If the request is unclear, settle the wording with the user before coding.
   - **Bug fix:** find the requirement the bug breaks. If no requirement covers the behaviour, the bug is a gap in the spec, so add one.
   - **Refactor with no behaviour change:** no spec edit, but it must still pass step 3.
   - Commit the spec change on its own, before the code: `spec: <summary>`.
2. **Code.** Implement only what the spec says. If the code needs behaviour the spec doesn't describe, go back to step 1.
3. **Confirm against the spec.** Before the code commit:
   - Run `scripts/test.sh`. It includes `app/tests/test_spec.gd`, which checks the keybinding and config tables in the spec against the code and the example files.
   - For every requirement ID touched, verify it as its **Verified by** column says (unit test, or a manual or screenshot check, headless by default). Prefer adding a unit test where one is possible.
   - Re-read the changed code against the requirement text and look for behaviour the spec doesn't mention.
   - Update the row: set the status to `done` (or `partial` with the gap written in), and fill in **Verified by**. Update `roadmap.md` if a planned item landed.
4. **Commit** the code with a `Spec: ID, ID` trailer listing the requirements it implements or affects, and tell the user which IDs were verified and how.

When reporting to the user, say plainly if something could only be partly verified (e.g. the check needs Hyprland and the user had the app open, so the manual test was skipped).

## Commands

```bash
nix develop                    # devshell: godot, gdtoolkit (gdlint, gdformat)
godot --path app               # run the app (opens a window); `godot --path app -e` opens the editor
scripts/test.sh                # unit tests + spec conformance tests (headless)
cd app && gdlint src tests && gdformat --check src tests    # must pass; `gdformat src tests` fixes
nix build                      # package -> ./result/bin/anchorage (also runs the tests)
scripts/build-appimage.sh      # AppImage for SteamOS -> dist/Anchorage-X.Y.Z-x86_64.AppImage (INT-25)
scripts/render-steam-art.sh    # redraw the icons and data/steam/ (nix-shell, pinned); --check after edits
nix flake check
git config core.hooksPath .githooks   # once per clone: enables the pre-push release check
```

The flake only sees git-tracked files. Run `git add` on new files before `nix build` or `nix develop`. `spec/` and `data/` are part of the package source, because the tests read them.

## Code layout

Keep this table current: one line per file, with the spec IDs it implements. The Godot project is `app/` (`app/project.godot`); `spec/`, `data/`, `nix/`, `scripts/` and `tools/` sit beside it.

```
app/project.godot        engine settings: viewport 1280x720, stretch, renderer, app ID (config/name), version   LOOK-1 WIN-3
app/export_presets.cfg   the "Linux" pack preset (nix/package.nix) and the "AppImage" release preset (embedded pack)   INT-25
app/scenes/main.tscn     the root node; main.gd adds the Ports service and the home screen   WIN-1
app/scenes/home.tscn     the home screen: cards row, detail panel, hint bar, menu, dialog, Playing   HOME
app/scenes/card.tscn     one port card                                            HOME-1 HOME-2
app/src/main.gd          startup: config, bindings, theme, Ports (real or fake), window, quit   WIN-1 WIN-4 CONF-8 CONF-9
app/src/ini.gd           INI reader (Godot's ConfigFile can't read unquoted values) CONF-1
app/src/config.gd        config.ini + keybindings.ini, first-run files            CONF KEY-2
app/src/keys.gd          Keys.BINDINGS, key and gamepad tokens, InputMap setup, hint labels   KEY HOME-11
app/src/palette.gd       the four Catppuccin palettes (the only hex colours)      LOOK-3
app/src/theme.gd         builds the one Theme: type variations, "Palette" colours, contrast   LOOK-2 LOOK-5 LOOK-6 LOOK-8
app/src/ports.gd         Ports, the one service screens use: state, queue, checks, scans, launches, art   PORT-5 PORT-6 PORT-9 PORT-12 PORT-14 PORT-17 ROM-4 ROM-5 ROM-9 ART-3
app/src/ports_fake.gd    stand-in for Ports with demo data and scenarios (tests, screenshots)   PORT-14
app/src/catalog.gd       reads and checks data/ports.json (its schema is in the header)   PORT-1 PORT-16 PORT-17 ART-1
app/src/releases.gd      latest release from the GitHub API, asset choice and digest, update-check rule, redirect hosts   PORT-2 PORT-3 PORT-5 PORT-13
app/src/http.gd          HTTPRequest wrapper: JSON, downloads with progress, redirects followed by hand and checked   PORT-4 PORT-13
app/src/installer.gd     download, digest, unpack, swap current/previous (worker), remove, stale cleanup, extra files   PORT-3 PORT-6 PORT-7 PORT-10
app/src/launcher.gd      child environment, /bin/sh spawn, ROM placement and argument, placed-copy cleanup   PORT-8 PORT-9 PORT-15 PORT-16
app/src/state.gd         state.ini: installed and latest tags, archive version, placed ROM, last check, ROM scan cache   PORT-11
app/src/roms.gd          ROM scan (ScanJob thread, abort), zip sizes, SHA1 identification, big-endian prepare, real paths   ROM
app/src/rom_folders.gd   ROM folder detection (EmuDeck, RetroDECK, defaults, mounts), SD card search (SearchJob), chooser listings   ROM-10 ROM-14 ROM-15 ROM-16
app/scenes/rom_folder.tscn + app/src/ui/rom_folder.gd   the ROM folder chooser: starting points, folders, search, config.ini notice   ROM-11 ROM-12 ROM-14
app/src/art.gd           cover art: download one at a time, cache by URL hash, size and type checks, decode   ART-3 ART-4 ART-6
app/src/ui/home.gd       home screen logic: focus, accept, menu, dialog, Playing, hints   HOME
app/src/ui/card.gd       a card: emblem, titles, badge, progress, focus/selection look   HOME-2 HOME-12
app/src/ui/detail.gd     detail panel: description or first-launch note, versions, ROM status, progress, errors   HOME-3 HOME-8 HOME-9 PORT-17
app/src/ui/hint_bar.gd   the hint bar from the live InputMap                      HOME-11
app/src/ui/port_state.gd state, badge text and primary action of one info() dict  HOME-2 HOME-4
app/fonts/               Inter (variable) and its licence (OFL 1.1)               LOOK-6
app/data/                config.example.ini + keybindings.example.ini (first-run files)   CONF-2
app/data/ports.json      the port catalog                                         PORT-1
app/tests/               run.gd (runner; awaits tests that await; TESTS=name runs one file), case.gd (base), test_*.gd; test_spec.gd checks spec <-> code
app/tests/test_http.gd   http.gd against a local TCPServer: redirects, stall, cancel, size limit, JSON   PORT-4 PORT-13
app/tests/test_art.gd    art.gd with fake HTTP; art_catalog.json is its test catalog   ART
app/tests/test_rom_folders.gd, test_rom_folder.gd   ROM folder detection and search over fake trees; Ports' folder API and the chooser screen   ROM-10 .. ROM-16
app/tests/fake_http.gd   http.gd stand-in that answers from memory and local files
scripts/test.sh          runs app/tests headless with every XDG folder in a temp dir; fails on script, Unicode and engine errors (allowlist for the tests that break input on purpose)
scripts/manual/          UI checks (lib.sh helpers; headless.sh runs one in a headless sway); art.sh fetches the real cover art (ART), e2e.sh installs and starts the real ports
scripts/release-check.sh recommended version bump since the last v* tag (spec delta)
scripts/release.sh       bump, commit "Anchorage X.Y.Z", tag, draft notes (no push)
scripts/build-appimage.sh builds the AppImage into dist/ (git-ignored)             INT-26
.githooks/pre-push       on a push of main, offers to release
data/                    desktop entry, metainfo, app icon and symbolic icon (drawn by tools/steam-art)   INT-2 INT-41 INT-42
data/steam/              Steam library art: portrait, wide, hero, logo (SVG + PNG) and icon.png; generated   INT-27
data/themes/             the style guide's Catppuccin CSS files, for test_palette   LOOK-3
app/icon.svg             Godot project and window icon: a copy of the app icon (test_steam_art checks)   INT-42
tools/steam-art/         generate.py draws the icons and Steam art as SVG; shell.nix pins its tools   INT-27 INT-42
scripts/render-steam-art.sh runs generate.py and renders data/steam/*.png; --check fails on stale files   INT-27
nix/                     package.nix, appimage.nix (+ AppRun), nixos-module.nix, hm-module.nix   INT-2x
spec/                    the specification
```

## Conventions

- GDScript only, in the Godot 4.7 version nixpkgs ships. No C#, no GDExtension, no addons: ask first (`PROD-1`).
- Look up the Godot docs before guessing at APIs, because they change between minor versions. Use `godot --doctool` or the class reference: https://docs.godotengine.org/en/stable/classes/. The nix store has the engine source for exact behaviour (`nix build nixpkgs#godot.src`).
- Use `preload("res://...")` constants, not `class_name`. `class_name` needs the editor's script cache, which a headless run doesn't have.
- Build screens from `Control` nodes and drive them through focus (`grab_focus`, `focus_neighbor_*`) and the `ui_*` actions, so the gamepad works. Never read raw joypad events in a screen. Add an action to `Keys.BINDINGS` instead (`PROD-5`).
- Never block the main thread: `HTTPRequest` and threads for network and disk work, `await` for waiting.
- Scene (`.tscn`) edits by hand are fine and keep diffs small. If the editor rewrites a file, check that `git diff` shows only the intended change.
- Godot prints script and engine errors and keeps going. `scripts/test.sh` treats "SCRIPT ERROR", "Parse Error", "Unicode parsing error" and engine "ERROR:" lines in the output as a failure, so a green run means none. A test that feeds Godot broken input on purpose goes on the `ALLOWED` list in `scripts/test.sh`, by its name.
- A test file is `app/tests/test_*.gd`, extending `res://tests/case.gd`; each `test_*` method runs separately. Use `eq` and `check`. Use `temp_dir` for files and `repo_file` to read from `spec/` or `data/`.
- The runner starts the tests on the first frame, so a test can add a scene to `(Engine.get_main_loop() as SceneTree).root` and drive it with `get_viewport().push_input(event)` (see `test_home.gd`). Free what you add before the test returns.
- Colours come from the theme: `theme_type_variation` for styles, `get_theme_color(name, "Palette")` for a palette colour. No hex or numeric `Color(...)` outside `palette.gd` (`test_theme` checks).
- Comments only when the reason is not obvious. `gdlint` allows 100 columns; `gdformat` decides the rest.
- Commits: `spec: <summary>` for spec changes, a `Spec: ID, ID` trailer on code commits, `BREAKING` in the body for incompatible changes (`scripts/release-check.sh` reads all three). No Claude-Session links in commit messages.

## Packaging

`nix/package.nix` exports `anchorage.pck` with `godot --headless --export-pack Linux` and installs a wrapper that runs nixpkgs' `godot` on it. That avoids patching an export-template binary for NixOS. The nixpkgs build is a debug build, so the window title gets " (DEBUG)".

`nix/appimage.nix` (`nix build .#appimage`, x86_64-linux only) is the self-contained build for SteamOS (`INT-25`, `INT-26`). It exports with the "AppImage" preset (`--export-release`, pack embedded) on the official release template from `godot.export-templates-bin`, so the binary is not patched for Nix: `dontFixup` keeps the stdenv from touching it, and the build fails on an RPATH, a Nix interpreter or a store path. It assembles an AppDir (`nix/AppRun`, desktop entry, icon, metainfo), makes a zstd squashfs and appends it to the pinned static type 2 runtime (`appimagetool` is not in nixpkgs). To update, bump the runtime's dated release and hash together, and nixpkgs brings the templates with the engine. Test with `scripts/manual/headless.sh scripts/manual/appimage.sh`. On NixOS the binary needs a stock `/lib64` loader, so run it as `TMPDIR=$HOME/.cache/at RUNNER=steam-run scripts/manual/headless.sh scripts/manual/appimage.sh` (`MODE=mount` covers the FUSE mount; a direct FUSE launch needs a non-NixOS host).

## Releasing

`scripts/release-check.sh` recommends a bump from the commits since the last `v*` tag: major for `BREAKING` or a removed config key or binding, minor when a requirement became `done` or `partial`, patch for other package changes. `scripts/release.sh LEVEL NOTES` bumps `config/version` in `app/project.godot` and the metainfo, runs the tests, commits and tags, and drafts notes; then `git push origin main vX.Y.Z` and `gh release create vX.Y.Z -F NOTES`. With the hook enabled, pushing main offers all of this (`NO_RELEASE_CHECK=1` skips it). `/release` (`.claude/skills/release/`) runs all of this: it pushes main, releases a patch or minor bump without asking, and asks first for a major one. Otherwise ask before pushing.

## Manual testing

Prefer adding a script to `scripts/manual/` (source `lib.sh`, which has the guards below built in) over ad-hoc commands. Each script names the spec IDs it checks. Run it after `nix build`.

### Fake ports and screenshots

`--fake-ports [SCENARIO]` after `--` starts the app with `app/src/ports_fake.gd` instead of the real service (it is also used while `app/src/ports.gd` doesn't exist): `./result/bin/anchorage -- --fake-ports error`, or `godot --path app -- --fake-ports offline`. Scenarios: `showcase` (default: one card per state), `fresh`, `installing`, `updating`, `rom-missing`, `error`, `offline`, `playing`, `art-late`, `first-run` (every port installed without its game files: the first-launch notes), `rom-config` (the ROM folder set in `config.ini`), `no-card` (no SD card or drive); the list and what each sets are at the top of `ports_fake.gd`. Actions in the fake play out over time (a download takes 6 s, a launched port runs 8 s); the scenarios' own busy states stay still, so screenshots repeat.

- `scripts/manual/shots.sh SIZE` takes a screenshot of every scenario, the options menu, the Remove dialog and latte with blue: `HEADLESS_RES=1280x720 HEADLESS_SCALE=1 OUT=/tmp/shots scripts/manual/headless.sh scripts/manual/shots.sh 1280x720`. `FLAVOR` and `ACCENT` change the look for the whole run.
- `scripts/manual/rom-folder.sh SIZE` takes screenshots of the ROM folder chooser (`ROM-11`, `ROM-12`, `ROM-14`), same usage as `shots.sh`.
- `scripts/manual/home.sh` (1280×720) drives focus with keys and finds the focus ring by its colour, including while a download runs.
- To try the UI from a checkout without `nix build`, run `godot --headless --path app --import` once (it imports the font), then pass `BIN=` a script that runs `godot --path app "$@"`.

### Headless (default)

Run checks with `./scripts/manual/headless.sh ./scripts/manual/<name>.sh`. It starts a headless sway with its own D-Bus session and runtime dir, so it works while the screen is locked or the user has the app open, and never touches their windows. `lib.sh` switches to `swaymsg` when `HEADLESS` is set, so scripts don't change.

- `lib.sh`'s `launch` starts the app with `--display-driver wayland --rendering-driver opengl3`, so it never falls back to the user's X11 session. It kills only the process it started (`$PID`).
- The output defaults to 3840×2160 at scale 2. Set `HEADLESS_RES` and `HEADLESS_SCALE` to test other sizes. The app ignores Wayland scale for layout, since the stretch mode scales the UI by window size, so check sizes with `scripts/manual/resolutions.sh` (1280×720, 1280×800, 1920×1080, 3840×2160, fullscreen as in gamescope). Windows float, so they open at their default size.
- A window size the app sets on itself after startup leaves part of the surface unpainted under sway (see the `CONF-4` row). Make the compositor resize instead (`swaymsg fullscreen enable`), as gamescope does.
- Send screenshots (`shot`, into `$OUT`) to the user when a change is visual.
- Headless sway drops the first key after `wtype` loads its keymap; `keys` sends a Shift tap first to absorb it.
- Gamepad input can't come from `wtype`. Unit-test the bindings (`test_keys.gd`), and for a screen's focus navigation send keyboard keys, which the default bindings map to the same actions.
- The runner keeps tests out of the user's session. It uses a private bus without portals, temp `XDG_STATE_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME` and runtime dir, and no `$DISPLAY`. Scripts still set their own config and state dirs: never rely on the runner to protect the user's files.
- In headless mode `hyprctl` only answers `cursorpos` (tracked from `wlrctl` moves) and `monitors`; anything else, and `ydotool` (kernel-level input), fails instead of reaching the real session.
- Headless sway is not Hyprland or gamescope. Use a real Hyprland session (below) for compositor behaviour, and ask the user to check on the Steam Deck or in game mode for anything gamescope-specific: say plainly that it was not verified there.

### End to end (real network, real ports)

`scripts/manual/e2e.sh` installs all four ports from GitHub with keyboard input, refreshes, launches each one (Shipwright and 2ship get the ROM as an argument and extract without asking), answers the other ports' first-run "Generate one now?" prompt and removes one, with HOME and every XDG folder in a temp sandbox and ROM copies from `ROMS`. Screenshots and the ports' `launch.log` go to `$OUT`; the sandbox is deleted at the end (`KEEP=1` keeps it). On NixOS the release AppImages need an FHS environment and `steam-run` has a private `/tmp`, so put the runner's temp folder in your home, under a short path (sway's socket path has a length limit):

```bash
mkdir -p ~/.cache/ae && TMPDIR=~/.cache/ae RUNNER=steam-run ROMS=/path/to/rom/copies OUT=/tmp/shots \
  HEADLESS_RES=1920x1080 HEADLESS_SCALE=1 scripts/manual/headless.sh scripts/manual/e2e.sh
```

On a NixOS host with `programs.appimage.binfmt`, the kernel hands every AppImage to `appimage-run`, which ignores `APPIMAGE_EXTRACT_AND_RUN` and has fewer libraries than SteamOS (Starship v2.0.0 misses `libgpg-error.so.0` there). Those failures are the host's, not Anchorage's.

### On Hyprland

Run `./scripts/manual/<name>.sh` directly.

- Screenshots: `hyprctl clients -j` gives the window geometry, and `grim -g` captures it. Use an `XDG_CONFIG_HOME` in a temp dir to test config variants.
- Check `pidof hyprlock` first: if the screen is locked, grim captures the lock screen. `systemd-inhibit --what=idle` works, because hypridle respects inhibitors.
- New windows don't take focus. Run `hyprctl dispatch 'hl.dsp.focus({ window = "class:io.github.DisposableSoftware.Anchorage" })'` (Hyprland 0.56 uses a Lua config), then send keys with `wtype`. Always check `hyprctl activewindow` first, so keys never land in the user's other apps.
- The Nix wrapper `exec`s `godot`, so the process name is `godot`: `pgrep -x anchorage` never matches. Kill test windows through the pid `launch` recorded, not by class or name.
- Check there are no `io.github.DisposableSoftware.Anchorage` clients before testing, and don't go ahead if there are: the user may have the app open.

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
nix flake check
git config core.hooksPath .githooks   # once per clone: enables the pre-push release check
```

The flake only sees git-tracked files. Run `git add` on new files before `nix build` or `nix develop`. `spec/` and `data/` are part of the package source, because the tests read them.

## Code layout

Keep this table current: one line per file, with the spec IDs it implements. The Godot project is `app/` (`app/project.godot`); `spec/`, `data/`, `nix/` and `scripts/` sit beside it.

```
app/project.godot        engine settings: viewport 1280x720, stretch, renderer, app ID (config/name), version   LOOK-1 WIN-3
app/export_presets.cfg   the "Linux" preset that `--export-pack` needs
app/scenes/main.tscn     the main screen                                          WIN-1
app/src/main.gd          startup: config, bindings, window title and size, quit   WIN-1 WIN-4
app/src/ini.gd           INI reader (Godot's ConfigFile can't read unquoted values) CONF-1
app/src/config.gd        config.ini + keybindings.ini, first-run files            CONF KEY-2
app/src/keys.gd          Keys.BINDINGS, key and gamepad tokens, InputMap setup    KEY
app/data/                config.example.ini + keybindings.example.ini (first-run files)   CONF-2
app/tests/               run.gd (runner), case.gd (base), test_*.gd; test_spec.gd checks spec <-> code
scripts/test.sh          runs app/tests headless, fails on script errors
scripts/manual/          UI checks (lib.sh helpers; headless.sh runs one in a headless sway)
scripts/release-check.sh recommended version bump since the last v* tag (spec delta)
scripts/release.sh       bump, commit "Anchorage X.Y.Z", tag, draft notes (no push)
.githooks/pre-push       on a push of main, offers to release
data/                    desktop entry, metainfo, icon                            INT-2 INT-41
nix/                     package.nix, nixos-module.nix, hm-module.nix             INT-2x
spec/                    the specification
```

## Conventions

- GDScript only, in the Godot 4.7 version nixpkgs ships. No C#, no GDExtension, no addons: ask first (`PROD-1`).
- Look up the Godot docs before guessing at APIs, because they change between minor versions. Use `godot --doctool` or the class reference: https://docs.godotengine.org/en/stable/classes/. The nix store has the engine source for exact behaviour (`nix build nixpkgs#godot.src`).
- Use `preload("res://...")` constants, not `class_name`. `class_name` needs the editor's script cache, which a headless run doesn't have.
- Build screens from `Control` nodes and drive them through focus (`grab_focus`, `focus_neighbor_*`) and the `ui_*` actions, so the gamepad works. Never read raw joypad events in a screen. Add an action to `Keys.BINDINGS` instead (`PROD-5`).
- Never block the main thread: `HTTPRequest` and threads for network and disk work, `await` for waiting.
- Scene (`.tscn`) edits by hand are fine and keep diffs small. If the editor rewrites a file, check that `git diff` shows only the intended change.
- Godot prints script errors and keeps going. `scripts/test.sh` treats "SCRIPT ERROR" and "Parse Error" in the output as a failure, so a green run means none.
- A test file is `app/tests/test_*.gd`, extending `res://tests/case.gd`; each `test_*` method runs separately. Use `eq` and `check`. Use `temp_dir` for files and `repo_file` to read from `spec/` or `data/`.
- Comments only when the reason is not obvious. `gdlint` allows 100 columns; `gdformat` decides the rest.
- Commits: `spec: <summary>` for spec changes, a `Spec: ID, ID` trailer on code commits, `BREAKING` in the body for incompatible changes (`scripts/release-check.sh` reads all three). No Claude-Session links in commit messages.

## Packaging

`nix/package.nix` exports `anchorage.pck` with `godot --headless --export-pack Linux` and installs a wrapper that runs nixpkgs' `godot` on it. That avoids patching an export-template binary for NixOS. The nixpkgs build is a debug build, so the window title gets " (DEBUG)". A self-contained build for SteamOS without Nix is `INT-25`.

## Releasing

`scripts/release-check.sh` recommends a bump from the commits since the last `v*` tag: major for `BREAKING` or a removed config key or binding, minor when a requirement became `done` or `partial`, patch for other package changes. `scripts/release.sh LEVEL NOTES` bumps `config/version` in `app/project.godot` and the metainfo, runs the tests, commits and tags, and drafts notes; then `git push origin main vX.Y.Z` and `gh release create vX.Y.Z -F NOTES`. With the hook enabled, pushing main offers all of this (`NO_RELEASE_CHECK=1` skips it). `/release` (`.claude/skills/release/`) runs all of this: it pushes main, releases a patch or minor bump without asking, and asks first for a major one. Otherwise ask before pushing.

## Manual testing

Prefer adding a script to `scripts/manual/` (source `lib.sh`, which has the guards below built in) over ad-hoc commands. Each script names the spec IDs it checks. Run it after `nix build`.

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

### On Hyprland

Run `./scripts/manual/<name>.sh` directly.

- Screenshots: `hyprctl clients -j` gives the window geometry, and `grim -g` captures it. Use an `XDG_CONFIG_HOME` in a temp dir to test config variants.
- Check `pidof hyprlock` first: if the screen is locked, grim captures the lock screen. `systemd-inhibit --what=idle` works, because hypridle respects inhibitors.
- New windows don't take focus. Run `hyprctl dispatch 'hl.dsp.focus({ window = "class:io.github.DisposableSoftware.Anchorage" })'` (Hyprland 0.56 uses a Lua config), then send keys with `wtype`. Always check `hyprctl activewindow` first, so keys never land in the user's other apps.
- The Nix wrapper `exec`s `godot`, so the process name is `godot`: `pgrep -x anchorage` never matches. Kill test windows through the pid `launch` recorded, not by class or name.
- Check there are no `io.github.DisposableSoftware.Anchorage` clients before testing, and don't go ahead if there are: the user may have the app open.

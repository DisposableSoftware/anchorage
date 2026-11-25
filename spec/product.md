# Product

A controller-first launcher for the [HarbourMasters](https://github.com/HarbourMasters) PC ports (Ship of Harkinian, 2Ship2Harkinian, Starship, SpaghettiKart). It installs, updates and launches them, and runs as a non-Steam game in Steam OS game mode (gamescope). Display name **Anchorage**, binary `anchorage`, app ID `io.github.DisposableSoftware.Anchorage`.

## Requirements

| ID | Requirement | Status |
|----|-------------|--------|
| `PROD-1` | Lightweight and minimal: no addons, no GDExtensions, fast startup. | done (ongoing constraint) |
| `PROD-2` | Follow a freedesktop/XDG spec wherever one exists for the behaviour (see [integration.md](integration.md)). | done (ongoing constraint) |
| `PROD-3` | Simple toolchain: `godot` and `gdtoolkit` inside a Nix devshell, nothing else. | done |
| `PROD-4` | Easy NixOS integration. | done (see `INT-20`…`INT-24`) |
| `PROD-5` | Every action has a binding users can change, for keyboard and gamepad (see [keybindings.md](keybindings.md)). | done (ongoing constraint) |
| `PROD-6` | Run fullscreen in gamescope at 1280×720 and up. The layout scales with the window size and uses no fixed pixel layouts. | partial: the layout scales, but the window was never made fullscreen, so Game Mode on a 1280×800 Deck showed black bars (see `WIN-6`) |
| `PROD-7` | Be fully usable with a gamepad alone: D-pad and stick to move, A to select, B to go back, with a button hint bar. Mouse and keyboard also work. | planned |
| `PROD-8` | Install a port by downloading its latest Linux release from GitHub into the XDG data directory. | planned |
| `PROD-9` | Check for updates and update an installed port. Keep the previous version until the new one launches. | planned |
| `PROD-10` | Launch a port as a child process, then return to Anchorage when the port exits. | planned |
| `PROD-11` | Scan a configured ROM directory (default `~/Roms/n64`) and match each ROM by hash to the right port. Run the port's own asset extraction. | planned |
| `PROD-12` | Show the state of each port: not installed, installed, update available, or ROM missing. | planned |
| `PROD-13` | Ports are data entries (name, GitHub repo, release asset pattern, ROM hashes), so adding a port adds a row, not code. | planned |
| `PROD-14` | No ROM, game archive or game asset ever enters the repository, its history or a push: `.gitignore` lists them, and `scripts/check-no-roms.sh` (run by the pre-push hook on every push) refuses ROM-like file names, N64 ROM headers under any name, and files over 5 MiB. | done | `scripts/manual/check-no-roms.sh` |

## Style guide

The shared look, feel and wording of DisposableSoftware apps is described in the [DisposableSoftware style guide](https://github.com/DisposableSoftware/style-guide). It is a reference, not a requirement: where it and this spec disagree, this spec wins. Look rules that apps adopt from it are `LOOK-n` rows in [appearance.md](appearance.md), each naming the guide page it comes from. The palette is [Catppuccin](https://catppuccin.com), made by the Catppuccin community, and is credited to them wherever it is shown or shipped.

## Non-goals

- Not a ROM manager or a general emulator frontend. Anchorage never downloads or distributes ROMs or game assets.
- No Steam shortcut per game. Anchorage is the single non-Steam entry.
- No status bar.

## Stack constraints

- Godot 4.7 from nixpkgs, GDScript only. No C#, no GDExtension, no addons: ask first.
- GL Compatibility renderer. UI is built from `Control` nodes, so focus navigation works from a gamepad.
- Scenes (`.tscn`) and scripts are text and live in git. Edit them by hand or in the editor, and keep diffs small: don't let the editor reorder or reformat unrelated parts of `project.godot`.
- Anything that touches disk or network is non-blocking: use `HTTPRequest`, threads or `await`, never a blocking call on the main thread in a frame callback.
- Use Godot's own APIs for paths, HTTP, JSON, zip and processes before adding anything.
- Ports run as child processes (`OS.create_process`), and Anchorage never links against them.

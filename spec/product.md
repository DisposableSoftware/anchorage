# Product

A controller-first launcher for the [HarbourMasters](https://github.com/HarbourMasters) PC ports (Ship of Harkinian, 2Ship2Harkinian, Starship, SpaghettiKart). It installs, updates and launches them, and runs as a non-Steam game in Steam OS game mode (gamescope). Display name **Anchorage**, binary `anchorage`, app ID `io.github.DisposableSoftware.Anchorage`.

## Requirements

| ID | Requirement | Status |
|----|-------------|--------|
| `PROD-1` | Lightweight and minimal: few dependencies, no libadwaita, fast startup. | done (ongoing constraint) |
| `PROD-2` | Follow a freedesktop/XDG spec wherever one exists for the behaviour (see [integration.md](integration.md)). | done (ongoing constraint) |
| `PROD-3` | Simple toolchain: `cargo` inside a Nix devshell, nothing else. | done |
| `PROD-4` | Easy NixOS integration. | done (see `INT-20`…`INT-24`) |
| `PROD-5` | Every action has a keybinding users can change (see [keybindings.md](keybindings.md)). | done (ongoing constraint) |
| `PROD-6` | Run fullscreen in gamescope at 1280×720 and up. The layout scales with the window size and uses no fixed pixel layouts. | planned |
| `PROD-7` | Be fully usable with a gamepad alone: D-pad and stick to move, A to select, B to go back, with a button hint bar. Mouse and keyboard also work. | planned |
| `PROD-8` | Install a port by downloading its latest Linux release from GitHub into the XDG data directory. | planned |
| `PROD-9` | Check for updates and update an installed port. Keep the previous version until the new one launches. | planned |
| `PROD-10` | Launch a port as a child process, then return to Anchorage when the port exits. | planned |
| `PROD-11` | Scan a configured ROM directory (default `~/Roms/n64`) and match each ROM by hash to the right port. Run the port's own asset extraction. | planned |
| `PROD-12` | Show the state of each port: not installed, installed, update available, or ROM missing. | planned |
| `PROD-13` | Ports are data entries (name, GitHub repo, release asset pattern, ROM hashes), so adding a port adds a row, not code. | planned |

## Style guide

The shared look, feel and wording of DisposableSoftware apps is described in the [DisposableSoftware style guide](https://github.com/DisposableSoftware/style-guide). It is a reference, not a requirement: where it and this spec disagree, this spec wins. Look rules that apps adopt from it are `LOOK-n` rows in [appearance.md](appearance.md), each naming the guide page it comes from. The palette is [Catppuccin](https://catppuccin.com), made by the Catppuccin community, and is credited to them wherever it is shown or shipped.

## Non-goals

- No libadwaita. It fights custom theming and transparency.
- Not a ROM manager or a general emulator frontend. Anchorage never downloads or distributes ROMs or game assets.
- No Steam shortcut per game. Anchorage is the single non-Steam entry.
- No status bar.

## Stack constraints

- Rust and gtk4-rs (`gtk4` 0.11 with feature `gnome_49`).
- Use GIO/GLib for anything they provide (XDG dirs, MIME, files, D-Bus) rather than reimplementing it or adding a crate.
- Ask before adding a crate.
- File I/O is async through GIO. The main loop never blocks on I/O.

# Integration

## XDG / freedesktop

| ID | Spec | Requirement | Status |
|----|------|-------------|--------|
| `INT-1` | Base Directory | Config paths come from `OS.get_config_dir()` (`$XDG_CONFIG_HOME`), and `user://` is `$XDG_DATA_HOME/anchorage` (`application/config/use_custom_user_dir`). State goes to `$XDG_STATE_HOME`, falling back to `~/.local/state`, and cache to `OS.get_cache_dir()`. Nothing is hard-coded as `~/.config`. | done |
| `INT-2` | Desktop Entry | `io.github.DisposableSoftware.Anchorage.desktop`: `Name=Anchorage`, `Exec=anchorage`, `Icon=io.github.DisposableSoftware.Anchorage`, `StartupWMClass=io.github.DisposableSoftware.Anchorage`, `Categories=Game;`. It passes `desktop-file-validate`. | done |

## Nix

| ID | Requirement | Status |
|----|-------------|--------|
| `INT-20` | The flake exports `packages.<system>.default`, `devShells.<system>.default`, `overlays.default` (attr `anchorage`), `nixosModules.default` and `homeManagerModules.default`, for x86_64-linux and aarch64-linux. | done |
| `INT-21` | The package builds `anchorage.pck` with nixpkgs' `godot` (`--export-pack`) and installs `bin/anchorage` (a wrapper that runs that `godot` on the pack), the desktop entry, the app icon, the AppStream metainfo (`INT-41`) and both example files (`CONF-2`). `nix build` runs the unit tests and the spec tests. | done |
| `INT-22` | NixOS module `programs.anchorage`: `enable`, `package`. | done |
| `INT-23` | Home-manager module `programs.anchorage`: `enable`, `package`, `settings` (generates `config.ini`), `keybindings` (binding name to a list of keys; generates `keybindings.ini`, lists joined with `;`). | done |
| `INT-24` | `nix flake check` passes, and it runs `gdlint` and `gdformat --check` over `app/src` and `app/tests` as well as the tests. | done |

## AppImage

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `INT-25` | Each GitHub release attaches `Anchorage-<version>-x86_64.AppImage`, a self-contained build that runs on SteamOS and other x86_64 glibc Linux without Nix or other installs. The binary is the official Godot release export template (same engine version as nixpkgs' `godot`) with the pack embedded and the Compatibility renderer. It is not patched: no RPATH, no Nix interpreter, and it links only glibc libraries. Everything else (Wayland, X11, GL, Vulkan, audio) is loaded at run time from the host. The system needs only glibc, its drivers, and FUSE 2 (or `--appimage-extract-and-run`, or `APPIMAGE_EXTRACT_AND_RUN=1`, which need no FUSE). The AppImage carries the desktop entry, icon and metainfo. The window title has no "(DEBUG)", the app ID is the one in `WIN-3`, and `user://` and the config paths follow `INT-1`. | partial: the release flow builds and attaches it (`scripts/release.sh`, `/release`) but no release has run yet; not run on SteamOS or under gamescope | `scripts/manual/appimage.sh` (headless sway, extract-and-run and FUSE mount: contents, ELF checks, window, app ID, title, size, quit, empty environment) |
| `INT-26` | `nix build .#appimage` (x86_64-linux only; `scripts/build-appimage.sh` runs it and puts the result in `dist/`) builds that AppImage from a clean checkout with no network except the Godot export templates and the AppImage runtime, both fetched by Nix with pinned hashes. The runtime is a dated release of the static type 2 runtime, and the image is a zstd squashfs appended to it (`appimagetool` is not in nixpkgs and adds nothing needed here). The build fails if the binary has an RPATH, a Nix interpreter or a store path, or if the desktop entry or metainfo does not validate. `scripts/manual/appimage.sh` starts the result headless and checks the window. | done | `nix build .#appimage` (the build checks) and `scripts/manual/appimage.sh` |

## Command line and metadata

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `INT-30` | `anchorage --help`. | dropped | superseded: Godot reads `--help` and `--version` itself, and the app is started from Steam, not a terminal. |
| `INT-31` | `anchorage --version`. | dropped | same reason as `INT-30`. The version is `config/version` in `app/project.godot`. |
| `INT-32` | The man page. | dropped | superseded: bindings and settings are documented in the example files (`CONF-2`), which are the reference for a game-mode app. |
| `INT-41` | AppStream metainfo, `share/metainfo/io.github.DisposableSoftware.Anchorage.metainfo.xml`: ID, name, summary, a description that keeps the README's warning, the launchable desktop entry, licences, developer, homepage and the current release. It passes `appstreamcli validate --no-net`. | done | manual (`appstreamcli validate --no-net`); `test_spec::test_version_is_the_same_everywhere` |
| `INT-42` | A symbolic app icon, `io.github.DisposableSoftware.Anchorage-symbolic.svg` (one colour), is installed beside the full-colour icon. The full-colour icon is flat Catppuccin mocha with no text. Style guide: layout.md, "Icons". | planned | manual (`nix build`; the file is in `share/icons`) |
| `INT-43` | The README follows the style guide's shape: centred icon and name, a one-line tagline, the vibe-coded warning, and a Credits section that credits [Catppuccin](https://catppuccin.com) and its community with links. Style guide: readme.md. | planned | manual |

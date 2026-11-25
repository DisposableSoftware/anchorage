# Configuration

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `CONF-1` | Settings are read from `$XDG_CONFIG_HOME/anchorage/config.ini` (INI syntax: `[section]`, `key = value`, `#` or `;` comment lines, values are plain text without quotes) when the app starts. A missing file is not an error. A file that can't be read is warned about, and the defaults are used. Every key is optional. Changes apply on restart. | done | `test_config`, `test_ini` |
| `CONF-2` | `app/data/config.example.ini` lists every setting with its default, and `app/data/keybindings.example.ini` every binding with its default keys. Both are installed to `share/doc/anchorage/`. | done | `test_spec::test_example_config_matches_spec` |
| `CONF-3` | When the app starts and `config.ini` or `keybindings.ini` doesn't exist, it creates the missing file (and the folder) from the example (`CONF-2`), with every line commented out, so the file changes nothing until a line is uncommented. A file that exists is never written to, whether it is a regular file, a symlink (as with dotfiles or home-manager) or a dangling symlink. If a file can't be created, that is warned about and the app starts normally. | done | `test_config` |
| `CONF-4` | `[window] width` and `height`: the size of the window in logical px when it is not fullscreen, clamped to 1280–8192 and 720–8192, so the window is never smaller than 720p. | partial | `test_config`, `test_spec`. Gap: under sway, a size the app sets on itself after startup leaves the surface partly unpainted (the default size is fine, and so is a size the compositor sets, such as fullscreen). Not checked on Hyprland or in gamescope. |
| `CONF-5` | `[view] greeting`. | dropped | superseded: the window shows the home screen (`WIN-1`), so the template's greeting has nothing to show. No release had it. |
| `CONF-6` | `[appearance] flavor`: `latte`, `frappe`, `macchiato` or `mocha`, default `mocha`. An unknown value falls back to `mocha` with a warning. Style guide: palette.md, "Config". | done | `test_config::test_appearance_falls_back_on_unknown_values`, `test_spec` |
| `CONF-7` | `[appearance] accent`: one of the 14 Catppuccin accent names, default `mauve`, with unknown values falling back to `mauve`. Style guide: palette.md, "Config". | done | `test_config::test_appearance_falls_back_on_unknown_values`, `test_spec` |
| `CONF-8` | `[roms] directory`: the folder scanned for ROMs (`ROM-1`), or several folders separated by `;` (empty items skipped), scanned in that order, the first folder with a match winning for a port (`ROM-17`). When it is set it wins over the folders chosen in the app (`ROM-12`); when it is not, Anchorage finds the folder itself (`ROM-10`), and the listed default `~/Roms/n64` is where that ends when nothing is found and `~/Emulation` does not exist. | done | `test_config` (a `;` list is kept as written), `test_spec`, `test_ports::test_rom_status_names_what_is_wanted_and_where_it_looked` (the folder Ports scans and names), `test_rom_folder_list::test_config_ini_lists_several_folders` (Ports splits it: in order, empty items skipped, a missing one skipped, both games found, the chooser cannot add); `main.gd` hands `Config.roms_directory` to `Ports` |
| `CONF-9` | `[ports] check_updates`: `true` or `false`, default `true`; whether Anchorage checks for updates at start (`PORT-5`). Anything but `false` counts as `true`. | done | `test_config::test_check_updates_is_off_only_for_false`, `test_spec`, `test_ports::test_the_start_check_obeys_check_updates_and_the_hour`; `main.gd` hands `Config.check_updates` to `Ports` |

## Defaults

<!-- spec:config:begin -->
| Section | Key | Default |
|---------|-----|---------|
| `window` | `width` | `1280` |
| `window` | `height` | `720` |
| `appearance` | `flavor` | `mocha` |
| `appearance` | `accent` | `mauve` |
| `roms` | `directory` | `~/Roms/n64` |
| `ports` | `check_updates` | `true` |
<!-- spec:config:end -->

The defaults for `[keybindings]` are in [keybindings.md](keybindings.md).

## Implementation notes

- To add a key, edit the defaults table, the fields of `Config` (`app/src/config.gd`), `config_value` and `CONFIG_KEY_COUNT` in `app/tests/test_spec.gd`, `app/data/config.example.ini` and, if it needs an option, `nix/hm-module.nix`. The spec tests fail until they agree.
- Godot's `ConfigFile` cannot read these files: it needs quoted strings, and home-manager writes them unquoted. `app/src/ini.gd` reads them instead.
- Runtime state the app remembers between sessions (as opposed to settings) belongs in `$XDG_STATE_HOME/anchorage/state.ini`, written atomically, never in `config.ini`. Downloaded ports and their data live in `user://`, which is `$XDG_DATA_HOME/anchorage` (`INT-1`).

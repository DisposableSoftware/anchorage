# Keybindings

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `KEY-1` | Every user-facing action has a binding name, and its defaults are listed in the table below. Each binding drives one Godot input action, so a gamepad and a keyboard do the same thing. | done | `test_spec::test_keybindings_match_spec` |
| `KEY-2` | Users override a binding in the `[keybindings]` group of `$XDG_CONFIG_HOME/anchorage/keybindings.ini`, writing `name = key;key`. An empty value unbinds it. A binding that isn't listed keeps its defaults. | done | `test_config::test_reads_settings_and_keybindings_from_their_files`, `test_keys::test_overrides_replace_defaults_and_bad_ones_are_dropped` |
| `KEY-3` | Unknown binding names and keys that can't be parsed are warned about on stderr and skipped. They never crash the app. | done | `test_keys::test_overrides_replace_defaults_and_bad_ones_are_dropped` |
| `KEY-4` | Key syntax: a keyboard key is optional `Ctrl+`, `Shift+`, `Alt+` or `Super+` modifiers and a Godot key name (`Enter`, `Escape`, `Up`, `Q`, `F4`). A gamepad input is `Pad:` and a button (`A`, `B`, `X`, `Y`, `Back`, `Guide`, `Start`, `LeftStick`, `RightStick`, `LeftShoulder`, `RightShoulder`, `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`), a stick direction (`LeftStickUp`, `LeftStickDown`, `LeftStickLeft`, `LeftStickRight`, and the same for `RightStick`) or a trigger (`LeftTrigger`, `RightTrigger`). | done | `test_keys::test_tokens` |
| `KEY-5` | Button names are the Xbox layout that Steam Input reports. The Steam Deck's A, B, X and Y are `Pad:A`, `Pad:B`, `Pad:X` and `Pad:Y`. | done | `test_keys::test_tokens` |
| `KEY-6` | Two more bindings drive the home screen: `options` (default `O`, `Pad:Y`) opens the port menu (`HOME-5`) and `refresh` (default `F5`, `Pad:X`) checks for updates and rescans ROMs (`HOME-6`). Add them to the table below with the code. | done | `test_spec::test_keybindings_match_spec`; `test_home::test_options_menu_lists_what_the_port_allows`, `test_home::test_refresh_checks_and_rescans` |
| `KEY-7` | A `menu` binding (default `F10`, `Pad:Start`) opens the app menu (`HOME-14`). Add it to the table below with the code. | done | `test_spec::test_keybindings_match_spec` (the table, `Keys.BINDINGS` and `keybindings.example.ini` agree), `test_keys::test_every_default_token_parses` (`F10`, `Pad:Start`); `test_app_menu::test_the_app_menu_opens_and_back_closes_it` |

## Default bindings

<!-- spec:keybindings:begin -->
| Name | Action | Default keys |
|------|--------|--------------|
| `up` | `ui_up` | `Up`, `Pad:DPadUp`, `Pad:LeftStickUp` |
| `down` | `ui_down` | `Down`, `Pad:DPadDown`, `Pad:LeftStickDown` |
| `left` | `ui_left` | `Left`, `Pad:DPadLeft`, `Pad:LeftStickLeft` |
| `right` | `ui_right` | `Right`, `Pad:DPadRight`, `Pad:LeftStickRight` |
| `accept` | `ui_accept` | `Enter`, `Pad:A` |
| `back` | `ui_cancel` | `Escape`, `Pad:B` |
| `options` | `options` | `O`, `Pad:Y` |
| `refresh` | `refresh` | `F5`, `Pad:X` |
| `menu` | `menu` | `F10`, `Pad:Start` |
| `quit` | `quit` | `Ctrl+Q` |
<!-- spec:keybindings:end -->

## Implementation notes

- To add a binding, edit the table above, `Keys.BINDINGS` in `app/src/keys.gd` and `app/data/keybindings.example.ini`. The spec tests fail until they agree.
- `ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_accept` and `ui_cancel` are Godot's own focus-navigation actions. Replacing their events (`Keys.apply`) is what makes `Control` focus movement follow the user's bindings, so screens use `Control` focus rather than reading raw input.
- A stick direction is a joypad-motion event, and the action's deadzone decides when it counts as pressed. `Keys.apply` leaves the deadzone at Godot's default.

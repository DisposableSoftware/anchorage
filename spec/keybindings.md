# Keybindings

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `KEY-1` | Every user-facing action has a binding name, and its defaults are listed in the table below. Each binding drives one Godot input action, so a gamepad and a keyboard do the same thing. | done | `test_spec::test_keybindings_match_spec` |
| `KEY-2` | Users override a binding in the `[keybindings]` group of `$XDG_CONFIG_HOME/anchorage/keybindings.ini`, writing `name = key;key`. An empty value unbinds it. A binding that isn't listed keeps its defaults. | done | `test_config::test_reads_settings_and_keybindings_from_their_files`, `test_keys::test_overrides_replace_defaults_and_bad_ones_are_dropped` |
| `KEY-3` | Unknown binding names and keys that can't be parsed are warned about on stderr and skipped. They never crash the app. | done | `test_keys::test_overrides_replace_defaults_and_bad_ones_are_dropped` |
| `KEY-4` | Key syntax: a keyboard key is optional `Ctrl+`, `Shift+`, `Alt+` or `Super+` modifiers and a Godot key name (`Enter`, `Escape`, `Up`, `Q`, `F4`). A gamepad input is `Pad:` and a button (`A`, `B`, `X`, `Y`, `Back`, `Guide`, `Start`, `LeftStick`, `RightStick`, `LeftShoulder`, `RightShoulder`, `DPadUp`, `DPadDown`, `DPadLeft`, `DPadRight`), a stick direction (`LeftStickUp`, `LeftStickDown`, `LeftStickLeft`, `LeftStickRight`, and the same for `RightStick`) or a trigger (`LeftTrigger`, `RightTrigger`). | done | `test_keys::test_tokens` |
| `KEY-5` | Button names are the Xbox layout that Steam Input reports. The Steam Deck's A, B, X and Y are `Pad:A`, `Pad:B`, `Pad:X` and `Pad:Y`. | done | `test_keys::test_tokens` |
| `KEY-6` | Two more bindings drive the home screen: `options` (default `O`, `Pad:Y`) opens the port menu (`HOME-5`) and `refresh` (default `F5`, `Pad:X`) checks for updates and rescans ROMs (`HOME-6`). Add them to the table below with the code. | planned | `test_spec::test_keybindings_match_spec` |

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
| `quit` | `quit` | `Ctrl+Q` |
<!-- spec:keybindings:end -->

## Implementation notes

- To add a binding, edit the table above, `Keys.BINDINGS` in `app/src/keys.gd` and `app/data/keybindings.example.ini`. The spec tests fail until they agree.
- `ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_accept` and `ui_cancel` are Godot's own focus-navigation actions. Replacing their events (`Keys.apply`) is what makes `Control` focus movement follow the user's bindings, so screens use `Control` focus rather than reading raw input.
- A stick direction is a joypad-motion event, and the action's deadzone decides when it counts as pressed. `Keys.apply` leaves the deadzone at Godot's default.

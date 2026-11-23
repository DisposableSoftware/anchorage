# Home screen

The one screen the user sees: the ports as cards, and the focused port's details and actions. Everything works with a gamepad alone (`PROD-7`).

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `HOME-1` | The screen shows one card per catalog port, in catalog order, in a single row or a grid that fits 1280×720 without scrolling for four ports. Focus starts on the first card. The D-pad and left stick move focus between cards. | planned | `scripts/manual/home.sh` (screenshot, keyboard focus moves); `test_home` |
| `HOME-2` | A card shows the game title, the port name and a state badge: `Not installed`, `Ready`, `Update available`, `ROM missing`, or a busy state (`Installing 42%`, `Updating`, `Playing`). A port that is both installed and short of a ROM shows `ROM missing`. | planned | `test_home` (badge text per state from `ports_fake`); screenshot |
| `HOME-3` | A detail panel for the focused port shows its description, the installed and latest versions (or `Offline` when the check failed), and the ROM status: the matched file's name, or the game versions it needs and the folder scanned (`ROM-9`). | planned | `test_home`; screenshot |
| `HOME-4` | The accept button runs the focused port's primary action: `Install` when not installed, `Update` when an update is available (the port stays playable through `Play` in the options), `Play` when ready, and nothing but a hint when the ROM is missing. | planned | `test_home` (which action each state calls on `ports_fake`) |
| `HOME-5` | The `options` binding opens a small menu for the focused port: `Play` (when installed), `Check for updates`, `Remove` (when installed). Back closes it. | planned | `test_home`; screenshot |
| `HOME-6` | The `refresh` binding checks for updates and rescans the ROM folder (`PORT-5`, `ROM-5`). | planned | `test_home` |
| `HOME-7` | A confirmation dialog guards `Remove`: it names the port and says that saves and settings stay. Focus starts on `Cancel`; accept presses the focused button, so confirming takes a move to `Remove` first, and back cancels. | planned | `test_home`; screenshot |
| `HOME-8` | While a port installs or updates its card and the detail panel show a progress bar, and the back button cancels it after a confirmation-free single press. | planned | `test_home`; screenshot |
| `HOME-9` | Errors from `Ports` appear in the detail panel as `Could not <verb> “<name>”` with the detail below it. Accept or back dismisses it. | planned | `test_home`; screenshot |
| `HOME-10` | While a port is running, the home screen shows `Playing <game>` over the card, ignores input except `quit`, and returns to normal when the port exits, with focus where it was. | planned | `test_home`; manual (real port, as far as the machine can run it) |
| `HOME-11` | A hint bar at the bottom shows the actions of the current screen, each with the first gamepad button and the first key bound to it, from the live bindings (`KEY-1`), so remaps show. | planned | `test_home` (hint text from a remapped binding); screenshot |
| `HOME-12` | The focused card is always visibly highlighted (`LOOK-5`). Moving the mouse over a card focuses it, and a click does what accept does. | planned | screenshot; `test_home` |
| `HOME-13` | Nothing on this screen blocks the main loop: installs, downloads, scans and update checks run through `Ports` and report back by signals. | planned | manual (the UI answers input during a download) |

## Implementation notes

- Screens are `Control` scenes under `app/scenes/` with scripts in `app/src/ui/`, built from the `Theme` (`LOOK-2`). Colours and sizes come from the theme, never from literals in scenes.
- The screen talks only to `Ports` (`PORT-14`). Tests and screenshots use `ports_fake.gd`, which has fixed demo data, including a state of every kind.
- Focus uses Godot's `Control` focus and the `ui_*` actions, so remapped bindings work.
- `info(id).error` is shown with its first line as the title (`Could not install “Ship of Harkinian”`) and the lines after it as the detail.
- Without cover art, a card shows a generated emblem: the game's short name built from its title (the part after a colon; initials, lowercase for lowercase words, numbers whole: `OoT`, `MM`, `SF64`, `MK64`) on a tile in one of the palette's accent colours, chosen by catalog position.
- Focus and selection look different: the focused card has an accent ring; the card a menu or dialog is about keeps an accent-tinted fill while focus is in the menu.
- `main.gd` uses `res://src/ports.gd` when it exists and `ports_fake.gd` otherwise. For screenshots and UI checks, `--fake-ports [SCENARIO]` after `--` forces the fake (`anchorage -- --fake-ports`, `godot --path app -- --fake-ports offline`); the scenarios are listed in `ports_fake.gd`.

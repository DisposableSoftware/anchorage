# Appearance

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `LOOK-1` | The UI is laid out for 1280×720 and scales with the window (stretch mode `canvas_items`, aspect `expand`): at 1280×720, 1280×800, 1920×1080 and 3840×2160 the layout is the same in logical px, and text is drawn at the window's full resolution, never upscaled. | done | `scripts/manual/resolutions.sh` (headless at each size: screenshot; the window has the requested size) |
| `LOOK-2` | One Godot `Theme` is built at startup from the flavour's palette and the accent, and every scene takes its colours from it. Scenes and scripts never contain hex colours. Style guide: palette.md. | planned | unit tests on the theme; manual |
| `LOOK-3` | Four Catppuccin palettes (`latte`, `frappe`, `macchiato`, `mocha`) ship in the app as data, with the values from the style guide's `reference/themes/` unmodified. Style guide: palette.md, "Flavours". | planned | unit test (every palette defines the 26 names and matches the style guide's values) |
| `LOOK-4` | A palette derived from the GTK theme (`flavor = gtk`). | dropped | no GTK in this app. |
| `LOOK-5` | Styling is flat: no gradients or shadows. The focused control is always clearly highlighted, readable from a couch on a 720p screen. Style guide: principles.md rules 1, 2, 6, 9. | planned | manual (screenshot at 1280×720) |
| `LOOK-6` | The window background is the flavour's `base`, fully opaque. The UI font is a bundled font, in sizes that stay readable at 1280×720. Style guide: principles.md rules 4 and 7. | planned | manual (screenshot) |
| `LOOK-7` | A user `style.css`. | dropped | no CSS in this app. |
| `LOOK-8` | The focus highlight keeps a contrast of at least 3:1 against `base` for every flavour and accent. Style guide: palette.md. | planned | unit test over all flavours and accents |

## Implementation notes

- The [style guide](https://github.com/DisposableSoftware/style-guide) describes the shared look; this file wins on conflict. Catppuccin belongs to the Catppuccin community (https://catppuccin.com).
- The project sets the base size and stretch in `app/project.godot` (`display/window/size/viewport_*`, `display/window/stretch/*`). Don't set pixel sizes in code against the real window size.
- The renderer is GL Compatibility: it starts fast, runs under gamescope on the Steam Deck and in a headless compositor, and a launcher needs nothing more.

# Appearance

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `LOOK-1` | The UI is laid out for 1280×720 and scales with the window (stretch mode `canvas_items`, aspect `expand`): at 1280×720, 1280×800, 1920×1080 and 3840×2160 the layout is the same in logical px, and text is drawn at the window's full resolution, never upscaled. | done | `scripts/manual/resolutions.sh` (headless at each size: screenshot; the window has the requested size) |
| `LOOK-2` | One Godot `Theme` is built at startup from the flavour's palette and the accent, and every scene takes its colours from it. Scenes and scripts never contain hex colours. Style guide: palette.md. | done | `test_theme::test_theme_uses_the_flavour_and_accent`, `test_theme::test_no_colour_literals_outside_the_palette`; screenshots (`scripts/manual/shots.sh`, every flavour by `FLAVOR`) |
| `LOOK-3` | Four Catppuccin palettes (`latte`, `frappe`, `macchiato`, `mocha`) ship in the app as data, with the values from the style guide's `reference/themes/` unmodified. Style guide: palette.md, "Flavours". | done | `test_palette` (26 names per flavour; values equal to `data/themes/*.css`, whose sha256 matches the style guide's files) |
| `LOOK-4` | A palette derived from the GTK theme (`flavor = gtk`). | dropped | no GTK in this app. |
| `LOOK-5` | Styling is flat: no gradients or shadows. The focused control is always clearly highlighted, readable from a couch on a 720p screen. Style guide: principles.md rules 1, 2, 6, 9. | done | `test_theme::test_theme_uses_the_flavour_and_accent` (4 px ring, no shadow, selection is a fill); `scripts/manual/home.sh` (finds the ring by colour at 1280×720); screenshots (`scripts/manual/shots.sh`) |
| `LOOK-6` | The window background is the flavour's `base`, fully opaque. The UI font is a bundled font, in sizes that stay readable at 1280×720. Style guide: principles.md rules 4 and 7. | done | `test_theme::test_bundled_font_and_no_text_under_20px` (Inter, nothing under 20 px); `scripts/manual/home.sh` (the background pixel is `base`); screenshots at 1280×720, 1280×800 and 1920×1080 |
| `LOOK-7` | A user `style.css`. | dropped | no CSS in this app. |
| `LOOK-8` | The focus highlight keeps a contrast of at least 3:1 against `base` for every flavour and accent. Style guide: palette.md. | done | `test_theme::test_focus_ring_has_3_to_1_against_base_everywhere` (4 flavours × 14 accents) |
| `LOOK-9` | The layout suits 16:10 as well as 16:9: at 1280×800 (Steam Deck), 1920×1200 and 2560×1600 as well as 1280×720, 1920×1080 and 3840×2160, nothing is clipped, cropped or left empty at the edges, the extra height goes to larger content (a taller art tile that shows more of the cover, more room in the detail panel) rather than to gaps, and the first-launch notes and the ROM folder chooser fit. No setting is needed: the layout follows the window. | planned | `scripts/manual/resolutions.sh` extended to 16:10 sizes with screenshots; `test_home_row` at 1280×800 and 1920×1200 |

## Implementation notes

- The [style guide](https://github.com/DisposableSoftware/style-guide) describes the shared look; this file wins on conflict. Catppuccin belongs to the Catppuccin community (https://catppuccin.com).
- The project sets the base size and stretch in `app/project.godot` (`display/window/size/viewport_*`, `display/window/stretch/*`). Don't set pixel sizes in code against the real window size.
- The palettes are `app/src/palette.gd`, the only place with hex colours. `data/themes/<flavour>.css` are byte-identical copies of the style guide's `reference/themes/`, which `test_palette` compares the data against.
- The focus colour is the accent. Where the accent is under 3:1 against `base` (some latte accents), it is darkened (lightened on a dark flavour) in 5 % steps until it reaches 3:1 (`LOOK-8`). Badge, button and pad-glyph text gets the same treatment against its own background, to 4.5:1. Mixing toward `text` instead turns every latte colour the same grey.
- The bundled font is [Inter](https://github.com/rsms/inter) (variable, SIL Open Font License 1.1, `app/fonts/` with its licence), at weight 400 and 700 only. A `SystemFont` was tried and rejected: it resolves to whatever the user's fontconfig prefers (a monospace font on the dev machine), so the layout would differ per machine. Godot's built-in font has only one weight (Open Sans SemiBold).
- The renderer is GL Compatibility: it starts fast, runs under gamescope on the Steam Deck and in a headless compositor, and a launcher needs nothing more.

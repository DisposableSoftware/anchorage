# Cover art

Each port card can show cover art from [SteamGridDB](https://www.steamgriddb.com). The art is chosen once, by hand, so the cards look like one set; Anchorage only downloads the chosen files.

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `ART-1` | A catalog entry may have an `art` object: `url` (a SteamGridDB CDN image), `author` (the artist's name on SteamGridDB), `source` (the asset's page on steamgriddb.com) and `style` (the SteamGridDB style it was chosen from). A port without `art` shows its monogram card. | done | `test_catalog::test_art_is_optional_and_a_bad_object_is_dropped_but_the_port_stays`, `test_art_needs_every_field_and_a_steamgriddb_url` |
| `ART-2` | All art in the catalog is horizontal (SteamGridDB 920×430 grids) and comes from the same SteamGridDB style, picked by hand for consistency. | done | `test_catalog::test_shipped_art_is_complete_and_all_one_style` (all four ports: 920x430 PNG, style `alternate`, checked once by hand against the CDN) |
| `ART-3` | At start, in the background, Anchorage downloads each port's art into `$XDG_CACHE_HOME/anchorage/art/`, named by the hash of its URL, so a changed URL fetches again and an unchanged one never does. It sends no API key and needs none. | done | `test_art` (download once, cache hit, changed URL, corrupt cache replaced, no key), `test_ports_starts_the_art_at_start_and_announces_it`; `scripts/manual/art.sh` (real CDN, four files cached, no `.part` left) |
| `ART-4` | Art is downloaded only from `https://cdn2.steamgriddb.com/` or `https://cdn.steamgriddb.com/`, at most 5 MiB per file, and used only if Godot decodes it as PNG, JPEG or WebP at no more than 4096×4096. Anything else is deleted and ignored. | done | `test_art` (wrong host or scheme, redirect check, over 5 MiB, not an image, truncated, over 4096 px, forged header, PNG, JPEG and WebP) |
| `ART-5` | The card shows the art in the place of the monogram tile, scaled to cover it without distortion, with the same rounded corners. The title, port name and badge stay as text below it, so the card reads without the art. | done | `scripts/manual/art.sh` and `shots.sh` screenshots at 1280x720, 1280x800 and 1920x1080; `test_home::test_cards_with_art_show_it_and_the_others_keep_the_monogram` |
| `ART-6` | While the art is missing, offline, or rejected, the card shows the monogram, with no error and no layout change. When the art arrives the card updates without moving focus. | done | `test_art` (failed, offline and rejected files show nothing, no error, `changed` on arrival), `test_home::test_art_arriving_changes_the_tile_not_the_layout_or_the_focus` |
| `ART-7` | The README credits SteamGridDB and lists every artist and asset page from the catalog. | planned | manual |

## Implementation notes

- Curation uses the SteamGridDB API (`/api/v2/grids/game/<id>?dimensions=920x430&styles=...`) with a personal API key held outside the repo (`STEAMGRIDDB_API_KEY`); the key is never stored or sent by the app.
- Asset licences are the uploaders' own, so the art is not bundled in the repository or the AppImage: it is fetched to the user's cache.
- The loader decodes with `Image.load_from_file` or `load_*_from_buffer` and builds an `ImageTexture` on the main thread after the worker finishes.

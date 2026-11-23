# Cover art

Each port card can show cover art from [SteamGridDB](https://www.steamgriddb.com). The art is chosen once, by hand, so the four cards look like one set; Anchorage only downloads the chosen files.

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `ART-1` | A catalog entry may have an `art` object: `url` (a SteamGridDB CDN image), `author` (the artist's name on SteamGridDB), `source` (the asset's page on steamgriddb.com) and `style` (the SteamGridDB style it was chosen from). A port without `art` shows its monogram card. | planned | `test_catalog` |
| `ART-2` | All art in the catalog is horizontal (SteamGridDB 920×430 grids) and comes from the same SteamGridDB style, picked by hand for consistency. | planned | `test_catalog` (every entry has `style`, and they are all equal) |
| `ART-3` | At start, in the background, Anchorage downloads each port's art into `$XDG_CACHE_HOME/anchorage/art/`, named by the hash of its URL, so a changed URL fetches again and an unchanged one never does. It sends no API key and needs none. | planned | `test_art` (fake HTTP: download once, cache hit, changed URL) |
| `ART-4` | Art is downloaded only from `https://cdn2.steamgriddb.com/` or `https://cdn.steamgriddb.com/`, at most 5 MiB per file, and used only if Godot decodes it as PNG, JPEG or WebP at no more than 4096×4096. Anything else is deleted and ignored. | planned | `test_art` |
| `ART-5` | The card shows the art in the place of the monogram tile, scaled to cover it without distortion, with the same rounded corners. The title, port name and badge stay as text below it, so the card reads without the art. | planned | `scripts/manual/home.sh` (screenshot); `test_home` |
| `ART-6` | While the art is missing, offline, or rejected, the card shows the monogram, with no error and no layout change. When the art arrives the card updates without moving focus. | planned | `test_art`; `test_home` |
| `ART-7` | The README credits SteamGridDB and lists every artist and asset page from the catalog. | planned | manual |

## Implementation notes

- Curation uses the SteamGridDB API (`/api/v2/grids/game/<id>?dimensions=920x430&styles=...`) with a personal API key held outside the repo (`STEAMGRIDDB_API_KEY`); the key is never stored or sent by the app.
- Asset licences are the uploaders' own, so the art is not bundled in the repository or the AppImage: it is fetched to the user's cache.
- The loader decodes with `Image.load_from_file` or `load_*_from_buffer` and builds an `ImageTexture` on the main thread after the worker finishes.

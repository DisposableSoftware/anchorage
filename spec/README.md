# Anchorage: specification

This folder is the source of truth for what Anchorage does. The code implements the spec. If the code and the spec disagree, the code is wrong, or the spec must be changed first.

## Files

| File | Prefix | Covers |
|------|--------|--------|
| [product.md](product.md) | `PROD` | Goals, non-goals, platform and stack constraints |
| [window.md](window.md) | `WIN` | Windows and what they show |
| [keybindings.md](keybindings.md) | `KEY` | Default bindings, user overrides |
| [appearance.md](appearance.md) | `LOOK` | Styling and display scale |
| [home.md](home.md) | `HOME` | The home screen: port cards, details, actions, hint bar |
| [update.md](update.md) | `UPD` | Updating Anchorage itself from Game Mode |
| [ports.md](ports.md) | `PORT` | Catalog, install, update, launch, remove |
| [art.md](art.md) | `ART` | Cover art from SteamGridDB |
| [roms.md](roms.md) | `ROM` | Finding and preparing the user's ROMs |
| [configuration.md](configuration.md) | `CONF` | `config.ini` and `keybindings.ini` |
| [integration.md](integration.md) | `INT` | XDG/freedesktop, desktop entry, Nix, command line, man page |
| [roadmap.md](roadmap.md) | — | The order of planned work, which `/implement` follows |

Add a file with a new prefix when a feature area doesn't fit these, and list it here.

## Requirement format

Each requirement is one line in a table:

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `WIN-1` | One sentence that can be checked. | done | `module::tests::name` |

- **IDs are permanent.** Do not renumber them or reuse one. When a requirement is dropped, keep its row, set the status to `dropped`, and give the reason.
- **Status** is one of:
  - `planned`: agreed but not built.
  - `partial`: built, but with a known gap. The gap is written in the row.
  - `done`: built and verified.
  - `dropped`: no longer wanted.
- Write behaviour, not implementation. Keep the "how" short, and put it under **Implementation notes** when it is not obvious or a past attempt failed.
- **Verified by** names the test, or says `manual` with what to check.

`scripts/release-check.sh` reads the status column: a requirement that became `done` or `partial` since the last release means a minor bump. `/release` pushes `main` and acts on that recommendation.

## Machine-checked sections

Tables between `<!-- spec:NAME:begin -->` and `<!-- spec:NAME:end -->` markers are parsed by `app/tests/test_spec.gd`. `scripts/test.sh` (and so `nix build`) fails when they disagree with the code or `app/data/config.example.ini` and `app/data/keybindings.example.ini`. Keep their column layout unchanged.

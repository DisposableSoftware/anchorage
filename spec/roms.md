# ROMs

Anchorage finds the user's own ROM files and hands the right one to each port. It never downloads or distributes ROMs.

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `ROM-1` | The ROM folder is `[roms] directory` (`CONF-8`), default `~/Roms/n64`, with `~` expanded. A missing or unreadable folder is a normal state ("ROM folder not found"), not an error. | planned | `test_roms` |
| `ROM-2` | A scan looks at the files directly in the folder (no recursion) with the extensions `.z64`, `.n64`, `.v64` or `.zip`. Every ROM-like entry of a zip with a size of at most 64 MiB is a candidate. Other files are ignored. | planned | `test_roms` (temp folder with all kinds) |
| `ROM-3` | A candidate is identified by the SHA1 of its data converted to big-endian (`.z64`) order, looked up in the catalog's hash lists (`PORT-1`). A file whose hash no port accepts is ignored. | planned | `test_roms` (fabricated ROM data with known hashes in each byte order) |
| `ROM-4` | Scans run on a worker thread, and the result is cached in `state.ini` by path, size and modification time, so unchanged files are not hashed again. The UI never waits for a scan. | planned | `test_roms` (cache hit skips hashing); manual (the UI stays responsive) |
| `ROM-5` | The folder is scanned at start, on `refresh` (`HOME-6`) and after an install. | planned | `test_ports` |
| `ROM-6` | Anchorage only reads the ROM folder. It never writes, moves, renames or deletes anything in it. | planned | `test_roms` (folder contents and mtimes unchanged after a scan and a prepare) |
| `ROM-7` | When several files or zip entries match one port, the catalog's hash order decides which is used (the first hash of the list wins), then the file name. | planned | `test_roms` |
| `ROM-8` | Preparing a ROM for a port writes the identified data as a big-endian `.z64` named by the catalog into the port's data folder, streamed from a zip entry when the source is a zip. | planned | `test_roms` |
| `ROM-9` | When no ROM matches a port, the port shows which game versions it accepts (from the catalog) and the folder that was scanned. | planned | `test_ports` |

## Implementation notes

- `app/src/roms.gd` does scanning, hashing and preparing; `ports.gd` owns the thread and the cache.
- Godot's `ZIPReader` reads zip entries, and `HashingContext` computes SHA1. Byte order is detected from the first four bytes of the data: `80 37 12 40` is z64, `37 80 40 12` is v64, `40 12 37 80` is n64.
- A ROM is at most 64 MiB, so holding one in memory while hashing is fine.

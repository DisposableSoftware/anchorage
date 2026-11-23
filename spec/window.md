# Window

## Requirements

| ID | Requirement | Status | Verified by |
|----|-------------|--------|-------------|
| `WIN-1` | Starting the app opens a window titled "Anchorage" that shows the home screen (`HOME-1`), at the size from `[window] width` and `height` (`CONF-4`). | done | `scripts/manual/smoke.sh` (screenshot; the window is 1280×720 logical px by default). The nixpkgs `godot` is a debug build and appends " (DEBUG)" to the title; the self-contained release build (`INT-25`) does not. |
| `WIN-2` | The app is single-instance: starting it again while it runs opens another window in the running process. | dropped | superseded: Anchorage is one fullscreen screen that Steam starts once, and Godot has no multi-window application model to share between processes. |
| `WIN-3` | The window has the Wayland app ID `io.github.DisposableSoftware.Anchorage`, so compositor window rules match it. | done | `scripts/manual/smoke.sh` (headless: `swaymsg` reports the app ID) |
| `WIN-4` | `quit` closes the window and quits the app. Closing the window by any other means quits it too. | done | `scripts/manual/smoke.sh` |
| `WIN-5` | The shortcut overlay. | dropped | superseded: a controller-first app shows a button hint bar on every screen (`PROD-7`), which the first `/feature` specifies. |

## Implementation notes

- The Wayland app ID comes from `application/config/name` in `app/project.godot`, which is why that setting holds the reverse-DNS ID. The window title is set in `main.gd`.

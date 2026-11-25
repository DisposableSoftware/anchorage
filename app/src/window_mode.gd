extends RefCounted
## WIN-6, CONF-10: fullscreen or windowed, from `[window] fullscreen` and the environment.

const SETTINGS := ["auto", "true", "false"]
## What gamescope and Steam put in the environment of what they start.
const VARIABLES := ["XDG_CURRENT_DESKTOP", "GAMESCOPE_WAYLAND_DISPLAY", "SteamGameId", "SteamAppId"]
## Windowed only: in fullscreen the compositor's size wins, whatever it is.
const MIN_SIZE := Vector2i(1280, 720)


## The variables `under_gamescope` reads, from this process (unset ones left out).
static func environment() -> Dictionary:
	var env := {}
	for name in VARIABLES:
		if OS.has_environment(name):
			env[name] = OS.get_environment(name)
	return env


## Gamescope (Game Mode), or Steam started the app.
static func under_gamescope(env: Dictionary) -> bool:
	for desktop in str(env.get("XDG_CURRENT_DESKTOP", "")).split(":", false):
		if desktop.to_lower() == "gamescope":
			return true
	for name in ["GAMESCOPE_WAYLAND_DISPLAY", "SteamGameId", "SteamAppId"]:
		if not str(env.get(name, "")).is_empty():
			return true
	return false


## {fullscreen: bool, size: Vector2i, min_size: Vector2i}. `setting` is `[window]
## fullscreen` (anything unknown counts as "auto"); `size` is `[window] width` and
## `height`. In fullscreen, size and min_size are zero: nothing is requested.
static func decide(setting: String, env: Dictionary, size: Vector2i) -> Dictionary:
	var fullscreen := under_gamescope(env)
	if setting == "true":
		fullscreen = true
	elif setting == "false":
		fullscreen = false
	if fullscreen:
		return {"fullscreen": true, "size": Vector2i.ZERO, "min_size": Vector2i.ZERO}
	return {"fullscreen": false, "size": size, "min_size": MIN_SIZE}


## Applies `decide`'s result. MODE_FULLSCREEN, not MODE_EXCLUSIVE_FULLSCREEN: on Wayland
## both send the same xdg_toplevel.set_fullscreen, and on X11 (gamescope's Xwayland, which
## the release build uses) both set _NET_WM_STATE_FULLSCREEN, the state gamescope resizes
## a window to the output for; exclusive only adds a compositor-bypass hint.
static func apply(window: Window, mode: Dictionary) -> void:
	if mode["fullscreen"]:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.min_size = mode["min_size"]
	if window.mode == Window.MODE_WINDOWED:
		window.size = mode["size"]

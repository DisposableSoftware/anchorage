extends "res://tests/case.gd"
## WIN-6, CONF-10: the fullscreen decision from fake environments.

const WindowMode := preload("res://src/window_mode.gd")
const SIZE := Vector2i(1600, 900)
const FULLSCREEN := {"fullscreen": true, "size": Vector2i.ZERO, "min_size": Vector2i.ZERO}
const WINDOWED := {"fullscreen": false, "size": SIZE, "min_size": Vector2i(1280, 720)}
## What Steam's Game Mode sets, each on its own.
const GAMESCOPE := [
	{"XDG_CURRENT_DESKTOP": "gamescope"},
	{"GAMESCOPE_WAYLAND_DISPLAY": "gamescope-0"},
	{"SteamGameId": "15790555012393680896"},
	{"SteamAppId": "0"},
]
const DESKTOPS := [
	{},
	{"XDG_CURRENT_DESKTOP": "KDE"},
	{"XDG_CURRENT_DESKTOP": "Hyprland"},
	{"XDG_CURRENT_DESKTOP": "GNOME:ubuntu"},
	{"GAMESCOPE_WAYLAND_DISPLAY": "", "SteamGameId": "", "SteamAppId": ""},
]


func test_each_gamescope_variable_alone_means_fullscreen() -> void:
	for env in GAMESCOPE:
		eq(WindowMode.decide("auto", env, SIZE), FULLSCREEN, "auto with %s" % env)
	var everything := {}
	for env in GAMESCOPE:
		everything.merge(env)
	eq(WindowMode.decide("auto", everything, SIZE), FULLSCREEN, "all of them")
	var listed := {"XDG_CURRENT_DESKTOP": "KDE:gamescope"}
	eq(WindowMode.decide("auto", listed, SIZE), FULLSCREEN, "gamescope as one item of a list")


func test_a_desktop_stays_windowed_at_the_configured_size() -> void:
	for env in DESKTOPS:
		eq(WindowMode.decide("auto", env, SIZE), WINDOWED, "auto with %s" % env)


func test_the_setting_overrides_the_detection() -> void:
	for env in DESKTOPS:
		eq(WindowMode.decide("true", env, SIZE), FULLSCREEN, "true with %s" % env)
	for env in GAMESCOPE:
		eq(WindowMode.decide("false", env, SIZE), WINDOWED, "false with %s" % env)


func test_an_unknown_setting_counts_as_auto() -> void:
	for value in ["", "yes", "TRUE", "on", "1", "fullscreen"]:
		eq(WindowMode.decide(value, GAMESCOPE[1], SIZE), FULLSCREEN, "'%s' in gamescope" % value)
		eq(WindowMode.decide(value, {}, SIZE), WINDOWED, "'%s' on a desktop" % value)


func test_fullscreen_requests_no_size() -> void:
	var mode := WindowMode.decide("true", {}, Vector2i(8192, 8192))
	eq([mode["size"], mode["min_size"]], [Vector2i.ZERO, Vector2i.ZERO], "nothing to fight")


func test_the_environment_is_read_from_this_process() -> void:
	var saved := {}
	for name in WindowMode.VARIABLES:
		if OS.has_environment(name):
			saved[name] = OS.get_environment(name)
		OS.unset_environment(name)
	eq(WindowMode.environment(), {}, "nothing set")
	OS.set_environment("SteamAppId", "0")
	OS.set_environment("XDG_CURRENT_DESKTOP", "gamescope")
	eq(
		WindowMode.environment(),
		{"SteamAppId": "0", "XDG_CURRENT_DESKTOP": "gamescope"},
		"only the four names, as set"
	)
	for name in WindowMode.VARIABLES:
		OS.unset_environment(name)
	for name in saved:
		OS.set_environment(name, saved[name])

extends RefCounted
## config.ini and keybindings.ini (CONF-1 .. CONF-10, KEY-2).

const Ini := preload("res://src/ini.gd")
const Palette := preload("res://src/palette.gd")
const WindowMode := preload("res://src/window_mode.gd")
const CONFIG_EXAMPLE := "res://data/config.example.ini"
const KEYBINDINGS_EXAMPLE := "res://data/keybindings.example.ini"

## Defaults; spec/configuration.md lists the same values and spec_tests checks them.
var width := 1280
var height := 720
## "auto", "true" or "false" (CONF-10); window_mode.gd decides.
var fullscreen := "auto"
var flavor := Palette.DEFAULT_FLAVOR
var accent := Palette.DEFAULT_ACCENT
## As written, `~` not expanded: the ROM scanner expands it (ROM-1).
var roms_directory := "~/Roms/n64"
## True when config.ini sets `[roms] directory`: it then wins over the app (ROM-12).
var roms_directory_set := false
var check_updates := true
## Overrides from keybindings.ini: name -> PackedStringArray of tokens (see keys.gd).
var keybindings := {}


## $XDG_CONFIG_HOME/anchorage
static func dir() -> String:
	return OS.get_config_dir().path_join("anchorage")


## Reads both files from `path`, first creating whichever is missing (CONF-3).
static func load_from(path: String) -> RefCounted:
	var cfg := new()
	create_missing(path)
	var settings := _read(path.path_join("config.ini"))
	cfg.width = clampi(_int(settings, "window", "width", cfg.width), 1280, 8192)
	cfg.height = clampi(_int(settings, "window", "height", cfg.height), 720, 8192)
	cfg.fullscreen = _choice(settings, "window", "fullscreen", WindowMode.SETTINGS, cfg.fullscreen)
	cfg.flavor = _choice(settings, "appearance", "flavor", Palette.FLAVORS.keys(), cfg.flavor)
	cfg.accent = _choice(settings, "appearance", "accent", Palette.ACCENTS, cfg.accent)
	var roms: String = settings.get("roms", {}).get("directory", "")
	if not roms.is_empty():
		cfg.roms_directory = roms
		cfg.roms_directory_set = true
	cfg.check_updates = settings.get("ports", {}).get("check_updates", "true") != "false"
	var keys := _read(path.path_join("keybindings.ini")).get("keybindings", {}) as Dictionary
	for name in keys:
		cfg.keybindings[name] = Ini.split_list(keys[name])
	return cfg


## The value when it is one of `allowed`, else `fallback` (warned about when set).
static func _choice(
	settings: Dictionary, section: String, key: String, allowed: Array, fallback: String
) -> String:
	var value: String = settings.get(section, {}).get(key, "")
	if value.is_empty() or allowed.has(value):
		return fallback if value.is_empty() else value
	push_warning("config.ini: unknown %s '%s', using '%s'" % [key, value, fallback])
	return fallback


static func _int(settings: Dictionary, section: String, key: String, fallback: int) -> int:
	var value: String = settings.get(section, {}).get(key, "")
	return int(value) if value.is_valid_int() else fallback


## The parsed file, or {} when it is missing or unreadable (unreadable is warned about).
static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("%s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	return Ini.parse(file.get_as_text())


## `example` with every setting commented out, so the file documents the defaults
## without pinning them.
static func commented(example: String) -> String:
	var out := "# Created by Anchorage with every default commented out. To change one,\n"
	out += "# remove the leading '# ' and edit the value.\n"
	var lowercase := RegEx.create_from_string("^[a-z].* =")
	for line in example.split("\n"):
		if lowercase.search(line):
			out += "# "
		out += line + "\n"
	return out.trim_suffix("\n")


## Writes the commented examples for files missing from `path`. Anything already at the
## path, a dangling symlink included, is left alone.
static func create_missing(path: String) -> void:
	for pair in [["config.ini", CONFIG_EXAMPLE], ["keybindings.ini", KEYBINDINGS_EXAMPLE]]:
		var target: String = path.path_join(pair[0])
		if _exists(target):
			continue
		var example := FileAccess.get_file_as_string(pair[1])
		var made := DirAccess.make_dir_recursive_absolute(path)
		var file := FileAccess.open(target, FileAccess.WRITE) if made == OK else null
		if file == null:
			push_warning("could not create %s" % target)
			continue
		file.store_string(commented(example))


## True for a file, a symlink or a dangling symlink.
static func _exists(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())

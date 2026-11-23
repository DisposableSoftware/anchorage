extends RefCounted
## config.ini and keybindings.ini (CONF-1 .. CONF-5, KEY-2).

const Ini := preload("res://src/ini.gd")
const CONFIG_EXAMPLE := "res://data/config.example.ini"
const KEYBINDINGS_EXAMPLE := "res://data/keybindings.example.ini"

## Defaults; spec/configuration.md lists the same values and spec_tests checks them.
var width := 1280
var height := 720
var greeting := "Hello"
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
	cfg.greeting = settings.get("view", {}).get("greeting", cfg.greeting)
	var keys := _read(path.path_join("keybindings.ini")).get("keybindings", {}) as Dictionary
	for name in keys:
		cfg.keybindings[name] = Ini.split_list(keys[name])
	return cfg


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

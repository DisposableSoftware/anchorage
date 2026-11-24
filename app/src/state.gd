extends RefCounted
## What Anchorage remembers between runs (PORT-11): installed version and latest known tag
## per port, the time of the last update check, and the ROM scan cache. It lives in
## `$XDG_STATE_HOME/anchorage/state.ini`. Every setter saves, atomically; a missing or
## broken file means nothing is remembered.
##
## File layout (plain INI, read by `ini.gd`):
##   [ports]    <id>.installed = <tag>      <id>.latest = <tag>
##              <id>.archive = <tag that made the archive>   <id>.rom_placed = <path>
##   [updates]  last_check = <unix seconds>
##   [catalog]  last_check = <unix seconds>   version = <the fetched version last announced>
##              new = <ids of fetched ports not focused yet, comma separated> (PORT-23)
##   [roms]     cache = <one line of JSON>  (owned by the ROM code: path -> entry)
##              directory = <the ROM folder chosen in the app (ROM-12)>

const Ini := preload("res://src/ini.gd")
const FIELDS := ["installed", "latest", "archive", "rom_placed"]

var path := ""
var _ports := {}
var _last_check := 0
var _rom_cache := {}
var _rom_dir := ""
var _catalog := {"last_check": 0, "version": 0, "new": []}


## $XDG_STATE_HOME/anchorage/state.ini (default ~/.local/state).
static func default_path() -> String:
	var base := OS.get_environment("XDG_STATE_HOME")
	if base.is_empty() or not base.is_absolute_path():
		base = OS.get_environment("HOME").path_join(".local/state")
	return base.path_join("anchorage").path_join("state.ini")


static func load_from(file_path: String) -> RefCounted:
	var state := new()
	state.path = file_path
	if not FileAccess.file_exists(file_path):
		return state
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("%s: %s" % [file_path, error_string(FileAccess.get_open_error())])
		return state
	var parsed := Ini.parse(file.get_as_text())
	var ports: Dictionary = parsed.get("ports", {})
	for key in ports:
		var dot := (key as String).rfind(".")
		if dot < 1 or ports[key].is_empty():
			continue
		var id := (key as String).substr(0, dot)
		var field := (key as String).substr(dot + 1)
		if field in FIELDS:
			if not state._ports.has(id):
				state._ports[id] = {}
			state._ports[id][field] = ports[key]
	var last: String = parsed.get("updates", {}).get("last_check", "")
	state._last_check = int(last) if last.is_valid_int() else 0
	var json := JSON.new()
	if json.parse(parsed.get("roms", {}).get("cache", "")) == OK and json.data is Dictionary:
		state._rom_cache = json.data
	state._rom_dir = parsed.get("roms", {}).get("directory", "")
	var catalog: Dictionary = parsed.get("catalog", {})
	state._catalog["last_check"] = _int(catalog.get("last_check", ""))
	state._catalog["version"] = _int(catalog.get("version", ""))
	var id := RegEx.create_from_string("^[a-z0-9_-]{1,32}$")
	for item in (catalog.get("new", "") as String).split(",", false):
		var name := item.strip_edges()
		if id.search(name) and name.length() == id.search(name).get_end():
			if not name in state._catalog["new"]:
				state._catalog["new"].append(name)
	return state


static func _int(text: String) -> int:
	return int(text) if text.is_valid_int() else 0


func installed_version(id: String) -> String:
	return _ports.get(id, {}).get("installed", "")


func set_installed(id: String, tag: String) -> void:
	_store(id, "installed", tag)


## Forgets the installed version (Remove, PORT-7).
func clear_installed(id: String) -> void:
	_store(id, "installed", "")


func latest_version(id: String) -> String:
	return _ports.get(id, {}).get("latest", "")


func set_latest(id: String, tag: String) -> void:
	_store(id, "latest", tag)


## The installed version that made the port's archive, or kept it (PORT-9).
func archive_version(id: String) -> String:
	return _ports.get(id, {}).get("archive", "")


func set_archive_version(id: String, tag: String) -> void:
	_store(id, "archive", tag)


## The ROM copy Anchorage wrote for the port, so only that is ever deleted (PORT-9).
func placed_rom(id: String) -> String:
	return _ports.get(id, {}).get("rom_placed", "")


func set_placed_rom(id: String, path: String) -> void:
	if placed_rom(id) != path:
		_store(id, "rom_placed", path)


## Unix seconds of the last successful update check, 0 when never.
func last_check() -> int:
	return _last_check


func set_last_check(unix_time: int) -> void:
	_last_check = unix_time
	save()


func rom_cache() -> Dictionary:
	return _rom_cache


func set_rom_cache(cache: Dictionary) -> void:
	_rom_cache = cache
	save()


## The ROM folder chosen in the app, "" when none was (ROM-12).
func rom_dir() -> String:
	return _rom_dir


func set_rom_dir(dir: String) -> void:
	_rom_dir = _line(dir)
	save()


## The fetched catalog's part (a copy): {last_check: unix seconds of the last successful
## fetch, 0 when never (PORT-18); version: the highest fetched version announced; new: ids
## of fetched ports not focused yet (PORT-23)}.
func catalog() -> Dictionary:
	return _catalog.duplicate(true)


## Changes some of `catalog()`'s keys, and saves when that changed anything.
func set_catalog(changes: Dictionary) -> void:
	var next := _catalog.duplicate(true)
	for key in changes:
		if next.has(key):
			next[key] = changes[key]
	var ids := []
	for id in next["new"]:
		var clean := _line(str(id)).replace(",", "")
		if not clean.is_empty() and not clean in ids:
			ids.append(clean)
	next["new"] = ids
	next["last_check"] = int(next["last_check"])
	next["version"] = int(next["version"])
	if next != _catalog:
		_catalog = next
		save()


## Writes a temp file beside the real one and renames it over, so a kill never leaves a
## half-written state.ini. Returns false (and warns) when it could not.
func save() -> bool:
	if path.is_empty():
		return false
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		push_warning("%s: %s" % [path, error_string(err)])
		return false
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("%s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(_serialise())
	file.close()
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("%s: %s" % [path, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return false
	return true


func _store(id: String, field: String, value: String) -> void:
	if not _ports.has(id):
		_ports[id] = {}
	_ports[id][field] = value
	save()


func _serialise() -> String:
	var out := "# Anchorage remembers these between runs. Safe to delete.\n[ports]\n"
	var ids := _ports.keys()
	ids.sort()
	for id in ids:
		for field in FIELDS:
			var value := _line(_ports[id].get(field, ""))
			if not value.is_empty():
				out += "%s.%s = %s\n" % [_line(id), field, value]
	out += "\n[updates]\nlast_check = %d\n" % _last_check
	if _catalog != {"last_check": 0, "version": 0, "new": []}:
		out += "\n[catalog]\nlast_check = %d\n" % _catalog["last_check"]
		out += "version = %d\n" % _catalog["version"]
		if not _catalog["new"].is_empty():
			out += "new = %s\n" % ",".join(PackedStringArray(_catalog["new"]))
	if not _rom_cache.is_empty() or not _rom_dir.is_empty():
		out += "\n[roms]\n"
	if not _rom_dir.is_empty():
		out += "directory = %s\n" % _rom_dir
	if not _rom_cache.is_empty():
		out += "cache = %s\n" % JSON.stringify(_rom_cache)
	return out


static func _line(value: String) -> String:
	return value.replace("\n", " ").replace("\r", " ").strip_edges()

extends RefCounted
## Where the ROM folder is (ROM-10, ROM-14, ROM-15, ROM-16) and folder listings for the
## chooser (ROM-11). Pure functions over a home folder, a media folder (/run/media) and the
## text of /proc/self/mounts, so tests use fake trees. Nothing here writes, and the EmuDeck
## and RetroDECK files are read as text, never run.

const Ini := preload("res://src/ini.gd")
const Roms := preload("res://src/roms.gd")

const FILE_EXTENSIONS := ["z64", "n64", "v64", "zip"]
const MEDIA := "/run/media"
const MOUNTS_FILE := "/proc/self/mounts"
const SEARCH_DEPTH := 4
const MAX_SEARCH_FOLDERS := 20000
const MAX_SETTINGS_BYTES := 1 << 20
## Current EmuDeck first (vars.sh: emudeckFolder="$HOME/.config/EmuDeck"), then the old one.
const EMUDECK_SETTINGS := [".config/EmuDeck/settings.sh", "emudeck/settings.sh"]
const RETRODECK_CONFIG := ".var/app/net.retrodeck.retrodeck/config/retrodeck"
const HOME_FOLDERS := ["Emulation/roms/n64", "retrodeck/roms/n64", "Roms/n64"]
const MOUNT_FOLDERS := ["Emulation/roms/n64", "retrodeck/roms/n64", "roms/n64", "ROMs/n64", "n64"]
const DEVICE_NAME := "^(mmcblk\\d+p\\d+|sd[a-z]+\\d*|nvme\\d+n\\d+p\\d+)$"


## Runs `search` on a worker thread (ROM-14). Keep a reference until `finished` fires, and
## call `abort` and `join` before the app exits.
class SearchJob:
	extends RefCounted

	signal finished(result: Dictionary)

	var result := {}
	var _thread: Thread
	var _delivered := false
	var _self_ref: RefCounted
	var _lock := Mutex.new()
	var _abort := false

	func start(media: String, mounts_file: String, depth: int = SEARCH_DEPTH) -> void:
		_self_ref = self
		_thread = Thread.new()
		_thread.start(_run.bind(media, mounts_file, depth))

	## Asks the search to stop at the next folder; `finished` still comes, with status
	## "aborted".
	func abort() -> void:
		_lock.lock()
		_abort = true
		_lock.unlock()

	func join() -> void:
		_deliver()

	func _stopped() -> bool:
		_lock.lock()
		var stop := _abort
		_lock.unlock()
		return stop

	func _run(media: String, mounts_file: String, depth: int) -> void:
		var script: GDScript = load("res://src/rom_folders.gd")
		var mounts: Array = script.mounts(media, script.read_mounts(mounts_file))
		result = script.search(mounts, depth, _stopped)
		_deliver.call_deferred()

	func _deliver() -> void:
		if _delivered or _thread == null:
			return
		_delivered = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_self_ref = null
		finished.emit(result)


## The number of ROM-like files directly in `dir` (ROM-2's extensions), 0 when unreadable.
static func rom_count(dir: String) -> int:
	var access := DirAccess.open(dir)
	if access == null:
		return 0
	var count := 0
	for name in access.get_files():
		if name.get_extension().to_lower() in FILE_EXTENSIONS:
			count += 1
	return count


## `path` with `home` shown as `~`.
static func display(path: String, home: String) -> String:
	if path == home:
		return "~"
	if not home.is_empty() and path.begins_with(home + "/"):
		return "~/" + path.substr(home.length() + 1)
	return path


## A shell value as written: one layer of quotes removed (else a trailing ` # comment`),
## `$HOME`, `${HOME}` and a leading `~` expanded. "" when the result is not absolute.
static func expand(raw: String, home: String) -> String:
	var value := raw.strip_edges()
	if value.length() >= 1 and value[0] in ['"', "'"]:
		var close := value.find(value[0], 1)
		value = value.substr(1, close - 1) if close > 0 else value.substr(1)
	else:
		var comment := RegEx.create_from_string("\\s#").search(value)
		if comment != null:
			value = value.substr(0, comment.get_start())
	value = value.strip_edges().replace("${HOME}", home).replace("$HOME", home)
	if value == "~":
		value = home
	elif value.begins_with("~/"):
		value = home.path_join(value.substr(2))
	if not value.is_absolute_path():
		return ""
	return value.simplify_path()


## The roms folder (without `n64`) a settings.sh names (ROM-15), or "".
static func parse_emudeck(text: String, home: String) -> String:
	var line_re := RegEx.create_from_string("^(?:export\\s+)?(romsPath|emulationPath)=(.*)$")
	var values := {}
	for raw in text.split("\n"):
		var m := line_re.search(raw.strip_edges())
		if m != null:
			values[m.get_string(1)] = expand(m.get_string(2), home)
	if not values.get("romsPath", "").is_empty():
		return values["romsPath"]
	if not values.get("emulationPath", "").is_empty():
		return String(values["emulationPath"]).path_join("roms")
	return ""


## The roms folder (without `n64`) a retrodeck.json names (ROM-16), or "".
static func parse_retrodeck_json(text: String, home: String) -> String:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return ""
	var paths: Variant = json.data.get("paths")
	if not paths is Dictionary:
		return ""
	var roms: Variant = paths.get("roms_path")
	if roms is String and not expand(roms, home).is_empty():
		return expand(roms, home)
	var rd_home: Variant = paths.get("rd_home_path")
	if rd_home is String and not expand(rd_home, home).is_empty():
		return expand(rd_home, home).path_join("roms")
	return ""


## The roms folder (without `n64`) an old INI retrodeck.cfg names (ROM-16), or "". Keys
## are taken from `[paths]`, or from any section when `[paths]` has none.
static func parse_retrodeck_cfg(text: String, home: String) -> String:
	var parsed := Ini.parse(text)
	var sections := ["paths"] + parsed.keys().filter(func(s: String) -> bool: return s != "paths")
	for key in ["roms_folder", "rdhome"]:
		for section in sections:
			var value := expand(parsed.get(section, {}).get(key, ""), home)
			if not value.is_empty():
				return value if key == "roms_folder" else value.path_join("roms")
	return ""


## EmuDeck's N64 folder from its settings, or "" (ROM-15).
static func emudeck_folder(home: String) -> String:
	for name in EMUDECK_SETTINGS:
		var path: String = home.path_join(name)
		if FileAccess.file_exists(path):
			var roms := parse_emudeck(_read(path), home)
			return roms.path_join("n64") if not roms.is_empty() else ""
	return ""


## RetroDECK's N64 folder from retrodeck.json, else retrodeck.cfg, or "" (ROM-16).
static func retrodeck_folder(home: String) -> String:
	var dir := home.path_join(RETRODECK_CONFIG)
	var roms := ""
	if FileAccess.file_exists(dir.path_join("retrodeck.json")):
		roms = parse_retrodeck_json(_read(dir.path_join("retrodeck.json")), home)
	if roms.is_empty() and FileAccess.file_exists(dir.path_join("retrodeck.cfg")):
		roms = parse_retrodeck_cfg(_read(dir.path_join("retrodeck.cfg")), home)
	return roms.path_join("n64") if not roms.is_empty() else ""


## `path` (absolute) with each missing part matched case-insensitively against the folders
## that exist (exFAT ignores case, ext4 does not), or "" when a part has no match.
static func resolve_ci(path: String) -> String:
	if not path.is_absolute_path():
		return ""
	var current := "/"
	for part in path.simplify_path().split("/", false):
		var exact := current.path_join(part)
		if DirAccess.dir_exists_absolute(exact):
			current = exact
			continue
		var names := _subdirs(current, true)
		names.sort()
		var found := ""
		for name in names:
			if name.to_lower() == part.to_lower():
				found = name
				break
		if found.is_empty():
			return ""
		current = current.path_join(found)
	return current


## The text of /proc/self/mounts. Its size reads as 0, so it is read line by line.
static func read_mounts(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines := PackedStringArray()
	while true:
		var line := file.get_line()
		if file.eof_reached() and line.is_empty():
			break
		lines.append(line)
	return "\n".join(lines)


## Every mounted volume under `media`: [{path, label, sd}], the SD card first (a mmcblk
## device, or a mmcblk mount folder), then the rest by path. Both SteamOS styles count:
## `/run/media/mmcblk0p1` and `/run/media/<user>/<label>`. Paths that resolve to the same
## folder (newer SteamOS links the first to the second) are one volume, listed by its
## /proc/self/mounts path, else by its real path.
static func mounts(media: String, mounts_text: String) -> Array:
	var devices := {}
	for line in mounts_text.split("\n"):
		var fields := line.split(" ", false)
		if fields.size() < 2:
			continue
		var point := _unescape(fields[1])
		if point.begins_with(media + "/"):
			devices[point] = fields[0]
	var device_name := RegEx.create_from_string(DEVICE_NAME)
	var points := {}
	for name in _subdirs(media, false):
		var path := media.path_join(name)
		if devices.has(path) or device_name.search(name) != null:
			points[path] = true
		else:
			for child in _subdirs(path, false):
				points[path.path_join(child)] = true
	for point in devices:
		if DirAccess.dir_exists_absolute(point):
			points[point] = true
	var volumes := {}
	for path: String in points:
		var real := Roms.real_path(path)
		var sd: bool = (
			String(devices.get(path, "")).begins_with("/dev/mmcblk")
			or path.get_file().begins_with("mmcblk")
		)
		var rank := 0 if devices.has(path) else (1 if path == real else 2)
		var volume: Dictionary = volumes.get(real, {"path": path, "rank": rank, "sd": false})
		if rank < volume.rank:
			volume.path = path
			volume.rank = rank
		volume.sd = volume.sd or sd
		volumes[real] = volume
	var out := []
	for volume: Dictionary in volumes.values():
		var name: String = volume.path.get_file()
		var label := name
		if volume.sd:
			label = "SD card" if name.begins_with("mmcblk") else "SD card (%s)" % name
		out.append({"path": volume.path, "label": label, "sd": volume.sd})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a.sd and not b.sd or (a.sd == b.sd and a.path < b.path)
	)
	return out


## ROM-10's candidates in order: [{path, source}], `source` one of "emudeck", "retrodeck",
## "default" and "mount". Paths are as named, not yet matched for case.
static func candidates(home: String, mount_list: Array) -> Array:
	var out := []
	var emudeck := emudeck_folder(home)
	if not emudeck.is_empty():
		out.append({"path": emudeck, "source": "emudeck"})
	var retrodeck := retrodeck_folder(home)
	if not retrodeck.is_empty():
		out.append({"path": retrodeck, "source": "retrodeck"})
	for folder in HOME_FOLDERS:
		out.append({"path": home.path_join(folder), "source": "default"})
	for mount in mount_list:
		for folder in MOUNT_FOLDERS:
			out.append({"path": String(mount.path).path_join(folder), "source": "mount"})
	return out


## The first candidate (ROM-10 steps 1 to 3) that holds ROM-like files, as {path, source},
## or {path: "", source: ""} when none does (then the SD card search is next).
static func detect(home: String, media: String, mounts_text: String) -> Dictionary:
	var seen := {}
	for candidate in candidates(home, mounts(media, mounts_text)):
		var path := resolve_ci(candidate.path)
		if path.is_empty() or seen.has(path):
			continue
		seen[path] = true
		if rom_count(path) > 0:
			return {"path": path, "source": candidate.source}
	return {"path": "", "source": ""}


## Where ROM-10 ends when nothing is found.
static func fallback(home: String) -> String:
	if DirAccess.dir_exists_absolute(home.path_join("Emulation")):
		return home.path_join("Emulation/roms/n64")
	return home.path_join("Roms/n64")


## ROM-14: every folder with ROM-like files on `mount_list`, at most `depth` levels below
## each mount, hidden folders skipped. A folder link is followed only to a folder inside
## the same mount that was not searched yet, and at most `limit` folders are searched in
## all. Returns {status: "ok"|"no_card"|"aborted", limited, results: [{path, roms, label
## (the mount's), folder (the path on the mount)}]}: by mount, then `n64` folders first,
## shallower first, then path.
static func search(
	mount_list: Array, depth: int = SEARCH_DEPTH, stop := Callable(), limit := MAX_SEARCH_FOLDERS
) -> Dictionary:
	if mount_list.is_empty():
		return {"status": "no_card", "results": [], "limited": false}
	var results := []
	var searched := 0
	var seen := {}
	for mount in mount_list:
		var found := []
		var root := Roms.real_path(mount.path)
		if seen.has(root):
			continue
		seen[root] = true
		# [path, level, real path]; a cursor, not pop_front, which copies the array.
		var queue := [[String(mount.path), 0, root]]
		var next := 0
		while next < queue.size():
			if stop.is_valid() and stop.call():
				return {"status": "aborted", "results": results, "limited": false}
			if searched >= limit:
				return {"status": "ok", "results": results, "limited": true}
			searched += 1
			var item: Array = queue[next]
			queue[next] = null
			next += 1
			var count := rom_count(item[0])
			if count > 0:
				var on_mount := String(item[0]).substr(String(mount.path).length()).trim_prefix("/")
				(
					found
					. append(
						{
							"path": item[0],
							"roms": count,
							"label": mount.label,
							"folder": on_mount,
							"level": item[1],
						}
					)
				)
			if item[1] < depth:
				var access := DirAccess.open(item[0])
				for name in _folders(item[0]):
					var child := String(item[0]).path_join(name)
					var real := String(item[2]).path_join(name)
					if access != null and access.is_link(child):
						real = Roms.real_path(child)
						if not real.begins_with(root.path_join("")):
							continue
					if not seen.has(real):
						seen[real] = true
						queue.append([child, item[1] + 1, real])
		found.sort_custom(_search_less)
		for entry in found:
			entry.erase("level")
			results.append(entry)
	return {"status": "ok", "results": results, "limited": false}


## A listing for the chooser (ROM-11): {ok, path, roms, folders: [{name, path, roms}],
## places: [{label, path, sd}]}. A folder that is gone is replaced by its nearest parent
## that exists. Hidden folders are left out.
static func list_folder(
	path: String, home: String, media: String, mounts_text: String
) -> Dictionary:
	var dir := path.simplify_path() if path.is_absolute_path() else home
	while dir != "/" and not DirAccess.dir_exists_absolute(dir):
		dir = dir.get_base_dir()
	var folders := []
	for name in _folders(dir):
		var child := dir.path_join(name)
		folders.append({"name": name, "path": child, "roms": rom_count(child)})
	var places := [{"label": "Home", "path": home, "sd": false}]
	places.append_array(mounts(media, mounts_text))
	return {
		"ok": DirAccess.open(dir) != null,
		"path": dir,
		"roms": rom_count(dir),
		"folders": folders,
		"places": places,
	}


static func _search_less(a: Dictionary, b: Dictionary) -> bool:
	var a_n64: bool = a.path.get_file().to_lower() == "n64"
	var b_n64: bool = b.path.get_file().to_lower() == "n64"
	if a_n64 != b_n64:
		return a_n64
	if a.level != b.level:
		return a.level < b.level
	return a.path < b.path


## The visible subfolders of `dir`, in natural order ignoring case.
static func _folders(dir: String) -> Array:
	var names := _subdirs(dir, false)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


## The subfolders of `dir`, hidden ones only when `hidden`; [] when it can't be opened
## (DirAccess.get_directories_at would print an error for a missing folder).
static func _subdirs(dir: String, hidden: bool) -> Array:
	var access := DirAccess.open(dir)
	if access == null:
		return []
	access.include_hidden = hidden
	var names := Array(access.get_directories())
	if not hidden:
		names = names.filter(func(n: String) -> bool: return not n.begins_with("."))
	names.sort()
	return names


## The first MAX_SETTINGS_BYTES of a settings file, cut after its last whole line there
## (so a cut never splits a UTF-8 character).
static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var data := file.get_buffer(MAX_SETTINGS_BYTES)
	var more := not file.eof_reached() and file.get_position() < file.get_length()
	file.close()
	if more:
		data = data.slice(0, data.rfind(0x0A) + 1)
	return data.get_string_from_utf8()


## Mount points in /proc/self/mounts write space, tab, newline and backslash as octal.
static func _unescape(field: String) -> String:
	return field.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace(
		"\\134", "\\"
	)

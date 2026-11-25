extends RefCounted
## ROM discovery and preparation (ROM-1 to ROM-9): scans a folder for ROM files, identifies them
## by the SHA1 of their big-endian (z64) data and writes a ready-to-use .z64 for a port.
## The scanned folder is only ever read.

const MAX_ROM_SIZE := 64 * 1024 * 1024
const ROM_EXTENSIONS := ["z64", "n64", "v64"]
const FILE_EXTENSIONS := ["z64", "n64", "v64", "zip"]

const Z64_MAGIC := [0x80, 0x37, 0x12, 0x40]
const V64_MAGIC := [0x37, 0x80, 0x40, 0x12]
const N64_MAGIC := [0x40, 0x12, 0x37, 0x80]


## Runs `scan_all` on a worker thread (ROM-4). Keep a reference to the job until `finished`
## fires, and call `join` before the app exits.
class ScanJob:
	extends RefCounted

	signal finished(result: Dictionary)

	var result := {}
	var _thread: Thread
	var _delivered := false
	var _self_ref: RefCounted
	var _lock := Mutex.new()
	var _abort := false

	func start(
		dirs: Array, hashes: Dictionary, cache: Dictionary, max_size: int = MAX_ROM_SIZE
	) -> void:
		_self_ref = self
		_thread = Thread.new()
		_thread.start(_run.bind(dirs.duplicate(), hashes, cache.duplicate(true), max_size))

	## Asks the scan to stop at the next file or zip entry; `finished` still comes, with
	## status "aborted". Call it before `join` when the app quits.
	func abort() -> void:
		_lock.lock()
		_abort = true
		_lock.unlock()

	## Waits for the worker. Emits `finished` here if the main loop has not delivered it yet.
	func join() -> void:
		_deliver()

	func _stopped() -> bool:
		_lock.lock()
		var stop := _abort
		_lock.unlock()
		return stop

	func _run(dirs: Array, hashes: Dictionary, cache: Dictionary, max_size: int) -> void:
		result = load("res://src/roms.gd").scan_all(dirs, hashes, cache, max_size, _stopped)
		_deliver.call_deferred()

	func _deliver() -> void:
		if _delivered or _thread == null:
			return
		_delivered = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_self_ref = null
		finished.emit(result)


## Replaces a leading `~` with $HOME.
static func expand_dir(path: String) -> String:
	var home := OS.get_environment("HOME")
	if path == "~":
		return home
	if path.begins_with("~/"):
		return home.path_join(path.substr(2))
	return path


## "z64", "v64" or "n64" from the first four bytes, or "" when it is none of them.
static func detect_order(data: PackedByteArray) -> String:
	if data.size() < 4:
		return ""
	var head: Array = [data[0], data[1], data[2], data[3]]
	if head == Z64_MAGIC:
		return "z64"
	if head == V64_MAGIC:
		return "v64"
	if head == N64_MAGIC:
		return "n64"
	return ""


## The data in big-endian (z64) order. `order` is "z64", "v64" (16-bit swapped) or
## "n64" (32-bit swapped). Data that is not a multiple of four bytes is returned unchanged.
static func to_z64(data: PackedByteArray, order: String) -> PackedByteArray:
	if order == "z64" or data.size() % 4 != 0 or not order in ["v64", "n64"]:
		return data
	var words := data.to_int32_array()
	if order == "v64":
		for i in words.size():
			var x := words[i] & 0xFFFFFFFF
			words[i] = ((x & 0x00FF00FF) << 8) | ((x >> 8) & 0x00FF00FF)
	else:
		for i in words.size():
			var x := words[i] & 0xFFFFFFFF
			words[i] = (
				((x & 0xFF) << 24) | ((x & 0xFF00) << 8) | ((x >> 8) & 0xFF00) | ((x >> 24) & 0xFF)
			)
	return words.to_byte_array()


static func sha1_of(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	return ctx.finish().hex_encode()


## Scans `dir` (not recursively). `hashes` maps port id -> Array of {sha1, label} in
## preference order. `cache` maps "path|size|mtime" -> Array of {sha1, entry, order} (an empty
## array marks a file with nothing usable). Entries over `max_size` are skipped.
## Returns {status: "ok"|"missing", dir, matches: {port id -> {found, path, entry, label, sha1,
## order}}, cache: the updated cache (only files seen in this scan), hashed, cache_hits}.
## `stop` (optional) is asked between files and zip entries; when it returns true the scan
## ends with status "aborted" (ROM-4: quitting never waits for a whole folder).
static func scan(
	dir: String,
	hashes: Dictionary,
	cache: Dictionary,
	max_size: int = MAX_ROM_SIZE,
	stop := Callable()
) -> Dictionary:
	var result := {
		"status": "ok",
		"dir": dir,
		"matches": _empty_matches(hashes),
		"cache": {},
		"hashed": 0,
		"cache_hits": 0,
	}
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		result["status"] = "missing"
		return result
	# get_files_at leaves get_open_error() as it was, so an unreadable folder is found by
	# opening it.
	var access := DirAccess.open(dir)
	if access == null:
		result["status"] = "missing"
		return result
	var names := access.get_files()
	names.sort()

	var best := {}
	for name in names:
		if not name.get_extension().to_lower() in FILE_EXTENSIONS:
			continue
		if stop.is_valid() and stop.call():
			result["status"] = "aborted"
			break
		var path := dir.path_join(name)
		for candidate in _identify_file(path, result, cache, max_size, stop):
			for port in hashes:
				var list: Array = hashes[port]
				for i in list.size():
					if String(list[i]["sha1"]).to_lower() != candidate["sha1"]:
						continue
					var rank := [i, name, candidate["entry"]]
					if not best.has(port) or _rank_less(rank, best[port]["rank"]):
						best[port] = {
							"rank": rank,
							"match":
							{
								"found": true,
								"path": path,
								"entry": candidate["entry"],
								"label": list[i].get("label", ""),
								"sha1": candidate["sha1"],
								"order": candidate["order"],
							},
						}
					break
	for port in best:
		result["matches"][port] = best[port]["match"]
	return result


## Scans every folder of `dirs` in order (ROM-17); a port keeps the match of the first
## folder that has one (ROM-7 decides within a folder). A folder that is one of the earlier
## ones by real path is not scanned again. Returns `scan`'s keys, with `dirs` (as given) in
## place of `dir`, and `folders`: [{path, status ("ok"|"missing"|"aborted"|"skipped" for a
## repeat), ports (ids whose match came from it)}]. The status is "ok" when any folder
## could be read, "missing" when none, "aborted" when `stop` cut it short. The cache keeps
## the entries of a missing folder, for when it is back (an unmounted SD card).
static func scan_all(
	dirs: Array,
	hashes: Dictionary,
	cache: Dictionary,
	max_size: int = MAX_ROM_SIZE,
	stop := Callable()
) -> Dictionary:
	var result := {
		"status": "missing",
		"dirs": dirs.duplicate(),
		"folders": [],
		"matches": _empty_matches(hashes),
		"cache": {},
		"hashed": 0,
		"cache_hits": 0,
	}
	var seen: Array[String] = []
	for dir: String in dirs:
		var folder := {"path": dir, "status": "skipped", "ports": []}
		result["folders"].append(folder)
		if result["status"] == "aborted":
			folder["status"] = "aborted"
			continue
		var real := real_path(dir) if dir.is_absolute_path() else dir
		if real in seen:
			continue
		seen.append(real)
		var one := scan(dir, hashes, cache, max_size, stop)
		folder["status"] = one["status"]
		result["hashed"] += one["hashed"]
		result["cache_hits"] += one["cache_hits"]
		result["cache"].merge(one["cache"])
		if one["status"] == "missing":
			for key: String in cache:
				if key.rsplit("|", true, 2)[0].get_base_dir() == dir:
					result["cache"][key] = cache[key]
			continue
		if result["status"] != "aborted":
			result["status"] = "aborted" if one["status"] == "aborted" else "ok"
		for port in one["matches"]:
			if one["matches"][port]["found"] and not result["matches"][port]["found"]:
				result["matches"][port] = one["matches"][port]
				folder["ports"].append(port)
	return result


## Writes the ROM of a `scan` match as big-endian data to `dest_path`, through a temp file in
## the same folder. Refuses to write into the source file's folder (ROM-6), compared by real
## path. ERR_FILE_CORRUPT when the data no longer has the SHA1 the scan found (the file
## changed since).
static func prepare(match: Dictionary, dest_path: String) -> Error:
	if not match.get("found", false):
		return ERR_INVALID_PARAMETER
	var src_path: String = match["path"]
	if same_folder(dest_path, src_path):
		return ERR_INVALID_PARAMETER
	var data := _read_source(src_path, match.get("entry", ""), MAX_ROM_SIZE)
	if data.is_empty():
		return ERR_FILE_CANT_READ
	var order := String(match.get("order", detect_order(data)))
	data = to_z64(data, order)
	var expected := String(match.get("sha1", ""))
	if not expected.is_empty() and sha1_of(data) != expected.to_lower():
		return ERR_FILE_CORRUPT
	var err := DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	if err != OK:
		return err
	var temp := dest_path + ".part"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
		DirAccess.remove_absolute(temp)
		return write_err
	err = DirAccess.rename_absolute(temp, dest_path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err


## True when the two paths' folders are one folder, after links and `..` are resolved.
static func same_folder(a: String, b: String) -> bool:
	return real_path(a.get_base_dir()) == real_path(b.get_base_dir())


## `path` (absolute) with `.`, `..` and symbolic links resolved, as far as it exists. Godot
## has no realpath, so links are followed one part at a time (at most 40 of them).
static func real_path(path: String) -> String:
	var parts := Array(path.simplify_path().split("/", false))
	var out := ""
	var hops := 0
	var i := 0
	while i < parts.size():
		var parent: String = out if not out.is_empty() else "/"
		var next: String = out + "/" + parts[i]
		var access := DirAccess.open(parent)
		if access != null and hops < 40 and access.is_link(next):
			hops += 1
			var target := access.read_link(next)
			if not target.begins_with("/"):
				target = parent.path_join(target)
			var rest := "/".join(parts.slice(i + 1))
			parts = Array((target + "/" + rest).simplify_path().split("/", false))
			out = ""
			i = 0
			continue
		out = next
		i += 1
	return out if not out.is_empty() else "/"


## Uncompressed size of every entry of a zip, by name, from its central directory, so an
## entry can be skipped without being read. Empty when it is not a readable zip. Zip64
## entries report 0xFFFFFFFF, which is over every limit here.
static func zip_sizes(path: String) -> Dictionary:
	var sizes := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return sizes
	var length := file.get_length()
	var tail_size := mini(length, 65557)
	file.seek(length - tail_size)
	var tail := file.get_buffer(tail_size)
	var eocd := -1
	for i in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50:
			eocd = i
			break
	if eocd < 0:
		file.close()
		return sizes
	var count := tail.decode_u16(eocd + 10)
	var dir_size := tail.decode_u32(eocd + 12)
	var dir_offset := tail.decode_u32(eocd + 16)
	if dir_offset + dir_size > length:
		file.close()
		return sizes
	file.seek(dir_offset)
	var central := file.get_buffer(dir_size)
	file.close()
	var pos := 0
	for _i in count:
		if pos + 46 > central.size() or central.decode_u32(pos) != 0x02014b50:
			break
		var name_length := central.decode_u16(pos + 28)
		var skip := name_length + central.decode_u16(pos + 30) + central.decode_u16(pos + 32)
		var name := central.slice(pos + 46, pos + 46 + name_length).get_string_from_utf8()
		sizes[name] = central.decode_u32(pos + 24)
		pos += 46 + skip
	return sizes


static func _empty_matches(hashes: Dictionary) -> Dictionary:
	var matches := {}
	for port in hashes:
		matches[port] = {
			"found": false, "path": "", "entry": "", "label": "", "sha1": "", "order": ""
		}
	return matches


static func _rank_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]


static func _cache_key(path: String) -> String:
	var size := 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		size = file.get_length()
		file.close()
	return "%s|%d|%d" % [path, size, FileAccess.get_modified_time(path)]


## The usable ROM entries of one file, from the cache when its key is unchanged. A file or
## zip entry over `max_size` is skipped before it is read.
static func _identify_file(
	path: String, result: Dictionary, cache: Dictionary, max_size: int, stop: Callable
) -> Array:
	var key := _cache_key(path)
	if cache.has(key):
		result["cache"][key] = cache[key]
		result["cache_hits"] += 1
		return cache[key]
	var entries: Array = []
	if path.get_extension().to_lower() == "zip":
		var zipped: Variant = _identify_zip(path, result, max_size, stop)
		if zipped == null:
			return []
		entries = zipped
	else:
		var candidate := _identify_data(_read_file(path, max_size), "", max_size)
		if not candidate.is_empty():
			result["hashed"] += 1
			entries.append(candidate)
	result["cache"][key] = entries
	return entries


## The candidates of a zip, or null when `stop` cut it short (then nothing is cached).
static func _identify_zip(
	path: String, result: Dictionary, max_size: int, stop: Callable
) -> Variant:
	var entries: Array = []
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return entries
	var sizes := zip_sizes(path)
	for entry in zip.get_files():
		if entry.ends_with("/") or not entry.get_extension().to_lower() in ROM_EXTENSIONS:
			continue
		if int(sizes.get(entry, max_size + 1)) > max_size:
			continue
		if stop.is_valid() and stop.call():
			result["status"] = "aborted"
			zip.close()
			return null
		var candidate := _identify_data(zip.read_file(entry), entry, max_size)
		if not candidate.is_empty():
			result["hashed"] += 1
			entries.append(candidate)
	zip.close()
	return entries


## The whole file, or nothing when it is larger than `max_size`.
static func _read_file(path: String, max_size: int) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > max_size:
		return PackedByteArray()
	var data := file.get_buffer(file.get_length())
	file.close()
	return data


## {sha1, entry, order} for ROM data, or {} when it is too large or has no ROM header.
static func _identify_data(data: PackedByteArray, entry: String, max_size: int) -> Dictionary:
	if data.size() > max_size:
		return {}
	var order := detect_order(data)
	if order.is_empty():
		return {}
	return {"sha1": sha1_of(to_z64(data, order)), "entry": entry, "order": order}


static func _read_source(path: String, entry: String, max_size: int) -> PackedByteArray:
	if entry.is_empty():
		return _read_file(path, max_size)
	if int(zip_sizes(path).get(entry, max_size + 1)) > max_size:
		return PackedByteArray()
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	var data := zip.read_file(entry)
	zip.close()
	return data

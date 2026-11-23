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


## Runs `scan` on a worker thread (ROM-4). Keep a reference to the job until `finished`
## fires, and call `join` before the app exits.
class ScanJob:
	extends RefCounted

	signal finished(result: Dictionary)

	var result := {}
	var _thread: Thread
	var _delivered := false
	var _self_ref: RefCounted

	func start(
		dir: String, hashes: Dictionary, cache: Dictionary, max_size: int = MAX_ROM_SIZE
	) -> void:
		_self_ref = self
		_thread = Thread.new()
		_thread.start(_run.bind(dir, hashes, cache.duplicate(true), max_size))

	## Waits for the worker. Emits `finished` here if the main loop has not delivered it yet.
	func join() -> void:
		_deliver()

	func _run(dir: String, hashes: Dictionary, cache: Dictionary, max_size: int) -> void:
		result = load("res://src/roms.gd").scan(dir, hashes, cache, max_size)
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
static func scan(
	dir: String, hashes: Dictionary, cache: Dictionary, max_size: int = MAX_ROM_SIZE
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
	var names := DirAccess.get_files_at(dir)
	if names.is_empty() and DirAccess.get_open_error() != OK:
		result["status"] = "missing"
		return result
	names.sort()

	var best := {}
	for name in names:
		if not name.get_extension().to_lower() in FILE_EXTENSIONS:
			continue
		var path := dir.path_join(name)
		for candidate in _identify_file(path, result, cache, max_size):
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


## Writes the ROM of a `scan` match as big-endian data to `dest_path`, through a temp file in
## the same folder. Refuses to write next to the source file.
static func prepare(match: Dictionary, dest_path: String) -> Error:
	if not match.get("found", false):
		return ERR_INVALID_PARAMETER
	var src_path: String = match["path"]
	if dest_path.get_base_dir() == src_path.get_base_dir():
		return ERR_INVALID_PARAMETER
	var data := _read_source(src_path, match.get("entry", ""))
	if data.is_empty():
		return ERR_FILE_CANT_READ
	var order := String(match.get("order", detect_order(data)))
	data = to_z64(data, order)
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


## The usable ROM entries of one file, from the cache when its key is unchanged.
static func _identify_file(
	path: String, result: Dictionary, cache: Dictionary, max_size: int
) -> Array:
	var key := _cache_key(path)
	if cache.has(key):
		result["cache"][key] = cache[key]
		result["cache_hits"] += 1
		return cache[key]
	var entries: Array = []
	if path.get_extension().to_lower() == "zip":
		entries = _identify_zip(path, result, max_size)
	else:
		var candidate := _identify_data(FileAccess.get_file_as_bytes(path), "", max_size)
		if not candidate.is_empty():
			result["hashed"] += 1
			entries.append(candidate)
	result["cache"][key] = entries
	return entries


static func _identify_zip(path: String, result: Dictionary, max_size: int) -> Array:
	var entries: Array = []
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return entries
	for entry in zip.get_files():
		if entry.ends_with("/") or not entry.get_extension().to_lower() in ROM_EXTENSIONS:
			continue
		var candidate := _identify_data(zip.read_file(entry), entry, max_size)
		if not candidate.is_empty():
			result["hashed"] += 1
			entries.append(candidate)
	zip.close()
	return entries


## {sha1, entry, order} for ROM data, or {} when it is too large or has no ROM header.
static func _identify_data(data: PackedByteArray, entry: String, max_size: int) -> Dictionary:
	if data.size() > max_size:
		return {}
	var order := detect_order(data)
	if order.is_empty():
		return {}
	return {"sha1": sha1_of(to_z64(data, order)), "entry": entry, "order": order}


static func _read_source(path: String, entry: String) -> PackedByteArray:
	if entry.is_empty():
		return FileAccess.get_file_as_bytes(path)
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	var data := zip.read_file(entry)
	zip.close()
	return data

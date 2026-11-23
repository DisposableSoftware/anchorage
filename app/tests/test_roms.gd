extends "res://tests/case.gd"

const Roms := preload("res://src/roms.gd")


## Deterministic 1 KiB of ROM-like data in z64 order; `seed` makes different "games".
func _rom(seed: int) -> PackedByteArray:
	var data := PackedByteArray([0x80, 0x37, 0x12, 0x40])
	for i in range(4, 1024):
		data.append((i * 31 + seed * 7 + (i >> 3)) & 0xFF)
	return data


func _swap(data: PackedByteArray, order: String) -> PackedByteArray:
	var out := data.duplicate()
	for i in range(0, out.size(), 4):
		if order == "v64":
			out[i] = data[i + 1]
			out[i + 1] = data[i]
			out[i + 2] = data[i + 3]
			out[i + 3] = data[i + 2]
		else:
			out[i] = data[i + 3]
			out[i + 1] = data[i + 2]
			out[i + 2] = data[i + 1]
			out[i + 3] = data[i]
	return out


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()


func _zip(path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(path)
	for name in entries:
		packer.start_file(name)
		packer.write_file(entries[name])
		packer.close_file()
	packer.close()


func _hashes() -> Dictionary:
	return {
		"alpha":
		[
			{"sha1": Roms.sha1_of(_rom(1)), "label": "Alpha US"},
			{"sha1": Roms.sha1_of(_rom(2)), "label": "Alpha EU"},
		],
		"beta": [{"sha1": Roms.sha1_of(_rom(3)), "label": "Beta"}],
	}


func _snapshot(dir: String) -> Dictionary:
	var snap := {}
	for name in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		snap[name] = [FileAccess.get_file_as_bytes(path).size(), FileAccess.get_modified_time(path)]
	return snap


func test_order_detection_and_conversion() -> void:
	var z := _rom(1)
	eq(Roms.detect_order(z), "z64", "z64 magic")
	for order in ["v64", "n64"]:
		var swapped := _swap(z, order)
		eq(Roms.detect_order(swapped), order, "%s magic" % order)
		eq(Roms.to_z64(swapped, order), z, "%s converts back" % order)
		eq(Roms.sha1_of(Roms.to_z64(swapped, order)), Roms.sha1_of(z), "%s hashes alike" % order)
	eq(Roms.detect_order(PackedByteArray([1, 2, 3, 4])), "", "unknown header")
	eq(Roms.detect_order(PackedByteArray([0x80])), "", "too short")


func test_scan_identifies_all_byte_orders_and_zips() -> void:
	var dir := temp_dir("roms-orders")
	_write(dir.path_join("a.z64"), _rom(1))
	_write(dir.path_join("b.v64"), _swap(_rom(3), "v64"))
	_zip(dir.path_join("c.zip"), {"c.n64": _swap(_rom(2), "n64")})
	var result := Roms.scan(dir, _hashes(), {})
	eq(result["status"], "ok", "folder exists")
	var alpha: Dictionary = result["matches"]["alpha"]
	eq(alpha["found"], true, "alpha found")
	eq(alpha["label"], "Alpha US", "most preferred hash wins over the zip's EU one")
	eq(alpha["path"], dir.path_join("a.z64"), "path")
	eq(alpha["entry"], "", "plain file has no entry")
	var beta: Dictionary = result["matches"]["beta"]
	eq(beta["found"], true, "v64 file identified")
	eq(beta["order"], "v64", "order recorded")
	eq(beta["sha1"], Roms.sha1_of(_rom(3)), "sha1 is of the z64 data")
	eq(result["hashed"], 3, "three ROMs hashed")
	remove(dir)


func test_zip_entry_and_preference_order() -> void:
	var dir := temp_dir("roms-pref")
	_zip(
		dir.path_join("both.zip"),
		{"readme.txt": "hi".to_utf8_buffer(), "eu.z64": _rom(2), "us.z64": _rom(1)}
	)
	_write(dir.path_join("plain.z64"), _rom(2))
	var result := Roms.scan(dir, _hashes(), {})
	var alpha: Dictionary = result["matches"]["alpha"]
	eq(alpha["label"], "Alpha US", "first hash of the list wins")
	eq(alpha["entry"], "us.z64", "zip entry named")
	eq(alpha["path"], dir.path_join("both.zip"), "zip path")

	var only_eu := {"alpha": [{"sha1": Roms.sha1_of(_rom(2)), "label": "EU"}]}
	var tie := Roms.scan(dir, only_eu, {})
	eq(tie["matches"]["alpha"]["path"], dir.path_join("both.zip"), "same hash: file name decides")
	remove(dir)


func test_junk_and_unknown_files_are_ignored() -> void:
	var dir := temp_dir("roms-junk")
	_write(dir.path_join("notes.txt"), _rom(1))
	_write(dir.path_join("fake.z64"), "not a rom at all".to_utf8_buffer())
	_write(dir.path_join("other.z64"), _rom(9))
	_zip(dir.path_join("docs.zip"), {"a.txt": _rom(1)})
	_write(dir.path_join("broken.zip"), "garbage".to_utf8_buffer())
	DirAccess.make_dir_recursive_absolute(dir.path_join("sub"))
	_write(dir.path_join("sub").path_join("deep.z64"), _rom(1))
	var result := Roms.scan(dir, _hashes(), {})
	eq(result["matches"]["alpha"]["found"], false, "nothing matches")
	eq(result["matches"]["beta"]["found"], false, "nothing matches")
	eq(result["status"], "ok", "folder is fine")
	remove(dir)


func test_missing_folder_is_a_status() -> void:
	var result := Roms.scan("/nonexistent/anchorage-roms", _hashes(), {})
	eq(result["status"], "missing", "distinct status")
	eq(result["matches"]["alpha"]["found"], false, "no matches")
	eq(Roms.scan("", _hashes(), {})["status"], "missing", "empty path")


func test_oversized_entries_are_skipped() -> void:
	var dir := temp_dir("roms-big")
	_zip(dir.path_join("big.zip"), {"big.z64": _rom(1)})
	_write(dir.path_join("big.z64"), _rom(3))
	var result := Roms.scan(dir, _hashes(), {}, 512)
	eq(result["matches"]["alpha"]["found"], false, "zip entry over the limit")
	eq(result["matches"]["beta"]["found"], false, "file over the limit")
	eq(Roms.MAX_ROM_SIZE, 64 * 1024 * 1024, "limit is 64 MiB")
	remove(dir)


func test_cache_skips_hashing() -> void:
	var dir := temp_dir("roms-cache")
	_write(dir.path_join("a.z64"), _rom(1))
	_zip(dir.path_join("z.zip"), {"x.z64": _rom(3)})
	_write(dir.path_join("junk.z64"), "xxxxxxxx".to_utf8_buffer())
	var first := Roms.scan(dir, _hashes(), {})
	eq(first["hashed"], 2, "first scan hashes")
	eq(first["cache_hits"], 0, "no hits yet")
	var second := Roms.scan(dir, _hashes(), first["cache"])
	eq(second["hashed"], 0, "second scan hashes nothing")
	eq(second["cache_hits"], 3, "every file from the cache, ignored ones too")
	eq(second["matches"], first["matches"], "same matches")
	# mtime has one-second resolution, so the size changes too
	var changed := _rom(2)
	changed.append_array(PackedByteArray([0, 0, 0, 0]))
	_write(dir.path_join("a.z64"), changed)
	var third := Roms.scan(dir, _hashes(), second["cache"])
	eq(third["hashed"], 1, "changed file is hashed again")
	eq(third["matches"]["alpha"]["found"], false, "new content no longer matches")
	remove(dir)


func test_prepare_writes_z64_and_leaves_folder_alone() -> void:
	var dir := temp_dir("roms-prep")
	var roms := dir.path_join("roms")
	var out := dir.path_join("data")
	DirAccess.make_dir_recursive_absolute(roms)
	_write(roms.path_join("a.v64"), _swap(_rom(1), "v64"))
	_zip(roms.path_join("b.zip"), {"b.n64": _swap(_rom(3), "n64")})
	var before := _snapshot(roms)
	var result := Roms.scan(roms, _hashes(), {})
	eq(Roms.prepare(result["matches"]["alpha"], out.path_join("sub/alpha.z64")), OK, "prepare file")
	eq(Roms.prepare(result["matches"]["beta"], out.path_join("beta.z64")), OK, "prepare zip entry")
	eq(
		Roms.sha1_of(FileAccess.get_file_as_bytes(out.path_join("sub/alpha.z64"))),
		Roms.sha1_of(_rom(1)),
		"alpha written as z64"
	)
	eq(FileAccess.get_file_as_bytes(out.path_join("beta.z64")), _rom(3), "beta written as z64")
	check(not FileAccess.file_exists(out.path_join("beta.z64.part")), "temp file gone")
	eq(_snapshot(roms), before, "ROM folder unchanged by scan and prepare")
	eq(
		Roms.prepare(result["matches"]["alpha"], roms.path_join("x.z64")),
		ERR_INVALID_PARAMETER,
		"refuses to write into the ROM folder"
	)
	eq(Roms.prepare({"found": false}, out.path_join("n.z64")), ERR_INVALID_PARAMETER, "no match")
	eq(_snapshot(roms), before, "still unchanged")
	remove(dir)


func test_scan_job_runs_on_a_thread() -> void:
	var dir := temp_dir("roms-job")
	_write(dir.path_join("a.z64"), _rom(1))
	var job := Roms.ScanJob.new()
	var got := []
	job.finished.connect(func(r: Dictionary): got.append(r))
	job.start(dir, _hashes(), {})
	job.join()
	eq(got.size(), 1, "finished emitted once")
	job.join()
	eq(got.size(), 1, "join twice does not emit twice")
	eq(got[0]["matches"]["alpha"]["found"], true, "result delivered")
	remove(dir)


func test_expand_dir() -> void:
	eq(Roms.expand_dir("~/Roms/n64"), OS.get_environment("HOME").path_join("Roms/n64"), "tilde")
	eq(Roms.expand_dir("/x/y"), "/x/y", "absolute unchanged")

extends "res://tests/case.gd"

const Roms := preload("res://src/roms.gd")
const Catalog := preload("res://src/catalog.gd")


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


## Quitting during a scan must not wait for the whole folder (ROM-4): the scan stops
## between files and between zip entries once asked to.
func test_a_scan_stops_when_asked() -> void:
	var dir := temp_dir("roms-stop")
	for i in 5:
		_write(dir.path_join("r%d.z64" % i), _rom(i))
	_zip(dir.path_join("z.zip"), {"a.z64": _rom(7), "b.z64": _rom(8), "c.z64": _rom(9)})
	var asked := [0]
	var stop := func() -> bool:
		asked[0] += 1
		return asked[0] > 2
	var result := Roms.scan(dir, _hashes(), {}, Roms.MAX_ROM_SIZE, stop)
	eq(result["status"], "aborted", "an aborted scan says so")
	check(result["hashed"] <= 2, "stopped early: %d hashed" % result["hashed"])
	var zip_only := temp_dir("roms-stop-zip")
	_zip(zip_only.path_join("z.zip"), {"a.z64": _rom(7), "b.z64": _rom(8), "c.z64": _rom(9)})
	asked[0] = 0
	result = Roms.scan(zip_only, _hashes(), {}, Roms.MAX_ROM_SIZE, stop)
	check(result["hashed"] < 3, "stopped between zip entries: %d hashed" % result["hashed"])
	eq(result["cache"], {}, "a half-read zip is not cached")
	remove(dir)
	remove(zip_only)


func test_a_scan_job_can_be_aborted() -> void:
	var dir := temp_dir("roms-abort")
	var big := PackedByteArray([0x80, 0x37, 0x12, 0x40])
	big.resize(4 << 20)
	for i in 30:
		big[8] = i
		_write(dir.path_join("r%02d.z64" % i), big)
	var job := Roms.ScanJob.new()
	var got := []
	job.finished.connect(func(r: Dictionary): got.append(r))
	job.start(dir, _hashes(), {})
	job.abort()
	job.join()
	eq(got.size(), 1, "finished still comes")
	eq(got[0]["status"], "aborted", "and says it stopped")
	check(got[0]["hashed"] < 30, "before the end: %d of 30" % got[0]["hashed"])
	remove(dir)


## ROM-2: sizes come from the zip's central directory, so an oversized entry is skipped
## without being read, and a file over the limit is never read whole.
func test_zip_entry_sizes_come_from_the_central_directory() -> void:
	var dir := temp_dir("roms-zipsize")
	var big := PackedByteArray()
	big.resize(5000)
	_zip(dir.path_join("z.zip"), {"small.z64": _rom(1), "dir/big.n64": big})
	var sizes := Roms.zip_sizes(dir.path_join("z.zip"))
	eq([sizes.get("small.z64"), sizes.get("dir/big.n64")], [1024, 5000], "sizes by name")
	_write(dir.path_join("junk.zip"), "not a zip".to_utf8_buffer())
	eq(Roms.zip_sizes(dir.path_join("junk.zip")), {}, "not a zip: nothing")
	remove(dir)


## ROM-6: "next to its source" is decided on real paths, so a link into the ROM folder or
## a path with `..` can't make prepare write there.
func test_prepare_never_writes_into_the_rom_folder_through_a_link() -> void:
	var dir := temp_dir("roms-guard")
	var roms := dir.path_join("roms")
	DirAccess.make_dir_recursive_absolute(roms)
	_write(roms.path_join("a.z64"), _rom(1))
	OS.execute("ln", ["-s", roms, dir.path_join("data")])
	var before := _snapshot(roms)
	var match: Dictionary = Roms.scan(roms, _hashes(), {})["matches"]["alpha"]
	eq(
		Roms.prepare(match, dir.path_join("data/alpha.z64")),
		ERR_INVALID_PARAMETER,
		"a data folder that links to the ROM folder"
	)
	eq(
		Roms.prepare(match, dir.path_join("other/../roms/alpha.z64")),
		ERR_INVALID_PARAMETER,
		"a path with .."
	)
	eq(_snapshot(roms), before, "the ROM folder is unchanged")
	eq(Roms.real_path(dir.path_join("data/alpha.z64")), roms.path_join("alpha.z64"), "real_path")
	remove(dir)


## The file is checked again when it is copied: one changed since the scan is not used.
func test_prepare_checks_the_sha1_again() -> void:
	var dir := temp_dir("roms-recheck")
	var roms := dir.path_join("roms")
	DirAccess.make_dir_recursive_absolute(roms)
	_write(roms.path_join("a.z64"), _rom(1))
	var match: Dictionary = Roms.scan(roms, _hashes(), {})["matches"]["alpha"]
	_write(roms.path_join("a.z64"), _rom(2))
	var out := dir.path_join("data/alpha.z64")
	eq(Roms.prepare(match, out), ERR_FILE_CORRUPT, "changed since the scan")
	check(not FileAccess.file_exists(out), "nothing written")
	remove(dir)


## Ghostship, PaperBoat and Lighthouse hash the raw file and take only big-endian data
## (docs/research/ports-2.md). With the shipped hash lists, each of them claims a ROM in any
## byte order (fabricated data standing in for one of its hashes), no other port claims it,
## and what is written for it is big-endian under its catalog name.
func test_the_new_ports_match_any_byte_order_and_get_big_endian_data() -> void:
	var catalog: Array = Catalog.load_default()["ports"]
	var shipped := {}
	for port in catalog:
		shipped[port["id"]] = port["roms"]
	var seed := 20
	for id in ["ghostship", "paperboat", "lighthouse"]:
		var port := Catalog.find(catalog, id)
		for order in ["z64", "v64", "n64"]:
			seed += 1
			var data := _rom(seed)
			var dir := temp_dir("roms-%s-%s" % [id, order])
			var roms := dir.path_join("roms")
			DirAccess.make_dir_recursive_absolute(roms)
			var raw := data if order == "z64" else _swap(data, order)
			_zip(roms.path_join("game.zip"), {"game." + order: raw})
			var none: Dictionary = Roms.scan(roms, shipped, {})["matches"]
			for other in none:
				check(not none[other]["found"], "%s: unknown data claims no port" % other)
			var hashes := shipped.duplicate()
			var list: Array = port["roms"].duplicate(true)
			list[-1]["sha1"] = Roms.sha1_of(data)
			hashes[id] = list
			var matches: Dictionary = Roms.scan(roms, hashes, {})["matches"]
			for other in matches:
				eq(
					matches[other]["found"],
					other == id,
					"%s %s: claimed by %s only" % [id, order, id]
				)
			eq(matches[id]["label"], list[-1]["label"], "%s %s: labelled" % [id, order])
			eq(matches[id]["order"], order, "%s %s: order seen" % [id, order])
			var out := dir.path_join("data").path_join(port["rom_file"])
			eq(Roms.prepare(matches[id], out), OK, "%s %s: prepared" % [id, order])
			var written := FileAccess.get_file_as_bytes(out)
			eq(written, data, "%s %s: written big-endian" % [id, order])
			eq(Roms.detect_order(written), "z64", "%s %s: z64 header" % [id, order])
			remove(dir)


func test_expand_dir() -> void:
	eq(Roms.expand_dir("~/Roms/n64"), OS.get_environment("HOME").path_join("Roms/n64"), "tilde")
	eq(Roms.expand_dir("/x/y"), "/x/y", "absolute unchanged")

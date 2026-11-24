extends "res://tests/case.gd"

const Catalog := preload("res://src/catalog.gd")


func _entry() -> Dictionary:
	return {
		"id": "x",
		"name": "X",
		"game": "G",
		"description": "D",
		"repo": "owner/name",
		"asset_suffix": ".AppImage",
		"archive": ["x.o2r"],
		"launch": {"executable": "x.appimage", "cwd": "data"},
		"rom_place": "cwd",
		"rom_file": "x.z64",
		"roms": [{"label": "US", "sha1": "a".repeat(40)}],
	}


func _parse(entries: Array) -> Dictionary:
	return Catalog.parse(JSON.stringify({"ports": entries}))


func test_shipped_catalog_is_valid_and_has_the_four_ports() -> void:
	var catalog := Catalog.load_default()
	eq(catalog["errors"], PackedStringArray(), "no problems in ports.json")
	var ids := []
	for port in catalog["ports"]:
		ids.append(port["id"])
	eq(ids, ["soh", "2ship", "starship", "spaghettikart"], "ids in catalog order")
	eq(ids.size(), Array(ids).duplicate().size(), "ids are unique")


func test_every_hash_is_40_lowercase_hex() -> void:
	var data: Dictionary = JSON.parse_string(repo_file("app/data/ports.json"))
	var count := 0
	for port in data["ports"]:
		for rom in port["roms"]:
			count += 1
			check(Catalog.is_sha1(rom["sha1"]), "%s %s" % [port["id"], rom["sha1"]])
	eq(count, 19 + 2 + 2 + 1, "OoT 19, MM 2, SF64 US 2, MK64 1")


func test_hashes_are_unique_across_ports() -> void:
	var seen := {}
	for port in Catalog.load_default()["ports"]:
		for rom in port["roms"]:
			check(not seen.has(rom["sha1"]), "%s is listed twice" % rom["sha1"])
			seen[rom["sha1"]] = true


func test_starship_runs_in_its_data_folder_with_what_its_extractor_reads() -> void:
	var starship := Catalog.find(Catalog.load_default()["ports"], "starship")
	eq(starship["launch"]["cwd"], "data", "sf64.o2r is written to the working directory (PORT-9)")
	eq(starship["extra_files"], ["gamecontrollerdb.txt", "config.yml", "assets"], "extra files")
	var kart := Catalog.find(Catalog.load_default()["ports"], "spaghettikart")
	eq(kart["extra_files"], ["gamecontrollerdb.txt"], "extra files")


func test_every_entry_has_every_field() -> void:
	for port in Catalog.load_default()["ports"]:
		for key in Catalog.STRING_KEYS:
			check(not (port[key] as String).is_empty(), "%s.%s" % [port["id"], key])
		for key in ["archive", "launch", "extra_files", "rom_place", "roms"]:
			check(port.has(key), "%s.%s" % [port["id"], key])
		check(port["launch"].has("args"), "%s launch.args" % port["id"])


func test_a_new_entry_needs_no_code_and_is_normalised() -> void:
	var catalog := _parse([_entry()])
	eq(catalog["errors"].size(), 0, "valid")
	var port: Dictionary = catalog["ports"][0]
	eq(port["asset_suffix"], ".appimage", "suffix lowercased")
	eq(port["extra_files"], [], "default extra_files")
	eq(port["launch"]["args"], [], "default args")


func test_bad_entries_are_dropped_with_a_reason() -> void:
	var bad_hash := _entry()
	bad_hash["id"] = "a"
	bad_hash["roms"] = [{"label": "L", "sha1": "ABC"}]
	var bad_path := _entry()
	bad_path["id"] = "b"
	bad_path["launch"]["executable"] = "../x"
	var bad_id := _entry()
	bad_id["id"] = "../etc"
	var duplicate := _entry()
	var catalog := _parse([_entry(), duplicate, bad_hash, bad_path, bad_id, 5])
	eq(catalog["ports"].size(), 1, "only the first good entry survives")
	eq(catalog["errors"].size(), 5, "one message per dropped entry")


func test_broken_json_is_an_error_not_a_crash() -> void:
	eq(Catalog.parse("{nope")["ports"].size(), 0, "no ports")
	eq(Catalog.parse("{nope")["errors"].size(), 1, "one error")


func test_art_is_optional_and_a_bad_object_is_dropped_but_the_port_stays() -> void:
	var catalog := Catalog.parse(FileAccess.get_file_as_string("res://tests/art_catalog.json"))
	var ports: Array = catalog["ports"]
	eq(ports.size(), 3, "all three ports stay (ART-1)")
	eq(ports[0]["art"]["author"], "Some Artist", "the art object is kept")
	check(not ports[1].has("art"), "a port without art has none")
	check(not ports[2].has("art"), "art on another host is dropped (ART-4)")
	eq(catalog["errors"].size(), 1, "and reported once")
	check(str(catalog["errors"][0]).contains("bad-art"), "naming the port")


func test_art_needs_every_field_and_a_steamgriddb_url() -> void:
	var good := {
		"url": "https://cdn.steamgriddb.com/grid/x.png",
		"author": "A",
		"source": "https://www.steamgriddb.com/grid/1",
		"style": "alternate",
	}
	eq(Catalog.validate_art(good).size(), 0, "valid")
	for key in good:
		var broken := good.duplicate()
		broken.erase(key)
		eq(Catalog.validate_art(broken).size(), 1, "%s is required" % key)
	var http := good.duplicate()
	http["url"] = "http://cdn2.steamgriddb.com/grid/x.png"
	check(Catalog.validate_art(http).size() > 0, "https only")
	var elsewhere := good.duplicate()
	elsewhere["source"] = "https://example.com/grid/1"
	check(Catalog.validate_art(elsewhere).size() > 0, "source on steamgriddb.com")
	check(Catalog.validate_art("x").size() > 0, "not an object")


func test_shipped_art_is_complete_and_all_one_style() -> void:
	var styles := {}
	var count := 0
	for port in Catalog.load_default()["ports"]:
		if not port.has("art"):
			continue
		count += 1
		eq(Catalog.validate_art(port["art"]).size(), 0, "%s art is valid (ART-1)" % port["id"])
		styles[port["art"]["style"]] = true
	check(styles.size() == 1, "every entry has the same style (ART-2): %s" % str(styles.keys()))
	eq(count, 4, "every port has art")

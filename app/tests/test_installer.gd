extends "res://tests/case.gd"

const Installer := preload("res://src/installer.gd")
const FakeHttp := preload("res://tests/fake_http.gd")

const BASE := "https://github.com/HarbourMasters/Starship/releases/download/v2.0.0/"
const ZIP_URL := BASE + "Starship-Linux.zip"

var _dir := ""
var _root := ""
var _http: RefCounted


func _setup(name: String) -> void:
	_dir = temp_dir(name)
	_root = _dir.path_join("ports")
	DirAccess.make_dir_recursive_absolute(_root)
	_http = FakeHttp.new()


func _port(extra_files := ["gamecontrollerdb.txt"]) -> Dictionary:
	return {
		"id": "starship",
		"name": "Starship",
		"repo": "HarbourMasters/Starship",
		"asset_suffix": "-linux.zip",
		"launch": {"executable": "starship.appimage", "cwd": "current", "args": []},
		"extra_files": extra_files,
	}


func _zip(path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	check(packer.open(path) == OK, "zip opens")
	for name in entries:
		packer.start_file(name)
		packer.write_file((entries[name] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()


func _good_zip(tag := "new") -> String:
	var path := _dir.path_join("good-%s.zip" % tag)
	_zip(
		path,
		{
			"starship.appimage": "#!/bin/sh\necho %s\n" % tag,
			"config.yml": "x: 1\n",
			"assets/a/b.yaml": "k: v\n",
			"gamecontrollerdb.txt": "db %s\n" % tag,
		}
	)
	return path


func _release(path: String, url := ZIP_URL, name := "Starship-Linux.zip", size := -1) -> Dictionary:
	return {
		"tag": "v2.0.0",
		"asset":
		{
			"name": name,
			"url": url,
			"size": FileAccess.get_file_as_bytes(path).size() if size < 0 else size
		},
	}


func _run(
	action: String, port: Dictionary, release: Dictionary, progress := Callable()
) -> Dictionary:
	var installer := Installer.new(_root, _http)
	installer.threaded = false
	var got := []
	var done := func(r: Dictionary) -> void: got.append(r)
	if action == "install":
		installer.install(port, release, progress, done)
	else:
		installer.update(port, release, progress, done)
	check(got.size() == 1, "done is called exactly once")
	return got[0] if got.size() == 1 else {}


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _install_old() -> void:
	var current := Installer.current_dir(_root, "starship")
	DirAccess.make_dir_recursive_absolute(current)
	var file := FileAccess.open(current.path_join("marker"), FileAccess.WRITE)
	file.store_string("old")
	file.close()


func _old_is_intact() -> bool:
	return _text(Installer.current_dir(_root, "starship").path_join("marker")) == "old"


func test_install_a_zip() -> void:
	_setup("inst_zip")
	var zip := _good_zip()
	_http.files[ZIP_URL] = zip
	var steps := []
	var result := _run(
		"install",
		_port(),
		_release(zip),
		func(s: String, d: int, t: int) -> void: steps.append([s, d, t])
	)
	check(result["ok"], "installed: %s" % result.get("error", ""))
	eq(result["version"], "v2.0.0", "version")
	var current := Installer.current_dir(_root, "starship")
	eq(_text(current.path_join("config.yml")), "x: 1\n", "config.yml next to the executable")
	eq(_text(current.path_join("assets/a/b.yaml")), "k: v\n", "nested entries")
	check(
		FileAccess.get_unix_permissions(current.path_join("starship.appimage")) & 64 != 0,
		"executable"
	)
	eq(
		_text(Installer.data_dir(_root, "starship").path_join("gamecontrollerdb.txt")),
		"db new\n",
		"extra file in data"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship")),
		"download/ gone"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.previous_dir(_root, "starship")),
		"no previous on a first install"
	)
	check(steps[0][0] == "download" and steps[0][1] == 0, "starts at 0 bytes")
	var downloads := steps.filter(func(s: Array) -> bool: return s[0] == "download")
	check(downloads.size() > 3, "progress arrives in several steps")
	eq(downloads[-1][1], downloads[-1][2], "last download step is complete")
	eq(steps[-1][0], "finish", "ends on finish")
	remove(_dir)


func test_install_a_bare_appimage_under_the_catalog_name() -> void:
	_setup("inst_bare")
	var file := _dir.path_join("raw")
	var out := FileAccess.open(file, FileAccess.WRITE)
	out.store_string("ELF")
	out.close()
	var url := (
		"https://github.com/HarbourMasters/Shipwright/releases/download/9.3.1/"
		+ "SoH-Dewey-Bravo.appimage"
	)
	_http.files[url] = file
	var port := {
		"id": "soh",
		"repo": "HarbourMasters/Shipwright",
		"asset_suffix": ".appimage",
		"launch": {"executable": "soh.appimage", "cwd": "data", "args": []},
		"extra_files": [],
	}
	var result := _run("install", port, _release(file, url, "SoH-Dewey-Bravo.appimage"))
	check(result["ok"], "installed: %s" % result.get("error", ""))
	var exe := Installer.current_dir(_root, "soh").path_join("soh.appimage")
	eq(_text(exe), "ELF", "content")
	check(FileAccess.get_unix_permissions(exe) & 64 != 0, "marked executable")
	remove(_dir)


func test_a_size_that_does_not_match_the_release_fails() -> void:
	_setup("inst_size")
	var zip := _good_zip()
	_http.files[ZIP_URL] = zip
	var result := _run("install", _port(), _release(zip, ZIP_URL, "Starship-Linux.zip", 12345))
	check(not result["ok"], "failed")
	check("12345" in result["error"], "says what it expected")
	check(
		not DirAccess.dir_exists_absolute(Installer.current_dir(_root, "starship")), "no current/"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship")), "no download/"
	)
	remove(_dir)


func _sha256(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


func test_the_sha256_digest_is_checked_when_the_release_has_one() -> void:
	_setup("inst_digest")
	_install_old()
	var zip := _good_zip()
	_http.files[ZIP_URL] = zip
	var release := _release(zip)
	release["asset"]["sha256"] = "0".repeat(64)
	var result := _run("update", _port(), release)
	check(not result["ok"], "a wrong digest fails (PORT-3)")
	check("SHA-256" in result["error"], "says why: %s" % result["error"])
	check(_old_is_intact(), "the old version stays")
	check(not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship")), "cleaned")
	release["asset"]["sha256"] = _sha256(zip)
	result = _run("update", _port(), release)
	check(result["ok"], "the right digest installs: %s" % result["error"])
	release["asset"].erase("sha256")
	result = _run("update", _port(), release)
	check(result["ok"], "no digest (Starship v2.0.0): the size is enough")
	remove(_dir)


func test_hostile_zip_entries_are_rejected_before_anything_is_written() -> void:
	for bad in ["../evil.txt", "/abs/evil.txt", "a/../../evil.txt", "..\\evil.txt", "C:/evil.txt"]:
		_setup("inst_evil")
		var zip := _dir.path_join("evil.zip")
		_zip(zip, {"starship.appimage": "x", "gamecontrollerdb.txt": "x", bad: "owned"})
		_http.files[ZIP_URL] = zip
		var result := _run("install", _port(), _release(zip))
		check(not result["ok"], "%s rejected" % bad)
		check("unsafe" in result["error"], "%s: says why" % bad)
		check(
			not DirAccess.dir_exists_absolute(Installer.current_dir(_root, "starship")),
			"no current/ for %s" % bad
		)
		check(
			not FileAccess.file_exists(_dir.path_join("evil.txt")), "%s wrote nothing outside" % bad
		)
		check(
			not FileAccess.file_exists(_root.path_join("evil.txt")),
			"%s wrote nothing in root" % bad
		)
		check(not FileAccess.file_exists("/abs/evil.txt"), "%s wrote nothing at /abs" % bad)
		remove(_dir)


func test_bad_archives_fail_without_touching_current() -> void:
	_setup("inst_bad")
	_install_old()
	var notzip := _dir.path_join("notzip")
	var f := FileAccess.open(notzip, FileAccess.WRITE)
	f.store_string("this is not a zip")
	f.close()
	_http.files[ZIP_URL] = notzip
	var result := _run("update", _port(), _release(notzip))
	check(not result["ok"], "not a zip fails")
	check(_old_is_intact(), "old version intact")
	var no_exe := _dir.path_join("noexe.zip")
	_zip(no_exe, {"readme.txt": "x", "gamecontrollerdb.txt": "x"})
	_http.files[ZIP_URL] = no_exe
	result = _run("update", _port(), _release(no_exe))
	check(not result["ok"] and "starship.appimage" in result["error"], "missing executable named")
	check(_old_is_intact(), "old version intact")
	var no_extra := _dir.path_join("noextra.zip")
	_zip(no_extra, {"starship.appimage": "x"})
	_http.files[ZIP_URL] = no_extra
	result = _run("update", _port(), _release(no_extra))
	check(
		not result["ok"] and "gamecontrollerdb.txt" in result["error"], "missing extra file named"
	)
	check(_old_is_intact(), "old version intact")
	check(
		not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship")), "no download/"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.previous_dir(_root, "starship")), "no previous/"
	)
	remove(_dir)


func test_a_failed_download_leaves_current_alone() -> void:
	_setup("inst_fail")
	_install_old()
	var zip := _good_zip()
	_http.status[ZIP_URL] = 500
	var result := _run("update", _port(), _release(zip))
	check(not result["ok"] and not result["cancelled"], "failed, not cancelled")
	check(_old_is_intact(), "old version intact")
	_http.status.clear()
	_http.offline = true
	result = _run("update", _port(), _release(zip))
	check(not result["ok"], "offline fails")
	check(_old_is_intact(), "old version intact")
	remove(_dir)


func test_cancel_cleans_the_download_folder() -> void:
	_setup("inst_cancel")
	var zip := _good_zip()
	_http.files[ZIP_URL] = zip
	var installer := Installer.new(_root, _http)
	installer.threaded = false
	var got := []
	var seen_download_dir := []
	installer.install(
		_port(),
		_release(zip),
		func(stage: String, done: int, _total: int) -> void:
			if stage == "download" and done >= 8 and got.is_empty():
				seen_download_dir.append(
					DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship"))
				)
				installer.cancel(),
		func(r: Dictionary) -> void: got.append(r)
	)
	eq(got.size(), 1, "done once")
	check(got[0]["cancelled"] and not got[0]["ok"], "cancelled")
	eq(seen_download_dir, [true], "the download folder existed while downloading")
	check(
		not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "starship")),
		"download/ removed"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.current_dir(_root, "starship")), "no current/"
	)
	remove(_dir)


func test_update_swaps_and_keeps_the_old_version_as_previous() -> void:
	_setup("inst_update")
	_install_old()
	var data := Installer.data_dir(_root, "starship")
	DirAccess.make_dir_recursive_absolute(data)
	var save := FileAccess.open(data.path_join("save.bin"), FileAccess.WRITE)
	save.store_string("save")
	save.close()
	var zip := _good_zip("v2")
	_http.files[ZIP_URL] = zip
	var result := _run("update", _port(), _release(zip))
	check(result["ok"], "updated: %s" % result.get("error", ""))
	var current := Installer.current_dir(_root, "starship")
	var previous := Installer.previous_dir(_root, "starship")
	check(FileAccess.file_exists(current.path_join("config.yml")), "new version in current/")
	check(not FileAccess.file_exists(current.path_join("marker")), "old file not in current/")
	eq(_text(previous.path_join("marker")), "old", "old version moved to previous/")
	eq(_text(data.path_join("save.bin")), "save", "data untouched")
	eq(_text(data.path_join("gamecontrollerdb.txt")), "db v2\n", "extra file refreshed")
	var again := _good_zip("v3")
	_http.files[ZIP_URL] = again
	result = _run("update", _port(), _release(again))
	check(result["ok"], "second update")
	check(not FileAccess.file_exists(previous.path_join("marker")), "older previous/ replaced")
	check(
		_text(previous.path_join("starship.appimage")).contains("v2"),
		"previous is the version before"
	)
	Installer.cleanup_previous(_root, "starship")
	check(not DirAccess.dir_exists_absolute(previous), "cleanup_previous removes it")
	check(DirAccess.dir_exists_absolute(current), "and keeps current/")
	remove(_dir)


func test_extra_folders_are_copied_to_data_and_replaced_on_update() -> void:
	_setup("inst_folder")
	var port := _port(["gamecontrollerdb.txt", "config.yml", "assets"])
	var zip := _good_zip("v1")
	_http.files[ZIP_URL] = zip
	check(_run("install", port, _release(zip))["ok"], "installed")
	var data := Installer.data_dir(_root, "starship")
	eq(_text(data.path_join("config.yml")), "x: 1\n", "file next to the folder")
	eq(_text(data.path_join("assets/a/b.yaml")), "k: v\n", "folder copied with its subfolders")
	var stale := FileAccess.open(data.path_join("assets/old.yaml"), FileAccess.WRITE)
	stale.store_string("old")
	stale.close()
	FileAccess.open(data.path_join("sf64.o2r"), FileAccess.WRITE).close()
	zip = _good_zip("v2")
	_http.files[ZIP_URL] = zip
	check(_run("update", port, _release(zip))["ok"], "updated")
	check(not FileAccess.file_exists(data.path_join("assets/old.yaml")), "old folder replaced")
	check(FileAccess.file_exists(data.path_join("assets/a/b.yaml")), "new folder in place")
	check(FileAccess.file_exists(data.path_join("sf64.o2r")), "the archive survives an update")
	remove(_dir)


func test_a_write_error_while_unpacking_fails() -> void:
	_setup("inst_full")
	if not FileAccess.file_exists("/dev/full"):
		remove(_dir)
		return
	var zip := _dir.path_join("full.zip")
	# Larger than stdio's buffer, so the write itself fails, as for a real program file.
	_zip(zip, {"big.bin": "x".repeat(65536)})
	var dest := _dir.path_join("dest")
	DirAccess.make_dir_recursive_absolute(dest)
	# Writing through a link to /dev/full fails like a full disk (ENOSPC).
	OS.execute("ln", ["-s", "/dev/full", dest.path_join("big.bin")])
	var error := Installer.extract_zip(zip, dest)
	check(error.begins_with("Could not write “big.bin”"), "a full disk is an error: %s" % error)
	remove(_dir)


func test_swap_failure_restores_current() -> void:
	_setup("inst_swap")
	_install_old()
	var port_path := Installer.port_dir(_root, "starship")
	var error := Installer.swap(port_path, port_path.path_join("download/missing"))
	check(not error.is_empty(), "reports the failure")
	check(_old_is_intact(), "current/ is back")
	check(
		not DirAccess.dir_exists_absolute(Installer.previous_dir(_root, "starship")),
		"previous/ is empty again"
	)
	remove(_dir)


func test_a_release_from_a_foreign_url_is_never_requested() -> void:
	_setup("inst_foreign")
	var zip := _good_zip()
	var url := "https://evil.example/Starship-Linux.zip"
	_http.files[url] = zip
	var result := _run("install", _port(), _release(zip, url))
	check(not result["ok"], "refused")
	eq(_http.requests.size(), 0, "no request made")
	remove(_dir)


func test_remove_deletes_the_program_but_not_the_data() -> void:
	_setup("inst_remove")
	_install_old()
	DirAccess.make_dir_recursive_absolute(Installer.previous_dir(_root, "starship"))
	var data := Installer.data_dir(_root, "starship")
	DirAccess.make_dir_recursive_absolute(data.path_join("saves"))
	var file := FileAccess.open(data.path_join("saves/a.sav"), FileAccess.WRITE)
	file.store_string("s")
	file.close()
	var result := Installer.remove(_root, "starship")
	check(result["ok"], "removed")
	check(
		not DirAccess.dir_exists_absolute(Installer.current_dir(_root, "starship")), "current/ gone"
	)
	check(
		not DirAccess.dir_exists_absolute(Installer.previous_dir(_root, "starship")),
		"previous/ gone"
	)
	eq(_text(data.path_join("saves/a.sav")), "s", "data kept")
	check(Installer.remove(_root, "never-installed")["ok"], "removing nothing is fine")
	remove(_dir)


## A remove that stops part-way (here previous/ can't be deleted; a kill is the same) must
## not leave previous/ without current/, which cleanup_stale would put back as current/
## while state.ini still names the newer version (PORT-7, PORT-12).
func test_a_remove_that_stops_part_way_never_brings_back_the_old_version() -> void:
	_setup("inst_remove_order")
	_install_old()
	var previous := Installer.previous_dir(_root, "starship")
	DirAccess.make_dir_recursive_absolute(previous.path_join("locked"))
	FileAccess.open(previous.path_join("locked/file"), FileAccess.WRITE).close()
	FileAccess.set_unix_permissions(previous.path_join("locked"), 365)  # r-xr-xr-x
	var result := Installer.remove(_root, "starship")
	FileAccess.set_unix_permissions(previous.path_join("locked"), 493)
	check(not result["ok"], "the remove reports the failure")
	Installer.cleanup_stale(_root)
	check(_old_is_intact(), "current/ is still the installed version: previous/ goes first")
	remove(_dir)


func test_cleanup_stale_removes_download_folders_and_finishes_a_killed_swap() -> void:
	_setup("inst_stale")
	var junk := Installer.download_dir(_root, "a").path_join("staging/deep")
	DirAccess.make_dir_recursive_absolute(junk)
	DirAccess.make_dir_recursive_absolute(Installer.current_dir(_root, "a"))
	DirAccess.make_dir_recursive_absolute(Installer.previous_dir(_root, "b"))
	var hidden := FileAccess.open(
		Installer.previous_dir(_root, "b").path_join(".hidden"), FileAccess.WRITE
	)
	hidden.close()
	eq(Installer.cleanup_stale(_root), 2, "one download folder and one restored swap")
	check(not DirAccess.dir_exists_absolute(Installer.download_dir(_root, "a")), "download/ gone")
	check(DirAccess.dir_exists_absolute(Installer.current_dir(_root, "a")), "a keeps current/")
	check(
		FileAccess.file_exists(Installer.current_dir(_root, "b").path_join(".hidden")),
		"b's previous/ is current/ again"
	)
	eq(Installer.cleanup_stale(_dir.path_join("nothing-here")), 0, "missing root is fine")
	remove(_dir)


func test_rm_rf_does_not_follow_links() -> void:
	_setup("inst_link")
	var outside := _dir.path_join("outside")
	DirAccess.make_dir_recursive_absolute(outside)
	var file := FileAccess.open(outside.path_join("keep"), FileAccess.WRITE)
	file.close()
	var victim := _dir.path_join("victim")
	DirAccess.make_dir_recursive_absolute(victim)
	OS.execute("ln", ["-s", outside, victim.path_join("link")])
	Installer.rm_rf(victim)
	check(not DirAccess.dir_exists_absolute(victim), "victim removed")
	check(FileAccess.file_exists(outside.path_join("keep")), "link target kept")
	remove(_dir)


## A worker task that ends without a result (a script error inside it) must still hand
## `finished` something, or the install stays at "Unpacking" forever.
func test_a_worker_task_without_a_result_still_finishes() -> void:
	var installer := Installer.new("/nonexistent", FakeHttp.new())
	var got := []
	installer._offload(
		func() -> Variant: return null, func(r: String) -> void: got.append(r), "fallback"
	)
	for _i in 100:
		if not got.is_empty():
			break
		await (Engine.get_main_loop() as SceneTree).process_frame
	eq(got, ["fallback"], "the fallback result arrives")

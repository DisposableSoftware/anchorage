extends "res://tests/case.gd"

const State := preload("res://src/state.gd")


func test_round_trip() -> void:
	var dir := temp_dir("state_rt")
	var path := dir.path_join("anchorage/state.ini")
	var state := State.load_from(path)
	state.set_installed("soh", "9.3.1")
	state.set_latest("soh", "9.4.0")
	state.set_latest("2ship", "5.0.1")
	state.set_last_check(1234567)
	state.set_rom_cache({"/roms/a b=c.z64": {"size": 3, "mtime": 4, "sha1": "x"}})
	var again := State.load_from(path)
	eq(again.installed_version("soh"), "9.3.1", "installed")
	eq(again.latest_version("soh"), "9.4.0", "latest")
	eq(again.latest_version("2ship"), "5.0.1", "id with a digit")
	eq(again.installed_version("2ship"), "", "unknown is empty")
	eq(again.last_check(), 1234567, "time")
	eq(again.rom_cache()["/roms/a b=c.z64"]["size"], 3.0, "cache, odd path kept")
	again.clear_installed("soh")
	eq(State.load_from(path).installed_version("soh"), "", "cleared and saved")
	again.set_rom_dirs(["/run/media/deck/My Card/roms/n64\n[ports]", "/a;b", "", "/a;b"])
	eq(
		State.load_from(path).rom_dirs(),
		["/run/media/deck/My Card/roms/n64 [ports]", "/a;b"],
		"the chosen ROM folders in order (ROM-12, ROM-17), each on one line, once"
	)
	eq(State.load_from(path).rom_cache().size(), 1, "next to the cache")
	remove(dir)


## ROM-12: an older state.ini kept one folder as `[roms] directory`; it loads as a list of
## one, and the first folder is still written there for an older Anchorage.
func test_an_old_single_rom_folder_loads_as_a_list() -> void:
	var dir := temp_dir("state_roms_old")
	var path := dir.path_join("state.ini")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[ports]\nsoh.installed = 9.3.1\n\n[roms]\ndirectory = /home/deck/Roms\n")
	file.close()
	var state := State.load_from(path)
	eq(state.rom_dirs(), ["/home/deck/Roms"], "one folder")
	eq(state.installed_version("soh"), "9.3.1", "the rest as before")
	state.set_rom_dirs(state.rom_dirs() + ["/run/media/deck/SD/n64"])
	var text := FileAccess.get_file_as_string(path)
	check(text.contains('directories = ["/home/deck/Roms","/run/media/deck/SD/n64"]'), text)
	check(text.contains("directory = /home/deck/Roms\n"), "the first one for older versions")
	eq(State.load_from(path).rom_dirs().size(), 2, "the list wins over the single key")
	state.set_rom_dirs([])
	eq(State.load_from(path).rom_dirs(), [], "none left")
	check(not FileAccess.get_file_as_string(path).contains("directory"), "and nothing written")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[roms]\ndirectories = {"odd": 1}\ndirectory = /x\n')
	file.close()
	eq(State.load_from(path).rom_dirs(), ["/x"], "a broken list falls back to the single key")
	remove(dir)


func test_catalog_check_version_and_new_ports_round_trip() -> void:
	var dir := temp_dir("state_catalog")
	var path := dir.path_join("anchorage/state.ini")
	var state := State.load_from(path)
	eq(state.catalog(), {"last_check": 0, "version": 0, "new": []}, "nothing yet")
	state.set_catalog({"last_check": 1234, "version": 3, "new": ["gamma", "delta", "gamma"]})
	var again := State.load_from(path)
	eq(again.catalog()["last_check"], 1234, "the catalog's own check time (PORT-18)")
	eq(again.catalog()["version"], 3, "the announced version")
	eq(again.catalog()["new"], ["gamma", "delta"], "the new ports, once each (PORT-23)")
	again.set_catalog({"new": ["delta"]})
	eq(State.load_from(path).catalog()["new"], ["delta"], "one cleared and saved")
	eq(State.load_from(path).catalog()["version"], 3, "the rest kept")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[catalog]\nnew = ok, ../bad, Upper,x\nversion = nope\n")
	file.close()
	again = State.load_from(path)
	eq(again.catalog()["new"], ["ok", "x"], "good ids read, bad ones ignored")
	eq(again.catalog()["version"], 0, "a broken number is 0")
	remove(dir)


func test_missing_or_broken_files_remember_nothing() -> void:
	var dir := temp_dir("state_broken")
	var missing := State.load_from(dir.path_join("nope/state.ini"))
	eq(missing.installed_version("soh"), "", "missing")
	eq(missing.last_check(), 0, "no time")
	var path := dir.path_join("state.ini")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(
		"garbage\n[ports\nsoh.installed\n[updates]\nlast_check = soon\n[roms]\ncache = {nope\n"
	)
	file.close()
	var state := State.load_from(path)
	eq(state.installed_version("soh"), "", "garbage ignored")
	eq(state.last_check(), 0, "bad time")
	eq(state.rom_cache(), {}, "bad cache")
	state.set_installed("soh", "1")
	eq(State.load_from(path).installed_version("soh"), "1", "still writable")
	remove(dir)


func test_write_is_atomic_and_leaves_no_temp_file() -> void:
	var dir := temp_dir("state_atomic")
	var path := dir.path_join("state.ini")
	var state := State.load_from(path)
	state.set_installed("soh", "1")
	check(FileAccess.file_exists(path), "state.ini exists")
	check(not FileAccess.file_exists(path + ".tmp"), "temp file renamed away")
	var inode_before := FileAccess.get_modified_time(path)
	state.set_installed("soh", "2")
	check(inode_before <= FileAccess.get_modified_time(path), "replaced")
	eq(FileAccess.get_file_as_string(path).count("soh.installed"), 1, "one line, not appended")
	remove(dir)


func test_a_stale_temp_file_from_a_killed_write_is_ignored() -> void:
	var dir := temp_dir("state_stale")
	var path := dir.path_join("state.ini")
	var state := State.load_from(path)
	state.set_installed("soh", "good")
	var tmp := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	tmp.store_string("[ports]\nsoh.installed = half")
	tmp.close()
	eq(State.load_from(path).installed_version("soh"), "good", "the real file wins")
	state.set_installed("soh", "next")
	eq(State.load_from(path).installed_version("soh"), "next", "next save replaces the temp file")
	remove(dir)


func test_newlines_cannot_inject_lines() -> void:
	var dir := temp_dir("state_inject")
	var path := dir.path_join("state.ini")
	var state := State.load_from(path)
	state.set_installed("soh", "1\n[updates]\nlast_check = 99")
	eq(State.load_from(path).last_check(), 0, "no injected section")
	remove(dir)


func test_default_path_follows_xdg_state_home() -> void:
	var before := OS.get_environment("XDG_STATE_HOME")
	OS.set_environment("XDG_STATE_HOME", "/tmp/xdg-state-test")
	eq(State.default_path(), "/tmp/xdg-state-test/anchorage/state.ini", "XDG_STATE_HOME")
	OS.set_environment("XDG_STATE_HOME", "")
	check(State.default_path().ends_with("/.local/state/anchorage/state.ini"), "fallback")
	OS.set_environment("XDG_STATE_HOME", before)

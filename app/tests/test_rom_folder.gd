extends "res://tests/case.gd"
## The ROM folder in `Ports` (ROM-10, ROM-12, ROM-13, ROM-14) over fake home and mount
## trees, and the chooser screen (ROM-11) over ports_fake and over the real Ports on a temp
## tree, driven with input events like test_home.

const Ports := preload("res://src/ports.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const State := preload("res://src/state.gd")
const Roms := preload("res://src/roms.gd")
const RomFolders := preload("res://src/rom_folders.gd")
const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const HomeScene := preload("res://scenes/home.tscn")
const ChooserScene := preload("res://scenes/rom_folder.tscn")

var _dir := ""
var _rom := PackedByteArray()


func _setup(name: String) -> void:
	_dir = temp_dir(name)
	_rom = PackedByteArray([0x80, 0x37, 0x12, 0x40])
	for i in 60:
		_rom.append(i)


func _home() -> String:
	return _dir.path_join("home/deck")


func _catalog() -> Array:
	return [
		{
			"id": "alpha",
			"name": "Alpha",
			"game": "Game alpha",
			"description": "About alpha",
			"repo": "test/alpha",
			"asset_suffix": "-linux.zip",
			"archive": ["alpha.o2r"],
			"launch": {"executable": "alpha.appimage", "cwd": "data", "args": []},
			"extra_files": [],
			"rom_place": "data_dir",
			"rom_file": "alpha.z64",
			"roms": [{"label": "US", "sha1": Roms.sha1_of(_rom)}],
		}
	]


## Writes the matching ROM into `rel` (under the test folder) and returns the folder.
func _put_rom(rel: String) -> String:
	var dir := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("Alpha (USA).z64"), FileAccess.WRITE)
	file.store_buffer(_rom)
	file.close()
	return dir


func _write(rel: String, text: String) -> void:
	var path := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _make(roms_dir := "", threaded := false) -> Node:
	var ports: Node = Ports.new()
	ports.root = _dir.path_join("ports")
	ports.state_path = _dir.path_join("state/state.ini")
	ports.roms_dir = roms_dir
	ports.config_file = _home().path_join(".config/anchorage/config.ini")
	ports.home = _home()
	ports.media_dir = _dir.path_join("media")
	ports.mounts_file = "/nonexistent/mounts"
	ports.check_updates = false
	ports.catalog = _catalog()
	ports.http = FakeHttp.new()
	ports.threaded = threaded
	ports.clock = func() -> int: return 1_800_000_000
	(Engine.get_main_loop() as SceneTree).root.add_child(ports)
	return ports


func _free(ports: Node) -> void:
	ports.get_parent().remove_child(ports)
	ports.free()


func _state_text() -> String:
	return FileAccess.get_file_as_string(_dir.path_join("state/state.ini"))


func _frames(until: Callable, limit := 200) -> void:
	for _i in limit:
		if until.call():
			return
		await (Engine.get_main_loop() as SceneTree).process_frame


# Ports --------------------------------------------------------------------------------


func test_the_folder_is_found_at_start() -> void:
	_setup("folder_found")
	var emu := _put_rom("card/Emulation/roms/n64")
	_write("home/deck/.config/EmuDeck/settings.sh", "romsPath=%s\n" % emu.get_base_dir())
	var ports := _make()
	var info: Dictionary = ports.rom_folder_info()
	eq([info.full, info.source, info.locked], [emu, "emudeck", false], "EmuDeck's (ROM-10, 15)")
	check(ports.info("alpha").rom.found, "and scanned")
	_free(ports)
	remove(_dir)


func test_nothing_found_runs_the_sd_card_search_once() -> void:
	_setup("folder_search")
	DirAccess.make_dir_recursive_absolute(_home().path_join("Emulation"))
	var ports := _make()
	eq(ports.rom_folder_info().source, "fallback", "nothing found, no card")
	eq(ports.rom_folder_info().path, "~/Emulation/roms/n64", "~/Emulation exists (ROM-10)")
	eq(ports.search_info().status, "no_card", "the search ran and found no card")
	eq(ports.info("alpha").rom.label, "ROM folder not found", "a normal state (ROM-1)")
	eq(ports.info("alpha").rom.path, "~/Emulation/roms/n64", "where it looked")
	_free(ports)
	var card := _put_rom("media/mmcblk0p1/games/nintendo")
	ports = _make()
	eq(ports.rom_folder_info().full, card, "the search's first result (ROM-10 step 4)")
	eq(ports.rom_folder_info().source, "search", "source")
	check(ports.info("alpha").rom.found, "scanned")
	eq(ports.search_info().results.size(), 1, "results kept for the chooser")
	check(not _state_text().contains("directory"), "a found folder is not stored")
	_free(ports)
	remove(_dir)


func test_a_chosen_folder_is_stored_and_rescanned_at_once() -> void:
	_setup("folder_chosen")
	var ports := _make()
	eq(ports.info("alpha").rom.label, "ROM folder not found", "nothing yet")
	var chosen := _put_rom("Games/N64 stuff")
	var heard := []
	ports.rom_folder_changed.connect(func() -> void: heard.append("folder"))
	ports.changed.connect(func(id: String) -> void: heard.append(id))
	ports.set_rom_folder(chosen)
	check(ports.info("alpha").rom.found, "rescanned at once (ROM-13)")
	check(heard.has("folder") and heard.has("alpha"), "the chooser and the cards hear it")
	eq(ports.rom_folder_info().source, "chosen", "source")
	check(_state_text().contains("directory = " + chosen), "stored in state.ini (ROM-12)")
	_free(ports)
	var emu := _put_rom("emu/roms/n64")
	_write("home/deck/emudeck/settings.sh", "romsPath=%s\n" % emu.get_base_dir())
	ports = _make()
	eq(ports.rom_folder_info().full, chosen, "a chosen folder beats detection on the next start")
	ports.set_rom_folder("relative/path")
	eq(ports.rom_folder_info().full, chosen, "a relative path is refused")
	_free(ports)
	remove(_dir)


func test_config_ini_wins_and_is_never_written() -> void:
	_setup("folder_config")
	var configured := _put_rom("configured")
	var ports := _make()
	ports.set_rom_folder(_put_rom("chosen"))
	_free(ports)
	ports = _make(configured)
	var info: Dictionary = ports.rom_folder_info()
	eq([info.full, info.source, info.locked], [configured, "config", true], "config.ini wins")
	eq(info.config_file, "~/.config/anchorage/config.ini", "the chooser can name the file")
	ports.set_rom_folder(_dir.path_join("other"))
	eq(ports.rom_folder_info().full, configured, "the chooser cannot change it (ROM-12)")
	check(_state_text().contains("chosen"), "the stored choice stays for when config is unset")
	check(
		not FileAccess.file_exists(_home().path_join(".config/anchorage/config.ini")),
		"config.ini is never written (CONF-3)"
	)
	_free(ports)
	remove(_dir)


func test_browse_answers_with_a_signal() -> void:
	_setup("folder_browse")
	_put_rom("home/deck/Emulation/roms/n64")
	DirAccess.make_dir_recursive_absolute(_home().path_join(".local/share"))
	var ports := _make(_home().path_join("Emulation/roms/n64"))
	var got := []
	ports.folder_listed.connect(func(p: String, l: Dictionary) -> void: got.append([p, l]))
	ports.browse(_home())
	eq(got.size(), 1, "one answer")
	eq(got[0][0], _home(), "for the path asked")
	eq(
		got[0][1].folders.map(func(f: Dictionary) -> String: return f.name),
		["Emulation"],
		"hidden folders are not listed"
	)
	got.clear()
	ports.browse("")
	eq(got[0][1].path, _home().path_join("Emulation/roms/n64"), "empty: the ROM folder")
	eq(got[0][1].roms, 1, "with its count")
	_free(ports)
	remove(_dir)


func test_detection_browse_and_search_run_off_the_main_thread() -> void:
	_setup("folder_threads")
	var emu := _put_rom("emu/Emulation/roms/n64")
	_write(
		"home/deck/.config/EmuDeck/settings.sh",
		"emulationPath=%s\n" % emu.get_base_dir().get_base_dir()
	)
	_put_rom("media/mmcblk0p1/Emulation/roms/n64")
	var ports := _make("", true)
	eq(ports.rom_folder_info().path, "", "the UI does not wait for detection")
	eq(ports.info("alpha").rom.label, "Looking for ROMs", "the cards say so")
	await _frames(func() -> bool: return ports.info("alpha").rom.found)
	eq(ports.rom_folder_info().source, "emudeck", "found on the worker pool")
	var got := []
	ports.folder_listed.connect(func(p: String, _l: Dictionary) -> void: got.append(p))
	ports.browse(_home())
	eq(got, [], "browse answers later")
	await _frames(func() -> bool: return not got.is_empty())
	eq(got, [_home()], "and then once")
	ports.search_sd_card()
	eq(ports.search_info().status, "running", "the search runs on a thread (ROM-14)")
	await _frames(func() -> bool: return ports.search_info().status != "running")
	eq(ports.search_info().results.size(), 1, "and finds the card's folder")
	ports.search_sd_card()
	ports.cancel_search()
	await _frames(func() -> bool: return ports.search_info().status != "running")
	check(ports.search_info().status in ["cancelled", "done"], "a cancelled search ends")
	eq(ports.rom_folder_info().source, "emudeck", "a search the user ran changes nothing")
	_free(ports)
	remove(_dir)


func test_a_choice_during_a_scan_counts_only_the_new_folder() -> void:
	_setup("folder_rescan")
	var first := _put_rom("first")
	var ports := _make(first, true)
	ports.roms_dir = ""
	var empty := _dir.path_join("empty")
	DirAccess.make_dir_recursive_absolute(empty)
	ports.set_rom_folder(empty)
	await _frames(func() -> bool: return ports._scan_job == null)
	eq(ports.info("alpha").rom.label, "No matching ROM", "the new folder's result (ROM-13)")
	eq(ports.info("alpha").rom.path, empty, "and its path")
	_free(ports)
	remove(_dir)


# The chooser screen --------------------------------------------------------------------


func _host() -> Control:
	Keys.apply({})
	var host := Control.new()
	host.theme = Style.build("mocha", "mauve")
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	return host


func _home_screen(scenario := "showcase") -> Control:
	var host := _host()
	var ports := PortsFake.new(scenario)
	ports.simulate = false
	host.add_child(ports)
	var home := HomeScene.instantiate()
	home.ports = ports
	host.add_child(home)
	return home


func _done(node: Control) -> void:
	var host := node.get_parent()
	host.get_parent().remove_child(host)
	host.free()


func _press(node: Control, keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		node.get_viewport().push_input(key)


func _focus_text(node: Control) -> String:
	var focus := node.get_viewport().gui_get_focus_owner()
	return focus.text if focus is Button else ""


func test_the_options_menu_opens_the_chooser_in_the_rom_folder() -> void:
	var home := _home_screen()
	_press(home, KEY_O)
	_press(home, KEY_DOWN)
	_press(home, KEY_DOWN)
	eq(_focus_text(home), "ROM folder", "ROM folder after Check for updates (HOME-5)")
	_press(home, KEY_ENTER)
	var chooser: Control = home.chooser()
	check(chooser != null and home.mode == home.Mode.CHOOSER, "opens the chooser (ROM-11)")
	eq(chooser.current_path(), "/home/deck/Emulation/roms/n64", "starts in the ROM folder")
	eq(chooser.row_texts().slice(0, 2), ["Search the SD card", "Use this folder"], "first rows")
	eq(chooser.place_texts(), ["Home", "SD card", "Backup"], "home and every drive")
	eq(_focus_text(home), "Search the SD card", "focus on the search")
	check(chooser.shown_text().contains("Now ~/Emulation/roms/n64, from EmuDeck's"), "source")
	check(chooser.hint_text().contains("Search"), "hints: " + chooser.hint_text())
	_press(home, KEY_DOWN)
	eq(_focus_text(home), "Use this folder", "down")
	check(chooser.shown_text().contains("holds 6 ROM files"), "the folder's count")
	_press(home, KEY_ESCAPE)
	eq(chooser.current_path(), "/home/deck/Emulation/roms", "back goes up")
	eq(_focus_text(home), "n64", "onto the folder it came from")
	check(chooser.shown_text().contains("“n64” holds 6 ROM files"), "the highlighted count")
	check(chooser.shown_text().contains("snes · 21 ROM files"), "counts on the rows")
	_press(home, KEY_DOWN)
	eq(_focus_text(home), "n64dd", "D-pad moves through the subfolders")
	check(chooser.shown_text().contains("“n64dd” holds no ROM files"), "an empty one")
	_press(home, KEY_ESCAPE)
	_press(home, KEY_ESCAPE)
	eq(chooser.current_path(), "/home/deck", "up to home")
	check(chooser.hint_text().contains("Close"), "back now closes: " + chooser.hint_text())
	_press(home, KEY_ESCAPE)
	eq(home.chooser(), null, "and leaves at a starting point")
	eq(home.mode, home.Mode.HOME, "home again")
	eq(home.get_viewport().gui_get_focus_owner(), home.card_for("soh"), "focus back on the card")
	eq(home.ports.calls.filter(func(c: Array) -> bool: return c[0] == "set_rom_folder"), [], "-")
	_done(home)


func test_open_a_folder_and_use_it() -> void:
	var home := _home_screen()
	home.open_chooser()
	var chooser: Control = home.chooser()
	_press(home, KEY_LEFT)
	eq(_focus_text(home), "Home", "left goes to the starting points")
	_press(home, KEY_DOWN)
	eq(_focus_text(home), "SD card", "down along them")
	_press(home, KEY_ENTER)
	eq(chooser.current_path(), "/run/media/mmcblk0p1", "accept on a place goes there")
	eq(_focus_text(home), "Emulation", "focus on its first folder")
	_press(home, KEY_ENTER)
	_press(home, KEY_ENTER)
	_press(home, KEY_ENTER)
	eq(chooser.current_path(), "/run/media/mmcblk0p1/Emulation/roms/n64", "accept opens")
	_press(home, KEY_O)
	eq(
		home.ports.calls.back(),
		["set_rom_folder", "/run/media/mmcblk0p1/Emulation/roms/n64"],
		"the options binding uses the folder shown (ROM-12)"
	)
	eq(home.chooser(), null, "and closes the chooser")
	eq(home.ports.rom_folder_info().source, "chosen", "chosen")
	home.open_chooser()
	chooser = home.chooser()
	_press(home, KEY_DOWN)
	_press(home, KEY_ENTER)
	eq(home.ports.calls.back()[0], "set_rom_folder", "accept on Use this folder")
	_done(home)


func test_the_rom_missing_hint_leads_to_the_chooser() -> void:
	var home := _home_screen("rom-missing")
	_press(home, KEY_ENTER)
	var notice: String = home.get_node("%Detail").notice()
	check(notice.contains("search the SD card"), "the hint offers it: " + notice)
	check(home.hint_text().contains("Choose ROM folder"), "hint bar: " + home.hint_text())
	_press(home, KEY_ENTER)
	check(home.chooser() != null, "accept while it shows opens the chooser (ROM-11)")
	_done(home)


func test_search_the_sd_card_from_the_chooser() -> void:
	var home := _home_screen()
	home.open_chooser()
	var chooser: Control = home.chooser()
	_press(home, KEY_ENTER)
	eq(home.ports.calls.back(), ["search_sd_card"], "the first entry searches (ROM-14)")
	check(chooser.shown_text().contains("Looking through the SD card"), chooser.shown_text())
	check(chooser.hint_text().contains("Cancel"), "back cancels: " + chooser.hint_text())
	_press(home, KEY_ESCAPE)
	eq(home.ports.calls.back(), ["cancel_search"], "cancelled with back")
	eq(_focus_text(home), "Search the SD card", "back in the folder")
	_press(home, KEY_ENTER)
	home.ports.finish_search()
	eq(
		chooser.row_texts(),
		["SD card › Emulation/roms/n64", "SD card › Emulation/roms/snes", "Backup › Roms/N64"],
		"each folder with ROM files, the SD card first"
	)
	check(chooser.shown_text().contains("Emulation/roms/n64 · 4 ROM files"), "with counts")
	check(chooser.shown_text().contains("3 folders with ROM files"), chooser.shown_text())
	eq(_focus_text(home), "SD card › Emulation/roms/n64", "focus on the first")
	_press(home, KEY_DOWN)
	_press(home, KEY_DOWN)
	_press(home, KEY_ENTER)
	eq(
		home.ports.calls.back(),
		["set_rom_folder", "/run/media/deck/Backup/Roms/N64"],
		"choosing one uses it"
	)
	eq(home.chooser(), null, "closed")
	_done(home)


func test_without_a_card_the_search_says_so() -> void:
	var home := _home_screen("no-card")
	home.open_chooser()
	var chooser: Control = home.chooser()
	eq(chooser.place_texts(), ["Home"], "no drives to start from")
	_press(home, KEY_ENTER)
	home.ports.finish_search()
	check(chooser.shown_text().contains("No SD card or drive found"), chooser.shown_text())
	eq(chooser.row_texts(), ["Search again"], "and offers to look again")
	_press(home, KEY_ESCAPE)
	eq(chooser.row_texts()[0], "Search the SD card", "back to browsing")
	_done(home)


func test_a_folder_set_in_config_ini_is_only_shown() -> void:
	var home := _home_screen("rom-config")
	home.open_chooser()
	var chooser: Control = home.chooser()
	var text: String = chooser.shown_text()
	check(text.contains("The ROM folder is set in config.ini"), "says so (ROM-12): " + text)
	check(text.contains("/mnt/games/n64"), "names the folder")
	check(text.contains("~/.config/anchorage/config.ini"), "and the file")
	eq(chooser.row_texts(), [], "nothing to choose")
	_press(home, KEY_O)
	_press(home, KEY_ENTER)
	eq(home.ports.calls.filter(func(c: Array) -> bool: return c[0] == "set_rom_folder"), [], "-")
	eq(chooser.hint_text().contains("Back"), true, "only back")
	_press(home, KEY_ESCAPE)
	eq(home.chooser(), null, "back leaves")
	_done(home)


func test_the_chooser_over_the_real_service_on_a_temp_tree() -> void:
	_setup("chooser_real")
	var n64 := _put_rom("home/deck/Emulation/roms/n64")
	DirAccess.make_dir_recursive_absolute(_home().path_join(".var/app"))
	DirAccess.make_dir_recursive_absolute(_home().path_join("Emulation/roms/.hidden"))
	DirAccess.make_dir_recursive_absolute(_home().path_join("Emulation/roms/gba"))
	DirAccess.make_dir_recursive_absolute(_dir.path_join("media/mmcblk0p1"))
	var ports := _make()
	ports.set_rom_folder(_home())
	check(not ports.info("alpha").rom.found, "home holds no ROM")
	var host := _host()
	var chooser := ChooserScene.instantiate()
	chooser.ports = ports
	host.add_child(chooser)
	eq(chooser.current_path(), _home(), "starts in the ROM folder")
	eq(chooser.row_texts(), ["Search the SD card", "Use this folder", "Emulation"], "no .var")
	eq(chooser.place_texts(), ["Home", "SD card"], "the card is a starting point")
	_press(chooser, KEY_DOWN)
	_press(chooser, KEY_DOWN)
	_press(chooser, KEY_ENTER)
	_press(chooser, KEY_ENTER)
	eq(chooser.row_texts().slice(2), ["gba", "n64"], "hidden folders are not listed (ROM-11)")
	check(chooser.shown_text().contains("n64 · 1 ROM file"), chooser.shown_text())
	_press(chooser, KEY_DOWN)
	_press(chooser, KEY_ENTER)
	eq(chooser.current_path(), n64, "opened")
	_press(chooser, KEY_O)
	eq(ports.rom_folder_info().full, n64, "chosen")
	check(ports.info("alpha").rom.found, "the cards update without a restart (ROM-13)")
	_done(chooser)
	_free(ports)
	remove(_dir)

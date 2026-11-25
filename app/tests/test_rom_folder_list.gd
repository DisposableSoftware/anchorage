extends "res://tests/rom_folder_case.gd"
## Several ROM folders in `Ports` (ROM-17, with ROM-1, ROM-7, ROM-10, ROM-12, ROM-13 and
## CONF-8): choosing adds, removing, an unmounted folder, the first folder winning, the
## found folder kept, a list in config.ini and an old state.ini.


## The bug from the Deck (ROM-17): a folder chosen for a second game replaced the first
## folder, so the first game went back to ROM missing.
func test_a_second_folder_keeps_the_first_games_rom() -> void:
	_setup("folder_second")
	var first := _put_rom("Games/A")
	var second := _put_beta_rom("Games/B")
	var ports := _make()
	ports.set_rom_folder(first)
	check(ports.info("alpha").rom.found, "game 1 found in folder A")
	check(not ports.info("beta").rom.found, "game 2 not yet")
	ports.set_rom_folder(second)
	check(ports.info("beta").rom.found, "game 2 found in folder B")
	check(ports.info("alpha").rom.found, "game 1 still found after folder B was chosen")
	_free(ports)
	ports = _make()
	check(ports.info("alpha").rom.found, "game 1 found after a restart")
	check(ports.info("beta").rom.found, "game 2 found after a restart")
	_free(ports)
	remove(_dir)


func test_remove_a_folder_and_the_last_one() -> void:
	_setup("folder_remove")
	var first := _put_rom("Games/A")
	var second := _put_beta_rom("Games/B")
	var ports := _make()
	ports.set_rom_folder(first)
	ports.set_rom_folder(second)
	ports.set_rom_folder(second + "/")
	eq(_chosen(ports), [first, second], "in the order chosen, once each (ROM-17)")
	eq(_statuses(ports), [["ok", 1], ["ok", 1]], "each serves one port")
	var heard := []
	ports.rom_folder_changed.connect(func() -> void: heard.append("folder"))
	ports.remove_rom_folder(second)
	check(not heard.is_empty(), "the chooser hears it")
	eq(_chosen(ports), [first], "removed")
	check(not ports.info("beta").rom.found, "game 2 missing once its folder is removed")
	check(ports.info("alpha").rom.found, "game 1 still found")
	eq(ports.info("beta").rom.path, first, "it names the folder left")
	ports.remove_rom_folder(_dir.path_join("never chosen"))
	eq(_chosen(ports), [first], "a folder never chosen changes nothing")
	_free(ports)
	ports = _make()
	eq(_chosen(ports), [first], "the removal is stored")
	ports.remove_rom_folder(first)
	eq(_chosen(ports), [], "none left")
	eq(ports.rom_folder_info().source, "fallback", "ROM-10 looks again (nothing to find here)")
	check(not ports.info("alpha").rom.found, "and the cards follow")
	check(not _state_text().contains("directory"), "nothing stored")
	_free(ports)
	remove(_dir)


func test_an_unmounted_folder_is_skipped_and_shown() -> void:
	_setup("folder_unmounted")
	var first := _put_rom("Games/A")
	var card := _put_beta_rom("card/n64")
	var ports := _make()
	ports.set_rom_folder(first)
	ports.set_rom_folder(card)
	check(ports.info("beta").rom.found, "the card's game")
	DirAccess.rename_absolute(_dir.path_join("card"), _dir.path_join("card-out"))
	ports.refresh()
	check(ports.info("alpha").rom.found, "the other folder still works (ROM-17)")
	check(not ports.info("beta").rom.found, "the card's game is missing")
	eq(ports.info("beta").rom.label, "No matching ROM", "not 'ROM folder not found'")
	eq(ports.info("beta").rom.path, "%s, %s (not found)" % [first, card], "where it looked")
	eq(_statuses(ports), [["ok", 1], ["missing", 0]], "the card is shown as missing")
	eq(_chosen(ports), [first, card], "and stays chosen")
	var cache: Dictionary = State.load_from(_dir.path_join("state/state.ini")).rom_cache()
	check(
		cache.keys().any(func(k: String) -> bool: return k.begins_with(card)),
		"the card's cache is kept for when it is back"
	)
	DirAccess.rename_absolute(_dir.path_join("card-out"), _dir.path_join("card"))
	ports.refresh()
	check(ports.info("beta").rom.found, "found again when it is back")
	DirAccess.rename_absolute(first, _dir.path_join("gone"))
	DirAccess.rename_absolute(_dir.path_join("card"), _dir.path_join("card-out"))
	ports.refresh()
	eq(ports.info("alpha").rom.label, "ROM folder not found", "none can be read (ROM-1)")
	_free(ports)
	remove(_dir)


func test_the_first_chosen_folder_wins() -> void:
	_setup("folder_first_wins")
	var first := _put_rom("Games/A")
	var second := _put_rom("Games/B")
	_put_beta_rom("Games/B")
	var ports := _make()
	ports.set_rom_folder(first)
	ports.set_rom_folder(second)
	eq(ports.info("alpha").rom.path, first.path_join("Alpha (USA).z64"), "the first folder's")
	eq(_statuses(ports), [["ok", 1], ["ok", 1]], "B serves beta only")
	ports.remove_rom_folder(first)
	eq(ports.info("alpha").rom.path, second.path_join("Alpha (USA).z64"), "then B's")
	_free(ports)
	remove(_dir)


## A found folder that serves a game stays when the first folder is chosen, so that game
## does not go back to ROM missing (ROM-10, ROM-17); a fallback that holds nothing does not.
func test_the_first_choice_keeps_the_found_folder() -> void:
	_setup("folder_keep_found")
	var emu := _put_rom("emu/roms/n64")
	_write("home/deck/.config/EmuDeck/settings.sh", "romsPath=%s\n" % emu.get_base_dir())
	var second := _put_beta_rom("Games/B")
	var ports := _make()
	eq(ports.rom_folder_info().source, "emudeck", "found")
	ports.set_rom_folder(second)
	eq(_chosen(ports), [emu, second], "the found folder first, then the choice")
	check(ports.info("alpha").rom.found and ports.info("beta").rom.found, "both games found")
	_free(ports)
	var first_dir := _dir
	_setup("folder_keep_fallback")
	second = _put_beta_rom("Games/B")
	ports = _make()
	eq(ports.rom_folder_info().source, "fallback", "nothing found")
	ports.set_rom_folder(second)
	eq(_chosen(ports), [second], "only the choice")
	_free(ports)
	remove(_dir)
	remove(first_dir)


func test_config_ini_lists_several_folders() -> void:
	_setup("folder_config_list")
	var first := _put_rom("Games/A")
	var second := _put_beta_rom("Games/B")
	var ports := _make("%s; ;%s;%s" % [first, _dir.path_join("gone"), second])
	var info: Dictionary = ports.rom_folder_info()
	eq([info.full, info.source, info.locked], [first, "config", true], "config.ini (CONF-8)")
	eq(
		info.folders.map(func(f: Dictionary) -> String: return f.full),
		[first, _dir.path_join("gone"), second],
		"in order, empty items skipped"
	)
	check(ports.info("alpha").rom.found and ports.info("beta").rom.found, "both found")
	eq(info.folders[1].status, "missing", "a missing one is skipped")
	ports.set_rom_folder(_dir.path_join("other"))
	eq(_chosen(ports), [], "the chooser cannot add to it")
	_free(ports)
	remove(_dir)


## ROM-12: the state.ini of 0.2.0 kept one folder; it loads as a list of one.
func test_an_old_state_ini_folder_is_kept() -> void:
	_setup("folder_old_state")
	var first := _put_rom("Games/A")
	var second := _put_beta_rom("Games/B")
	_write("state/state.ini", "[updates]\nlast_check = 0\n\n[roms]\ndirectory = %s\n" % first)
	var ports := _make()
	eq(_chosen(ports), [first], "the old folder")
	check(ports.info("alpha").rom.found, "and its game")
	ports.set_rom_folder(second)
	check(ports.info("alpha").rom.found and ports.info("beta").rom.found, "both after a choice")
	_free(ports)
	ports = _make()
	eq(_chosen(ports), [first, second], "both after a restart")
	_free(ports)
	remove(_dir)

extends "res://tests/case.gd"
## ROM-10, ROM-14, ROM-15, ROM-16 and the chooser's listings (ROM-11) over fake home and
## mount trees in temp folders.

const RomFolders := preload("res://src/rom_folders.gd")

var _dir := ""


func _setup(name: String) -> String:
	_dir = temp_dir(name)
	return _dir


## Makes the folder `rel` under the test folder, with `roms` ROM-like files and one other.
func _folder(rel: String, roms := 0) -> String:
	var path := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path)
	for i in roms:
		_write(path.path_join("Game %d.z64" % i), "x")
	if roms > 0:
		_write(path.path_join("readme.txt"), "not a ROM")
	return path


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _home() -> String:
	return _dir.path_join("home/deck")


func _media() -> String:
	return _dir.path_join("media")


func test_emudeck_settings_variants() -> void:
	var home := "/home/deck"
	var cases := [
		["romsPath=/home/deck/Emulation/roms", "/home/deck/Emulation/roms", "unquoted"],
		['romsPath="/run/media/mmcblk0p1/Emulation/roms"', "/run/media/mmcblk0p1/Emulation/roms"],
		["romsPath='$HOME/Games/roms'", "/home/deck/Games/roms", "single quotes, $HOME"],
		['romsPath="${HOME}/Games/roms"', "/home/deck/Games/roms", "${HOME}"],
		["romsPath=~/roms", "/home/deck/roms", "~"],
		["export romsPath=/x/roms", "/x/roms", "export"],
		["romsPath=/x/roms # moved to the card", "/x/roms", "trailing comment"],
		["emulationPath=/run/media/deck/SD/Emulation", "/run/media/deck/SD/Emulation/roms"],
		['romsPath=""\nemulationPath=$HOME/Emulation', "/home/deck/Emulation/roms", "empty"],
		["#romsPath=/nope\n# emulationPath=/nope", "", "comment lines only"],
		["romsPath=relative/roms", "", "a relative path is odd"],
		["romsPath=/first\nromsPath=/second", "/second", "the last line wins, as in bash"],
		["#!/usr/bin/env bash\nexpert=false\nromsPath=/r\nemulationPath=/e", "/r", "romsPath"],
		["", "", "empty file"],
	]
	for case in cases:
		var label: String = case[2] if case.size() > 2 else case[0]
		eq(RomFolders.parse_emudeck(case[0], home), case[1], "settings.sh: %s (ROM-15)" % label)


func test_emudeck_settings_file_locations() -> void:
	_setup("emudeck_files")
	var home := _home()
	eq(RomFolders.emudeck_folder(home), "", "no EmuDeck")
	_write(home.path_join("emudeck/settings.sh"), "romsPath=/old/roms\n")
	eq(RomFolders.emudeck_folder(home), "/old/roms/n64", "the older ~/emudeck/settings.sh")
	_write(home.path_join(".config/EmuDeck/settings.sh"), "emulationPath=$HOME/Emulation\n")
	eq(
		RomFolders.emudeck_folder(home),
		home.path_join("Emulation/roms/n64"),
		"~/.config/EmuDeck/settings.sh first, n64 subfolder"
	)
	_write(home.path_join(".config/EmuDeck/settings.sh"), "\u0001 garbage ===\n")
	eq(RomFolders.emudeck_folder(home), "", "an odd file is ignored, not the old one used")
	remove(_dir)


func test_retrodeck_json_cfg_and_broken() -> void:
	_setup("retrodeck")
	var home := _home()
	var conf := home.path_join(RomFolders.RETRODECK_CONFIG)
	eq(RomFolders.retrodeck_folder(home), "", "no RetroDECK")
	_write(conf.path_join("retrodeck.cfg"), "[paths]\nrdhome=/home/deck/retrodeck\nsdcard=/x\n")
	eq(RomFolders.retrodeck_folder(home), "/home/deck/retrodeck/roms/n64", "cfg rdhome + /roms")
	_write(conf.path_join("retrodeck.cfg"), '[paths]\nroms_folder = "/card/retrodeck/roms"\n')
	eq(RomFolders.retrodeck_folder(home), "/card/retrodeck/roms/n64", "cfg roms_folder, quoted")
	_write(conf.path_join("retrodeck.json"), "{ not json")
	eq(RomFolders.retrodeck_folder(home), "/card/retrodeck/roms/n64", "broken json: the cfg")
	_write(conf.path_join("retrodeck.json"), '{"paths": {"rd_home_path": "/rd"}}')
	eq(RomFolders.retrodeck_folder(home), "/rd/roms/n64", "json rd_home_path + /roms")
	var json := '{"version": "0.9", "paths": {"rd_home_path": "/rd", "roms_path": "%s"}}'
	_write(conf.path_join("retrodeck.json"), json % "/run/media/mmcblk0p1/retrodeck/roms")
	eq(
		RomFolders.retrodeck_folder(home),
		"/run/media/mmcblk0p1/retrodeck/roms/n64",
		"json roms_path wins (ROM-16)"
	)
	_write(conf.path_join("retrodeck.json"), '{"paths": {"roms_path": 5}}')
	eq(RomFolders.retrodeck_folder(home), "/card/retrodeck/roms/n64", "a json without paths")
	for text in ["[1, 2]", '{"paths": []}', "", "null"]:
		eq(RomFolders.parse_retrodeck_json(text, home), "", "odd json: " + text)
	eq(RomFolders.parse_retrodeck_cfg("rdhome=~/rd\n", home), home + "/rd/roms", "no section")
	eq(RomFolders.parse_retrodeck_cfg("# only a comment\n", home), "", "cfg without keys")
	remove(_dir)


func test_detection_order() -> void:
	_setup("detect_order")
	var home := _home()
	_folder("media/mmcblk0p1/Emulation/roms/n64", 1)
	_folder("media/deck/USB/n64", 1)
	eq(
		RomFolders.detect(home, _media(), ""),
		{"path": _media().path_join("mmcblk0p1/Emulation/roms/n64"), "source": "mount"},
		"step 3: a drive, the SD card first"
	)
	_folder("home/deck/Roms/n64", 2)
	eq(RomFolders.detect(home, _media(), "").source, "default", "step 2 before the drives")
	eq(RomFolders.detect(home, _media(), "").path, home.path_join("Roms/n64"), "~/Roms/n64")
	_folder("home/deck/retrodeck/roms/n64", 2)
	eq(RomFolders.detect(home, _media(), "").path, home.path_join("retrodeck/roms/n64"), "~/rd")
	_folder("home/deck/Emulation/roms/n64", 2)
	eq(RomFolders.detect(home, _media(), "").path, home.path_join("Emulation/roms/n64"), "~/Emu")
	var rd := _folder("rdcard/roms/n64", 1)
	_write(home.path_join(RomFolders.RETRODECK_CONFIG + "/retrodeck.json"), _rd_json(rd))
	eq(RomFolders.detect(home, _media(), ""), {"path": rd, "source": "retrodeck"}, "RetroDECK")
	var emu := _folder("emucard/Emulation/roms/n64", 1)
	var settings := "romsPath=%s\n" % emu.get_base_dir()
	_write(home.path_join(".config/EmuDeck/settings.sh"), settings)
	eq(RomFolders.detect(home, _media(), ""), {"path": emu, "source": "emudeck"}, "EmuDeck first")
	# A candidate without ROM-like files is passed over (ROM-10).
	for file in DirAccess.get_files_at(emu):
		DirAccess.remove_absolute(emu.path_join(file))
	_write(emu.path_join("notes.txt"), "x")
	eq(RomFolders.detect(home, _media(), "").source, "retrodeck", "an empty EmuDeck folder")
	remove(_dir)


func _rd_json(n64: String) -> String:
	return JSON.stringify({"paths": {"roms_path": n64.get_base_dir()}})


func test_nothing_found_and_the_fallback() -> void:
	_setup("detect_none")
	var home := _home()
	_folder("home/deck/Roms/n64")
	eq(RomFolders.detect(home, _media(), ""), {"path": "", "source": ""}, "empty folders only")
	eq(RomFolders.fallback(home), home.path_join("Roms/n64"), "no ~/Emulation: ~/Roms/n64")
	_folder("home/deck/Emulation")
	eq(RomFolders.fallback(home), home.path_join("Emulation/roms/n64"), "~/Emulation exists")
	remove(_dir)


func test_folder_names_match_case_insensitively() -> void:
	_setup("detect_case")
	var home := _home()
	var card := _folder("media/deck/CARD/ROMS/N64", 1)
	eq(RomFolders.detect(home, _media(), "").path, card, "ROMS/N64 on an exFAT card")
	var emu := _folder("home/deck/emulation/Roms/N64", 1)
	eq(RomFolders.detect(home, _media(), "").path, emu, "~/emulation/Roms/N64")
	eq(RomFolders.resolve_ci(home.path_join("EMULATION/roms/n64")), emu, "every part")
	eq(RomFolders.resolve_ci(home.path_join("Emulation/roms/gba")), "", "a part with no match")
	eq(RomFolders.resolve_ci("relative/path"), "", "relative")
	remove(_dir)


func test_rom_count_counts_rom_like_files_only() -> void:
	_setup("rom_count")
	var dir := _folder("n64")
	for name in ["a.z64", "b.N64", "c.V64", "d.ZIP", "e.txt", "f.sav", ".hidden.z64"]:
		_write(dir.path_join(name), "x")
	_folder("n64/sub", 3)
	eq(RomFolders.rom_count(dir), 4, "the four extensions, any case, files directly in it")
	eq(RomFolders.rom_count(_dir.path_join("missing")), 0, "missing folder")
	remove(_dir)


func test_mounts_in_both_styles_with_the_sd_card_first() -> void:
	_setup("mounts")
	var media := _media()
	_folder("media/sda1")
	_folder("media/mmcblk0p1")
	_folder("media/deck/My Card")
	_folder("media/deck/Backup")
	_folder("media/deck/.hidden")
	var mounts := (
		"\n"
		. join(
			[
				"/dev/nvme0n1p8 /home ext4 rw 0 0",
				"/dev/mmcblk0p1 %s/deck/My\\040Card exfat rw 0 0" % media,
				"/dev/sdb1 %s/deck/Backup vfat rw 0 0" % media,
				"/dev/sdc1 %s/deck/Gone vfat rw 0 0" % media,
			]
		)
	)
	var got := RomFolders.mounts(media, mounts)
	eq(
		got.map(func(m: Dictionary) -> String: return m.path.trim_prefix(media)),
		["/deck/My Card", "/mmcblk0p1", "/deck/Backup", "/sda1"],
		"/run/media/<dev> and /run/media/<user>/<label>; SD cards first, a gone mount left out"
	)
	eq(got[0].label, "SD card (My Card)", "a mmcblk device is the SD card whatever its name")
	eq(got[1].label, "SD card", "mmcblk0p1 by its path")
	eq(got[2].sd, false, "a USB drive")
	eq(got[3].label, "sda1", "label")
	eq(RomFolders.mounts(_dir.path_join("nothing"), ""), [], "no /run/media: no mounts")
	remove(_dir)


func test_read_mounts_reads_proc() -> void:
	var text := RomFolders.read_mounts(RomFolders.MOUNTS_FILE)
	check(text.contains(" / "), "/proc/self/mounts reads despite its zero size")
	eq(RomFolders.read_mounts("/nonexistent/mounts"), "", "unreadable: empty")


func test_search_depth_hidden_folders_and_order() -> void:
	_setup("search")
	var media := _media()
	_folder("media/deck/USB/n64", 1)
	_folder("media/mmcblk0p1/a/b/c/d", 2)
	_folder("media/mmcblk0p1/a/b/c/d/e", 5)
	_folder("media/mmcblk0p1/.Trash/n64", 5)
	_folder("media/mmcblk0p1/games", 3)
	_folder("media/mmcblk0p1/Emulation/roms/N64", 7)
	_folder("media/mmcblk0p1/Emulation/roms/snes", 9)
	_write(media.path_join("mmcblk0p1/root.zip"), "x")
	var result := RomFolders.search(RomFolders.mounts(media, ""))
	eq(result.status, "ok", "status")
	eq(
		result.results.map(func(r: Dictionary) -> String: return r.label + ":" + r.folder),
		[
			"SD card:Emulation/roms/N64",
			"SD card:",
			"SD card:games",
			"SD card:Emulation/roms/snes",
			"SD card:a/b/c/d",
			"USB:n64",
		],
		"SD card first, n64 folders first, then by depth; depth 5 and hidden left out (ROM-14)"
	)
	eq(result.results[0].roms, 7, "with its file count")
	eq(result.results[0].path, media.path_join("mmcblk0p1/Emulation/roms/N64"), "full path")
	eq(RomFolders.search(RomFolders.mounts(media, ""), 3).results.size(), 5, "depth is a limit")
	remove(_dir)


func test_search_without_a_card_and_stopping() -> void:
	_setup("search_none")
	eq(RomFolders.search(RomFolders.mounts(_media(), "")).status, "no_card", "no card")
	_folder("media/mmcblk0p1/n64", 1)
	var stopped := RomFolders.search(
		RomFolders.mounts(_media(), ""), 4, func() -> bool: return true
	)
	eq(stopped.status, "aborted", "stops when asked")
	remove(_dir)


func test_search_job_runs_on_a_thread() -> void:
	_setup("search_job")
	_folder("media/mmcblk0p1/Emulation/roms/n64", 2)
	var job := RomFolders.SearchJob.new()
	var got := []
	job.finished.connect(func(r: Dictionary) -> void: got.append(r))
	job.start(_media(), "/nonexistent/mounts")
	job.join()
	eq(got.size(), 1, "finished once")
	eq(got[0].results.size(), 1, "found the folder")
	var aborted := RomFolders.SearchJob.new()
	aborted.abort()
	aborted.start(_media(), "/nonexistent/mounts")
	aborted.join()
	eq(aborted.result.status, "aborted", "abort before it starts")
	remove(_dir)


func test_list_folder_for_the_chooser() -> void:
	_setup("list")
	var home := _home()
	_folder("home/deck/Emulation/roms/n64", 3)
	_folder("home/deck/Emulation/roms/gba")
	_folder("home/deck/Emulation/roms/.cache", 2)
	_folder("home/deck/Emulation/roms/Atari 2600")
	_folder("media/mmcblk0p1")
	var listing := RomFolders.list_folder(home.path_join("Emulation/roms"), home, _media(), "")
	eq(listing.ok, true, "ok")
	eq(
		listing.folders.map(func(f: Dictionary) -> String: return "%s %d" % [f.name, f.roms]),
		["Atari 2600 0", "gba 0", "n64 3"],
		"visible subfolders, ignoring case, with their ROM counts (ROM-11)"
	)
	eq(
		listing.places.map(func(p: Dictionary) -> String: return p.label),
		["Home", "SD card"],
		"home and the mounts are the starting points"
	)
	var gone := RomFolders.list_folder(home.path_join("Emulation/roms/n64/x/y"), home, _media(), "")
	eq(gone.path, home.path_join("Emulation/roms/n64"), "a gone folder lists its parent")
	eq(gone.roms, 3, "and its count")
	eq(RomFolders.list_folder("", home, _media(), "").path, home, "no path: home")
	remove(_dir)


func test_display_and_expand() -> void:
	eq(RomFolders.display("/home/deck/Emulation", "/home/deck"), "~/Emulation", "~")
	eq(RomFolders.display("/home/deck", "/home/deck"), "~", "home")
	eq(RomFolders.display("/home/decks/x", "/home/deck"), "/home/decks/x", "not a prefix")
	eq(RomFolders.expand("  '/a b/c'  ", "/h"), "/a b/c", "quotes keep spaces")
	eq(RomFolders.expand("/a//b/../c", "/h"), "/a/c", "simplified")

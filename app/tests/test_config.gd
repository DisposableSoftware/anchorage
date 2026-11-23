extends "res://tests/case.gd"
## CONF-1, CONF-3, CONF-4, CONF-5, KEY-2

const Config := preload("res://src/config.gd")


func test_reads_settings_and_keybindings_from_their_files() -> void:
	var dir := temp_dir("read")
	FileAccess.open(dir.path_join("config.ini"), FileAccess.WRITE).store_string(
		"[window]\nwidth=100\nheight=900\n[view]\ngreeting=Hi there\n"
	)
	FileAccess.open(dir.path_join("keybindings.ini"), FileAccess.WRITE).store_string(
		"[keybindings]\nquit=Ctrl+Q;Ctrl+Shift+Q\nback=\n"
	)
	var cfg := Config.load_from(dir)
	eq(cfg.width, 1280, "clamped up to 720p")
	eq(cfg.height, 900, "height")
	eq(cfg.greeting, "Hi there", "greeting")
	eq(cfg.keybindings["quit"], PackedStringArray(["Ctrl+Q", "Ctrl+Shift+Q"]), "quit")
	check(cfg.keybindings["back"].is_empty(), "empty value unbinds")
	remove(dir)


func test_creates_missing_files_with_the_defaults_commented_out() -> void:
	var dir := temp_dir("create").path_join("anchorage")
	var cfg := Config.load_from(dir)
	eq(cfg.width, 1280, "defaults when nothing is set")
	check(cfg.keybindings.is_empty(), "no overrides")
	var config := FileAccess.get_file_as_string(dir.path_join("config.ini"))
	var keys := FileAccess.get_file_as_string(dir.path_join("keybindings.ini"))
	check(config.contains("\n# width = 1280\n"), "width line commented out")
	check(keys.contains("\n# quit = Ctrl+Q\n"), "quit line commented out")
	for line in (config + "\n" + keys).split("\n"):
		check(
			line.is_empty() or line.begins_with("#") or line.begins_with("["),
			"not commented out: " + line
		)
	FileAccess.open(dir.path_join("config.ini"), FileAccess.WRITE).store_string(
		config.replace("# width = 1280", "width = 1600")
	)
	eq(Config.load_from(dir).width, 1600, "an uncommented line takes effect")
	remove(dir.get_base_dir())


func test_never_writes_to_existing_files_or_symlinks() -> void:
	var dir := temp_dir("keep")
	FileAccess.open(dir.path_join("config.ini"), FileAccess.WRITE).store_string(
		"[window]\nwidth=1500\n"
	)
	OS.execute("ln", ["-s", dir.path_join("elsewhere.ini"), dir.path_join("keybindings.ini")])
	var cfg := Config.load_from(dir)
	eq(cfg.width, 1500, "existing file is read")
	eq(
		FileAccess.get_file_as_string(dir.path_join("config.ini")),
		"[window]\nwidth=1500\n",
		"untouched"
	)
	check(
		not FileAccess.file_exists(dir.path_join("elsewhere.ini")),
		"dangling symlink target not created"
	)
	remove(dir)


func test_starts_with_defaults_when_the_files_cant_be_created() -> void:
	var blocker := temp_dir("blocked").path_join("file")
	FileAccess.open(blocker, FileAccess.WRITE).store_string("a file, not a folder")
	var cfg := Config.load_from(blocker.path_join("anchorage"))
	eq(cfg.width, 1280, "defaults")
	remove(blocker.get_base_dir())


func test_paths_follow_xdg() -> void:
	var home := OS.get_environment("XDG_CONFIG_HOME")
	if home.is_empty():
		return
	eq(Config.dir(), home.path_join("anchorage"), "config dir")
	var data := OS.get_environment("XDG_DATA_HOME")
	if not data.is_empty():
		eq(
			ProjectSettings.globalize_path("user://").trim_suffix("/"),
			data.path_join("anchorage"),
			"user:// is the XDG data dir"
		)

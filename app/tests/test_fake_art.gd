extends "res://tests/case.gd"
## ART-8: ANCHORAGE_FAKE_ART_DIR gives the fake ports real cover art for screenshots.

const PortsFake := preload("res://src/ports_fake.gd")


func _png(dir: String, id: String, width: int, height: int) -> void:
	Image.create(width, height, false, Image.FORMAT_RGB8).save_png(dir.path_join(id + ".png"))


func _art_of(scenario: String, dir: String) -> Dictionary:
	OS.set_environment(PortsFake.ART_DIR_ENV, dir)
	var ports := PortsFake.new(scenario)
	OS.unset_environment(PortsFake.ART_DIR_ENV)
	var sizes := {}
	for id: String in ports.list():
		var texture: Texture2D = ports.info(id).art
		sizes[id] = texture.get_size() if texture != null else null
	ports.free()
	return sizes


func test_a_folder_gives_each_port_its_image() -> void:
	var dir := temp_dir("fake_art")
	_png(dir, "soh", 64, 30)
	_png(dir, "ghostship", 80, 40)
	_png(dir, "lighthouse", 920, 430)
	var sizes := _art_of("showcase", dir)
	eq(sizes.soh, Vector2(64, 30), "the file replaces the placeholder")
	eq(sizes.ghostship, Vector2(80, 40), "a port that has a monogram gets its file")
	eq(sizes.lighthouse, Vector2(920, 430), "the last port too")
	eq(sizes["2ship"], Vector2(PortsFake.ART_SIZE), "no file: the placeholder stays")
	eq(sizes.starship, null, "no file and no placeholder: the monogram")
	remove(dir)


func test_an_unusable_file_is_ignored() -> void:
	var dir := temp_dir("fake_art_bad")
	var file := FileAccess.open(dir.path_join("starship.png"), FileAccess.WRITE)
	file.store_string("not an image")
	file.close()
	_png(dir, "paperboat", 5000, 10)
	var sizes := _art_of("showcase", dir)
	eq(sizes.starship, null, "a file that is not an image shows the monogram (ART-4)")
	eq(sizes.paperboat, null, "an image over 4096 px too")
	remove(dir)


func test_without_the_variable_or_with_an_empty_folder_nothing_changes() -> void:
	var dir := temp_dir("fake_art_none")
	for folder in ["", dir, dir.path_join("missing")]:
		var sizes := _art_of("showcase", folder)
		eq(sizes.soh, Vector2(PortsFake.ART_SIZE), "the placeholder (%s)" % folder)
		eq(sizes.lighthouse, null, "the monogram (%s)" % folder)
	remove(dir)


func test_only_the_fake_reads_the_variable() -> void:
	var users := []
	for path in ["res://src", "res://tests"]:
		for name in DirAccess.get_files_at(path):
			var text := FileAccess.get_file_as_string(path.path_join(name))
			if name.ends_with(".gd") and text.contains("ANCHORAGE_FAKE_ART_DIR"):
				users.append(path.path_join(name))
	users.sort()
	eq(
		users,
		["res://src/ports_fake.gd", "res://tests/test_fake_art.gd"],
		"no other script mentions ANCHORAGE_FAKE_ART_DIR",
	)

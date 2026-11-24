extends "res://tests/case.gd"
## PORT-9, PORT-10: Installer.copy_extra_files, which install and launch use to put the
## catalog's extra files and folders into a port's data folder.

const Installer := preload("res://src/installer.gd")

var _dir := ""


func _setup(name: String) -> void:
	_dir = temp_dir(name)


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_copy_extra_files_only_missing_keeps_what_is_there() -> void:
	_setup("inst_missing")
	var from := _dir.path_join("from")
	DirAccess.make_dir_recursive_absolute(from.path_join("assets/x"))
	for path in ["config.yml", "assets/x/y.yaml"]:
		var file := FileAccess.open(from.path_join(path), FileAccess.WRITE)
		file.store_string("new")
		file.close()
	var data := _dir.path_join("data")
	DirAccess.make_dir_recursive_absolute(data)
	var mine := FileAccess.open(data.path_join("config.yml"), FileAccess.WRITE)
	mine.store_string("mine")
	mine.close()
	var port := {"extra_files": ["config.yml", "assets"]}
	eq(Installer.copy_extra_files(port, from, data, true), "", "no error")
	eq(_text(data.path_join("config.yml")), "mine", "present file kept")
	eq(_text(data.path_join("assets/x/y.yaml")), "new", "missing folder copied")
	remove(_dir)


## A copy that fails part-way leaves the old copy whole, never a half folder under the real
## name, which `only_missing` would then keep for good (PORT-9, PORT-10).
func test_a_failed_extra_copy_keeps_the_old_copy_whole() -> void:
	_setup("inst_half")
	var from := _dir.path_join("from")
	DirAccess.make_dir_recursive_absolute(from.path_join("assets"))
	for name in ["a.yaml", "b.yaml"]:
		var file := FileAccess.open(from.path_join("assets").path_join(name), FileAccess.WRITE)
		file.store_string("new")
		file.close()
	FileAccess.set_unix_permissions(from.path_join("assets/b.yaml"), 0)
	var data := _dir.path_join("data")
	DirAccess.make_dir_recursive_absolute(data.path_join("assets"))
	var old := FileAccess.open(data.path_join("assets/old.yaml"), FileAccess.WRITE)
	old.store_string("old")
	old.close()
	var port := {"extra_files": ["assets"]}
	var error := Installer.copy_extra_files(port, from, data)
	FileAccess.set_unix_permissions(from.path_join("assets/b.yaml"), 420)
	check(not error.is_empty(), "the copy fails")
	eq(_text(data.path_join("assets/old.yaml")), "old", "the old copy is untouched")
	check(not FileAccess.file_exists(data.path_join("assets/a.yaml")), "no half copy in its place")
	eq(Array(DirAccess.get_directories_at(data)), ["assets"], "no temp folder left behind")
	eq(Installer.copy_extra_files(port, from, data), "", "a later copy works")
	eq(_text(data.path_join("assets/b.yaml")), "new", "and replaces it")
	remove(_dir)


## An extra file in data/ that is a symbolic link is replaced, never written through.
func test_extra_files_replace_a_link_instead_of_writing_through_it() -> void:
	_setup("inst_extra_link")
	var from := _dir.path_join("from")
	DirAccess.make_dir_recursive_absolute(from)
	var file := FileAccess.open(from.path_join("gamecontrollerdb.txt"), FileAccess.WRITE)
	file.store_string("db")
	file.close()
	var outside := _dir.path_join("outside.txt")
	file = FileAccess.open(outside, FileAccess.WRITE)
	file.store_string("keep me")
	file.close()
	var data := _dir.path_join("data")
	DirAccess.make_dir_recursive_absolute(data)
	OS.execute("ln", ["-s", outside, data.path_join("gamecontrollerdb.txt")])
	eq(Installer.copy_extra_files({"extra_files": ["gamecontrollerdb.txt"]}, from, data), "", "ok")
	eq(_text(outside), "keep me", "the link's target is not written")
	eq(_text(data.path_join("gamecontrollerdb.txt")), "db", "the new copy is in place")
	check(not DirAccess.open(data).is_link(data.path_join("gamecontrollerdb.txt")), "not a link")
	remove(_dir)

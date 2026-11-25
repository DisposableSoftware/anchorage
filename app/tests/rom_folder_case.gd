extends "res://tests/case.gd"
## Shared by test_rom_folder and test_rom_folder_list: a temp tree with a fake home and
## mounts, two ports (alpha and beta, each with its own ROM) and a real `Ports` over them.

const Ports := preload("res://src/ports.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const State := preload("res://src/state.gd")
const Roms := preload("res://src/roms.gd")

var _dir := ""
var _rom := PackedByteArray()
## Beta's ROM: another game, so a folder can hold one port's ROM and not the other's.
var _beta_rom := PackedByteArray()


func _setup(name: String) -> void:
	_dir = temp_dir(name)
	_rom = PackedByteArray([0x80, 0x37, 0x12, 0x40])
	_beta_rom = _rom.duplicate()
	for i in 60:
		_rom.append(i)
		_beta_rom.append(200 - i)


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
		},
		{
			"id": "beta",
			"name": "Beta",
			"game": "Game beta",
			"description": "About beta",
			"repo": "test/beta",
			"asset_suffix": "-linux.zip",
			"archive": ["beta.o2r"],
			"launch": {"executable": "beta.appimage", "cwd": "data", "args": []},
			"extra_files": [],
			"rom_place": "data_dir",
			"rom_file": "beta.z64",
			"roms": [{"label": "US", "sha1": Roms.sha1_of(_beta_rom)}],
		},
	]


## Writes the matching ROM into `rel` (under the test folder) and returns the folder.
func _put_rom(rel: String) -> String:
	var dir := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("Alpha (USA).z64"), FileAccess.WRITE)
	file.store_buffer(_rom)
	file.close()
	return dir


## Writes beta's ROM into `rel` and returns the folder.
func _put_beta_rom(rel: String) -> String:
	var dir := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("Beta (USA).z64"), FileAccess.WRITE)
	file.store_buffer(_beta_rom)
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


## Waits frame by frame until `until` holds; a failure after `seconds`.
func _frames(until: Callable, seconds := 10.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not until.call():
		if Time.get_ticks_msec() > deadline:
			check(false, "timed out after %.0f s waiting" % seconds)
			return
		await (Engine.get_main_loop() as SceneTree).process_frame


func _chosen(ports: Node) -> Array:
	return ports.rom_folder_info().chosen


func _statuses(ports: Node) -> Array:
	return ports.rom_folder_info().folders.map(
		func(f: Dictionary) -> Array: return [f.status, f.ports]
	)

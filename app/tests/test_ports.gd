extends "res://tests/case.gd"
## The real Ports service (PORT-5, PORT-6, PORT-8, PORT-9, PORT-12, PORT-14, ROM-4, ROM-5,
## ROM-9, CONF-8, CONF-9) over a test catalog, fake HTTP answers, temp folders and fake
## ports (shell scripts) that really run.

const Ports := preload("res://src/ports.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const Releases := preload("res://src/releases.gd")
const Installer := preload("res://src/installer.gd")
const State := preload("res://src/state.gd")
const Roms := preload("res://src/roms.gd")
const NOW := 1_800_000_000
## Engine classes and singletons that reach the network, the disk, processes or threads, or
## that could reach them by name.
const FORBIDDEN := [
	"HTTPRequest",
	"HTTPClient",
	"StreamPeer\\w*",
	"TCPServer",
	"PacketPeer\\w*",
	"FileAccess",
	"DirAccess",
	"ZIPReader",
	"ZIPPacker",
	"OS",
	"Thread",
	"WorkerThreadPool",
	"Mutex",
	"Semaphore",
	"ClassDB",
	"Expression",
	"ResourceLoader",
	"ResourceSaver",
	"ProjectSettings",
]
## What a screen may load: scenes, other screens and the pure helpers.
const LOADABLE := (
	"^res://(scenes/[a-z_]+\\.tscn|src/ui/[a-z_]+\\.gd" + "|src/(keys|theme|palette)\\.gd)$"
)


## Holds downloads until `release_one`, so a test can look while one runs.
class HeldHttp:
	extends "res://tests/fake_http.gd"

	var held: Array = []

	func download(
		url: String, dest: String, progress: Callable, done: Callable, expected := 0
	) -> void:
		held.append([url, dest, progress, done, expected])

	func release_one() -> void:
		var args: Array = held.pop_front()
		super.download(args[0], args[1], args[2], args[3], args[4])

	func cancel_download() -> void:
		if held.is_empty():
			return
		var args: Array = held.pop_front()
		args[3].call({"ok": false, "status": 0, "error": "Cancelled", "cancelled": true})


var _dir := ""
var _http: RefCounted
var _rom := PackedByteArray()


func _setup(name: String, http: RefCounted = null) -> void:
	_dir = temp_dir(name)
	_http = http if http != null else FakeHttp.new()
	_rom = PackedByteArray([0x80, 0x37, 0x12, 0x40])
	for i in 60:
		_rom.append(i)


func _catalog() -> Array:
	var out := []
	for id in ["alpha", "beta"]:
		var first := Roms.sha1_of(_rom) if id == "alpha" else "0".repeat(40)
		(
			out
			. append(
				{
					"id": id,
					"name": id.capitalize(),
					"game": "Game " + id,
					"description": "About " + id,
					"repo": "test/" + id,
					"asset_suffix": "-linux.zip",
					"archive": [id + ".o2r"],
					"launch": {"executable": id + ".appimage", "cwd": "data", "args": []},
					"extra_files": [],
					"rom_place": "data_dir",
					"rom_file": id + ".z64",
					"roms":
					[
						{"label": "US", "sha1": first},
						{"label": "US", "sha1": "1".repeat(40)},
						{"label": "EU", "sha1": "2".repeat(40)},
					],
				}
			)
		)
	return out


## Publishes `tag` of port `id` on the fake GitHub, with a fake port that sleeps `sleep`
## seconds, creates its archive when its ROM was placed, prints "boom" and exits `code`.
func _publish(id: String, tag: String, sleep := 0.0, code := 0) -> String:
	var script := (
		'#!/bin/sh\n[ -f %s.z64 ] && : > "$SHIP_HOME/%s.o2r"\nsleep %s\necho boom\nexit %d\n'
		% [id, id, str(sleep), code]
	)
	var zip_path := _dir.path_join("%s-%s.zip" % [id, tag])
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file(id + ".appimage")
	packer.write_file(script.to_utf8_buffer())
	packer.close_file()
	packer.close()
	var url := "https://github.com/test/%s/releases/download/%s/%s-Linux.zip" % [id, tag, id]
	_http.files[url] = zip_path
	var size := FileAccess.get_file_as_bytes(zip_path).size()
	_http.json[Releases.API % ("test/" + id)] = {
		"tag_name": tag,
		"assets": [{"name": id + "-Linux.zip", "browser_download_url": url, "size": size}],
	}
	return url


func _roms_dir() -> String:
	return _dir.path_join("roms")


func _put_rom() -> void:
	DirAccess.make_dir_recursive_absolute(_roms_dir())
	var file := FileAccess.open(_roms_dir().path_join("Alpha (USA).z64"), FileAccess.WRITE)
	file.store_buffer(_rom)
	file.close()


func _make(check_updates := false, threaded := false, settle := 10.0) -> Node:
	var ports: Node = Ports.new()
	ports.root = _dir.path_join("ports")
	ports.state_path = _dir.path_join("state/state.ini")
	ports.roms_dir = _roms_dir()
	ports.check_updates = check_updates
	ports.catalog = _catalog()
	ports.http = _http
	ports.threaded = threaded
	ports.clock = func() -> int: return NOW
	ports.settle_seconds = settle
	(Engine.get_main_loop() as SceneTree).root.add_child(ports)
	return ports


func _free(ports: Node) -> void:
	ports.get_parent().remove_child(ports)
	ports.free()
	remove(_dir)


## Polls until the port is no longer running (at most 5 s).
func _wait_exit(ports: Node, id: String) -> void:
	for _i in 100:
		ports.poll()
		if not ports.info(id).running:
			return
		OS.delay_msec(50)
	check(false, "%s still running after 5 s" % id)


func _api_requests() -> Array:
	return _http.requests.filter(func(u: String) -> bool: return u.begins_with("https://api."))


func test_info_has_the_contract_keys_in_catalog_order() -> void:
	_setup("ports_contract")
	var ports := _make()
	eq(ports.list(), ["alpha", "beta"], "catalog order")
	var fake := PortsFake.new()
	var expected := fake.info("soh").keys()
	expected.sort()
	var got: Array = ports.info("alpha").keys()
	got.sort()
	eq(got, expected, "the same keys as ports_fake (PORT-14)")
	eq(ports.info("alpha").rom.keys(), fake.info("soh").rom.keys(), "rom keys")
	eq(ports.info("alpha").busy.keys(), fake.info("soh").busy.keys(), "busy keys")
	fake.free()
	_free(ports)


func test_ports_has_every_method_and_signal_the_screens_use() -> void:
	var ports: Node = Ports.new()
	for method in (
		["list", "info", "install", "update", "remove", "launch", "cancel", "refresh"]
		+ ["dismiss_error"]
	):
		check(ports.has_method(method), method)
	for sig in ["changed", "launched", "exited"]:
		check(ports.has_signal(sig), sig)
	ports.free()


## What in `source` breaks PORT-14. Comments are skipped, names are whole words whatever the
## spacing, and every load must be of a screen file or a pure helper.
static func _forbidden(source: String) -> Array:
	var found := []
	var code := RegEx.create_from_string("#[^\\n]*").sub(source, "", true)
	var words := RegEx.create_from_string("\\b(%s)\\b" % "|".join(FORBIDDEN))
	for m in words.search_all(code):
		found.append(m.get_string(1))
	if code.contains("user://"):
		found.append("user://")
	var loads := RegEx.create_from_string("\\b(?:pre)?load\\s*\\(\\s*([^)]*)\\)")
	for m in loads.search_all(code):
		var arg := m.get_string(1).strip_edges()
		var path := arg.substr(1, arg.length() - 2) if arg.begins_with('"') else arg
		if not (arg.begins_with('"') and RegEx.create_from_string(LOADABLE).search(path)):
			found.append("load(%s)" % arg)
	return found


func test_screens_never_touch_the_network_the_disk_or_processes() -> void:
	for file in DirAccess.get_files_at("res://src/ui"):
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://src/ui/" + file)
		eq(_forbidden(text), [], "%s (PORT-14)" % file)
	# Ways around a plain substring search, which the old check let through.
	for sample in [
		"var dir = DirAccess .open(path)",
		"OS\n\t.execute('rm', [])",
		'const I := preload("res://src/installer.gd")',
		'var h = load("res://src/http.gd").new()',
		"var name := 'res://src/' + 'roms.gd'\nload(name)",
		'ClassDB.instantiate("HTTP" + "Request")',
		"var t := Thread.new()",
		'var p := "user://ports"',
	]:
		check(not _forbidden(sample).is_empty(), "caught: %s" % sample)
	eq(_forbidden("# OS.execute in a comment\nvar x := 1"), [], "comments do not count")
	eq(_forbidden('const K := preload("res://src/keys.gd")'), [], "pure helpers may be loaded")


func test_the_start_check_obeys_check_updates_and_the_hour() -> void:
	_setup("ports_check")
	_publish("alpha", "1.0")
	var ports := _make(false)
	eq(_api_requests().size(), 0, "check_updates = false: no check at start (CONF-9)")
	ports.refresh()
	eq(_api_requests().size(), 2, "refresh always checks, every port (PORT-5)")
	eq(ports.info("alpha").latest_version, "1.0", "latest tag from GitHub")
	check(ports.info("beta").offline == false, "a port without a release is not offline")
	ports.get_parent().remove_child(ports)
	ports.free()
	_http.requests.clear()
	ports = _make(true)
	eq(_api_requests().size(), 0, "checked a moment ago: not again at start")
	eq(ports.info("alpha").latest_version, "1.0", "the last known tag is remembered")
	ports.get_parent().remove_child(ports)
	ports.free()
	var state := State.load_from(_dir.path_join("state/state.ini"))
	state.set_last_check(NOW - 3601)
	ports = _make(true)
	eq(_api_requests().size(), 2, "an hour later the start checks (PORT-5)")
	_free(ports)


func test_offline_keeps_the_last_known_state_without_an_error() -> void:
	_setup("ports_offline")
	_publish("alpha", "1.0")
	var ports := _make()
	ports.refresh()
	_http.offline = true
	ports.refresh()
	var info: Dictionary = ports.info("alpha")
	check(info.offline, "offline after a failed check (PORT-2)")
	eq(info.latest_version, "1.0", "last known version kept")
	eq(info.error, "", "not an error")
	ports.install("alpha")
	info = ports.info("alpha")
	eq(
		info.error,
		"Could not install “Alpha”\nGitHub could not be reached: Could not connect",
		"an install that can't reach GitHub says so"
	)
	eq(info.busy.action, "", "and is not left busy")
	_free(ports)


func test_install_fetches_the_latest_release_then_rescans() -> void:
	_setup("ports_install")
	var url := _publish("alpha", "2.0")
	var ports := _make()
	eq(ports.info("alpha").rom.found, false, "no ROM yet")
	_put_rom()
	var seen := []
	ports.changed.connect(
		func(id: String) -> void:
			if id == "alpha":
				seen.append(ports.info("alpha").busy.duplicate())
	)
	ports.install("alpha")
	var info: Dictionary = ports.info("alpha")
	check(info.installed, "installed")
	eq(info.installed_version, "2.0", "the release tag")
	eq(info.busy.action, "", "idle again")
	eq(info.error, "", "no error")
	check(not info.update_available, "up to date")
	eq(_http.requests.slice(-2), [Releases.API % "test/alpha", url], "release looked up first")
	check(info.rom.found, "ROM folder rescanned after the install (ROM-5)")
	eq(info.rom.label, "Alpha (USA).z64", "the matched file")
	var details := seen.map(func(b: Dictionary) -> String: return b.detail)
	check("Looking for the release" in details, "busy while looking: %s" % str(details))
	check(
		seen.any(
			func(b: Dictionary) -> bool: return b.progress > 0.0 and b.detail.contains(" of ")
		),
		"download progress in bytes"
	)
	check("Unpacking" in details, "unpack stage shown")
	var exe := _dir.path_join("ports/alpha/current/alpha.appimage")
	check(FileAccess.get_unix_permissions(exe) & 73 != 0, "executable")
	_free(ports)


func test_failures_become_could_not_messages() -> void:
	_setup("ports_fail")
	var url := _publish("alpha", "2.0")
	_http.status[url] = 500
	var ports := _make()
	ports.install("alpha")
	var info: Dictionary = ports.info("alpha")
	eq(info.error, "Could not install “Alpha”\nHTTP 500", "verb, name and detail")
	check(not info.installed, "nothing installed")
	ports.dismiss_error("alpha")
	eq(ports.info("alpha").error, "", "dismissed")
	ports.install("beta")
	check(
		ports.info("beta").error.begins_with("Could not install “Beta”\nNo release found"),
		"a port without a release"
	)
	_free(ports)


func test_update_keeps_previous_until_the_new_version_ran_a_while() -> void:
	_setup("ports_update")
	_publish("alpha", "1.0", 0.6)
	var ports := _make(false, false, 0.3)
	ports.install("alpha")
	_publish("alpha", "2.0", 0.6)
	ports.refresh()
	check(ports.info("alpha").update_available, "update available (PORT-5)")
	ports.update("alpha")
	var previous := _dir.path_join("ports/alpha/previous")
	eq(ports.info("alpha").installed_version, "2.0", "updated")
	check(DirAccess.dir_exists_absolute(previous), "old version kept as previous/")
	ports.launch("alpha")
	check(ports.info("alpha").running, "running")
	ports.poll()
	check(DirAccess.dir_exists_absolute(previous), "kept right after the launch")
	OS.delay_msec(400)
	ports.poll()
	check(not DirAccess.dir_exists_absolute(previous), "deleted once it ran past the settle time")
	_wait_exit(ports, "alpha")
	ports.update("alpha")
	eq(_http.requests[-1], Releases.API % "test/alpha", "same tag: only looked up")
	eq(ports.info("alpha").busy.action, "", "and idle")
	_free(ports)


func test_launch_places_the_rom_runs_and_comes_back() -> void:
	_setup("ports_launch")
	_put_rom()
	_publish("alpha", "1.0", 0.3)
	var ports := _make()
	ports.install("alpha")
	var events := []
	ports.launched.connect(func(id: String) -> void: events.append("launched " + id))
	ports.exited.connect(func(id: String) -> void: events.append("exited " + id))
	ports.launch("alpha")
	var data := _dir.path_join("ports/alpha/data")
	check(FileAccess.file_exists(data.path_join("alpha.z64")), "ROM placed before the start")
	check(ports.info("alpha").running, "running (HOME-10)")
	ports.launch("alpha")
	ports.remove("alpha")
	ports.update("alpha")
	check(ports.info("alpha").installed, "not removed while it runs (PORT-12)")
	_wait_exit(ports, "alpha")
	eq(events, ["launched alpha", "exited alpha"], "one launch, one exit")
	eq(ports.info("alpha").error, "", "a clean exit is no error")
	check(FileAccess.file_exists(data.path_join("alpha.o2r")), "the fake port extracted")
	check(not FileAccess.file_exists(data.path_join("alpha.z64")), "placed ROM deleted (PORT-9)")
	_free(ports)


func test_a_port_that_fails_at_once_shows_why() -> void:
	_setup("ports_crash")
	_publish("alpha", "1.0", 0.0, 127)
	var ports := _make()
	ports.install("alpha")
	ports.launch("alpha")
	_wait_exit(ports, "alpha")
	eq(
		ports.info("alpha").error,
		"Could not start “Alpha”\nIt stopped after 1 s with exit code 127. boom",
		"exit code and the last line of the log (PORT-8)"
	)
	_free(ports)


func test_one_download_at_a_time_and_a_waiting_one_can_be_cancelled() -> void:
	_setup("ports_queue", HeldHttp.new())
	_publish("alpha", "1.0")
	_publish("beta", "1.0")
	var ports := _make()
	ports.install("alpha")
	eq(ports.info("alpha").busy.action, "install", "alpha downloading")
	eq(_http.held.size(), 1, "one download")
	ports.install("alpha")
	ports.launch("alpha")
	eq(_http.held.size(), 1, "the same port is not started twice (PORT-12)")
	ports.install("beta")
	eq(ports.info("beta").busy.detail, "Waiting for Alpha", "beta waits")
	eq(_http.held.size(), 1, "still one download overall")
	ports.cancel("beta")
	eq(ports.info("beta").busy.action, "", "a waiting install is cancelled")
	ports.install("beta")
	_http.release_one()
	check(ports.info("alpha").installed, "alpha done")
	eq(_http.held.size(), 1, "beta's download starts next")
	eq(ports.info("beta").busy.action, "install", "beta busy")
	ports.cancel("beta")
	eq(ports.info("beta").busy.action, "", "cancel stops the running download")
	eq(ports.info("beta").error, "", "cancel is no error")
	check(not ports.info("beta").installed, "nothing installed")
	_free(ports)


func test_leftover_downloads_are_deleted_at_start() -> void:
	_setup("ports_stale")
	var stale := _dir.path_join("ports/alpha/download/staging")
	DirAccess.make_dir_recursive_absolute(stale)
	var ports := _make()
	check(not DirAccess.dir_exists_absolute(stale.get_base_dir()), "download/ gone (PORT-12)")
	_free(ports)


func test_remove_keeps_data_and_forgets_the_version() -> void:
	_setup("ports_remove")
	_publish("alpha", "1.0")
	var ports := _make()
	ports.install("alpha")
	var data := _dir.path_join("ports/alpha/data")
	DirAccess.make_dir_recursive_absolute(data)
	FileAccess.open(data.path_join("save.sav"), FileAccess.WRITE).close()
	ports.remove("alpha")
	check(not ports.info("alpha").installed, "removed")
	eq(State.load_from(_dir.path_join("state/state.ini")).installed_version("alpha"), "", "state")
	check(FileAccess.file_exists(data.path_join("save.sav")), "data kept")
	_free(ports)


## HOME-13: deleting a port runs on the worker pool; meanwhile it shows as removing.
func test_remove_runs_off_the_main_thread() -> void:
	_setup("ports_remove_async")
	_publish("alpha", "1.0")
	var ports := _make(false, true)
	var tree := Engine.get_main_loop() as SceneTree
	ports.install("alpha")
	for _i in 200:
		if ports.info("alpha").installed and ports.info("alpha").busy.action == "":
			break
		await tree.process_frame
	check(ports.info("alpha").installed, "installed")
	ports.remove("alpha")
	eq(ports.info("alpha").busy.action, "remove", "busy removing while the worker deletes")
	for _i in 200:
		if ports.info("alpha").busy.action == "":
			break
		await tree.process_frame
	check(not ports.info("alpha").installed, "removed")
	eq(ports.info("alpha").error, "", "no error")
	_free(ports)


func test_rom_status_names_what_is_wanted_and_where_it_looked() -> void:
	_setup("ports_rom")
	var ports := _make()
	var rom: Dictionary = ports.info("alpha").rom
	check(not rom.found, "no folder, no ROM")
	eq(rom.label, "ROM folder not found", "missing folder is a state (ROM-1)")
	eq(rom.path, _roms_dir(), "the folder from the config (CONF-8)")
	eq(rom.wanted, ["US", "EU"], "each version named once (ROM-9)")
	DirAccess.make_dir_recursive_absolute(_roms_dir())
	ports.refresh()
	eq(ports.info("alpha").rom.label, "No matching ROM", "folder there, nothing matches")
	var data := _dir.path_join("ports/alpha/data")
	DirAccess.make_dir_recursive_absolute(data)
	FileAccess.open(data.path_join("alpha.o2r"), FileAccess.WRITE).close()
	check(ports.info("alpha").rom.found, "an extracted port needs no ROM (ROM-9)")
	_free(ports)


func test_the_scan_runs_on_a_thread_and_its_cache_is_saved() -> void:
	_setup("ports_scan")
	_put_rom()
	var ports := _make(false, true)
	eq(ports.info("alpha").rom.label, "Looking for ROMs", "the UI does not wait (ROM-4)")
	check(ports._scan_job != null, "a ScanJob runs")
	ports._scan_job.join()
	check(ports.info("alpha").rom.found, "found once the job finished")
	var cache: Dictionary = State.load_from(_dir.path_join("state/state.ini")).rom_cache()
	eq(cache.size(), 1, "the scan cache is in state.ini (ROM-4)")
	check(cache.keys()[0].begins_with(_roms_dir()), "keyed by path")
	ports.refresh()
	ports.refresh()
	ports._scan_job.join()
	check(ports._scan_job != null, "a refresh during a scan runs one more after it")
	ports._scan_job.join()
	check(ports._scan_job == null, "and only one")
	ports.roms_dir = _dir.path_join("unmounted")
	ports.refresh()
	ports._scan_job.join()
	eq(ports.info("alpha").rom.label, "ROM folder not found", "an unmounted card")
	cache = State.load_from(_dir.path_join("state/state.ini")).rom_cache()
	eq(cache.size(), 1, "keeps the cache for when it is back")
	_free(ports)


## A worker task that ends without a result (a script error inside it) must still hand
## `finished` something, or the port stays busy forever.
func test_a_worker_task_without_a_result_still_finishes() -> void:
	_setup("ports_offload")
	var ports := _make(false, true)
	var got := []
	ports._offload(
		func() -> Variant: return null,
		func(r: Dictionary) -> void: got.append(r),
		{"ok": false, "error": "fallback"}
	)
	for _i in 100:
		if not got.is_empty():
			break
		await (Engine.get_main_loop() as SceneTree).process_frame
	eq(got, [{"ok": false, "error": "fallback"}], "the fallback result arrives")
	_free(ports)

extends "res://tests/case.gd"
## UPD-1 .. UPD-10: self_update.gd with fake HTTP and temp files (a fake AppImage: the
## ELF and AppImage magic, then a shell script that SMOKE runs), and the home screen's
## chip, app menu entry and dialog over ports_fake.gd.

const SelfUpdate := preload("res://src/self_update.gd")
const SelfUpdateFake := preload("res://src/self_update_fake.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const Launcher := preload("res://src/launcher.gd")

const OWN := "0.2.0"
const NEXT := "0.3.0"
const NAME := "Anchorage-0.3.0-x86_64.AppImage"
const URL := "https://github.com/DisposableSoftware/anchorage/releases/download/v0.3.0/"
## Runs the fake AppImage's script (what follows its 12-byte header) with its arguments.
## The file itself is never executed: NixOS hands files with the AppImage magic to
## appimage-run.
const SMOKE := ["/bin/sh", "-c", 'tail -c +13 "$0" | /bin/sh -s -- "$@"']
const NOTES := "EVIL RELEASE NOTES <b>bold</b>"

var _dir := ""
var _http: RefCounted
var _nodes: Array[Node] = []


func _setup(name: String) -> String:
	_dir = temp_dir("self-update-" + name)
	_http = FakeHttp.new()
	DirAccess.make_dir_recursive_absolute(_dir.path_join("Applications"))
	var path := _dir.path_join("Applications/Anchorage.AppImage")
	_appimage(path, "echo old; exit 0")
	return path


func _finish() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	remove(_dir)


## A file with the ELF and AppImage type 2 magic, then `script`.
static func _appimage(path: String, script: String, elf := true, magic := true) -> void:
	var data := PackedByteArray([0x7F, 0x45, 0x4C, 0x46] if elf else [0x23, 0x21, 0x2F, 0x2F])
	data.append_array("abcd".to_utf8_buffer())
	data.append_array(PackedByteArray([0x41, 0x49, 0x02] if magic else [0x41, 0x49, 0x01]))
	data.append_array(("\n%s\n" % script).to_utf8_buffer())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
	FileAccess.set_unix_permissions(path, 0x1ED)


## Serves release v`version` with `file` as its AppImage. `changes` replace fields of the
## AppImage asset; `sums` replaces SHA256SUMS.
func _serve(version: String, file: String, changes := {}, sums: Variant = null) -> Dictionary:
	var name := "Anchorage-%s-x86_64.AppImage" % version
	var base := "https://github.com/DisposableSoftware/anchorage/releases/download/v%s/" % version
	var sha := FileAccess.get_sha256(file)
	var asset := {
		"name": name,
		"size": float(FileAccess.get_file_as_bytes(file).size()),
		"digest": "sha256:" + sha,
		"browser_download_url": base + name,
	}
	asset.merge(changes, true)
	var data := {
		"tag_name": "v" + version,
		"name": NOTES,
		"body": NOTES,
		"draft": false,
		"prerelease": false,
		"assets":
		[
			{"name": "steam-hero.png", "size": 10.0, "browser_download_url": base + "x.png"},
			asset,
			{"name": "SHA256SUMS", "size": 200.0, "browser_download_url": base + "SHA256SUMS"},
		],
	}
	_http.json[SelfUpdate.API] = data
	_http.files[base + name] = file
	_http.text[base + "SHA256SUMS"] = (
		sums if sums != null else "%s  steam-hero.png\n%s  %s\n" % ["0".repeat(64), sha, name]
	)
	return data


func _make(path: String, changes := {}) -> Node:
	var node := SelfUpdate.new()
	node.appimage = path
	node.version = OWN
	node.http = _http
	node.memory_path = _dir.path_join("self-update.ini")
	node.threaded = false
	node.settle_seconds = 0.0
	node.smoke_seconds = 1.0
	node.smoke_runner = PackedStringArray(SMOKE)
	node.record_path = _dir.path_join("state/anchorage-installer/files.sha256")
	for key in changes:
		node.set(key, changes[key])
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_nodes.append(node)
	return node


## Waits until the update is in one of `states` (the smoke run is a real process).
func _until(node: Node, states: Array, seconds := 5.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var left := seconds
	while not node.info()["state"] in states and left > 0.0:
		await tree.create_timer(0.05).timeout
		left -= 0.05


func _new_file(name: String, script: String, elf := true, magic := true) -> String:
	var file := _dir.path_join(name)
	_appimage(file, script, elf, magic)
	return file


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


func test_only_a_writable_appimage_is_supported() -> void:
	var path := _setup("supported")
	check(SelfUpdate.supported(path), "a file and a folder the user may write (UPD-1)")
	check(not SelfUpdate.supported(""), "APPIMAGE unset")
	check(not SelfUpdate.supported("Applications/Anchorage.AppImage"), "a relative path")
	check(not SelfUpdate.supported(_dir.path_join("missing.AppImage")), "a missing file")
	check(not SelfUpdate.supported(_dir), "a folder")
	FileAccess.set_unix_permissions(path, 0x16D)
	check(not SelfUpdate.supported(path), "a read-only file")
	FileAccess.set_unix_permissions(path, 0x1ED)
	var dir := _dir.path_join("Applications")
	FileAccess.set_unix_permissions(dir, 0x16D)
	check(not SelfUpdate.supported(path), "a folder the user may not write")
	FileAccess.set_unix_permissions(dir, 0x1ED)
	eq(DirAccess.get_files_at(dir), PackedStringArray(["Anchorage.AppImage"]), "the probe is gone")
	var before := _bytes(path)
	_serve(NEXT, _new_file("next.AppImage", "exit 0"))
	FileAccess.set_unix_permissions(path, 0x16D)
	var node := _make(path)
	eq(node.info()["state"], "unsupported", "not supported")
	node.check(true)
	node.start()
	eq(_http.requests, [], "no release is looked for")
	eq(node.info()["state"], "unsupported", "nothing starts")
	eq(DirAccess.get_files_at(dir), PackedStringArray(["Anchorage.AppImage"]), "no file touched")
	eq(_bytes(path), before, "the file is the same")
	eq(_make("").info()["state"], "unsupported", "APPIMAGE unset: unsupported")
	_finish()


func test_versions_compare_as_numbers_and_never_go_down() -> void:
	check(SelfUpdate.newer("0.10.0", "0.9.0"), "0.10.0 is newer than 0.9.0 (UPD-2)")
	check(SelfUpdate.newer("v1.0.0", "0.99.99"), "a v prefix and a major bump")
	check(SelfUpdate.newer("0.2.1", "0.2.0"), "a patch")
	check(not SelfUpdate.newer("0.2.0", "0.2.0"), "the same")
	check(not SelfUpdate.newer("0.1.9", "0.2.0"), "older: never a downgrade")
	for odd in ["0.3.0-rc1", "0.3", "0.3.0.1", "v", "", "0.3.x", " 0.3.0", "1234567.0.0"]:
		check(not SelfUpdate.newer(odd, "0.2.0"), "not a version: %s" % odd)
	check(not SelfUpdate.newer("0.3.0", "dev"), "an own version that is no version")


func test_the_check_finds_only_a_newer_stable_release() -> void:
	var path := _setup("check")
	var next := _new_file("next.AppImage", "exit 0")
	var now := [100000]
	var clock := func() -> int: return now[0]
	var node := _make(path, {"clock": clock})
	eq(node.info()["state"], "none", "nothing known yet")
	var data := _serve(NEXT, next)
	node.check(false)
	eq(node.info()["state"], "available", "a newer release (UPD-2)")
	eq(node.info()["version"], NEXT, "its version")
	eq(
		FileAccess.get_file_as_string(_dir.path_join("self-update.ini")).split("\n").slice(1, 4),
		PackedStringArray(["[anchorage]", "last_check = 100000", "latest = " + NEXT]),
		"remembered beside state.ini"
	)
	_http.requests.clear()
	now[0] += 60
	node.check(false)
	eq(_http.requests, [], "at start, at most once an hour")
	node.check(true)
	eq(_http.requests, [SelfUpdate.API], "refresh always checks")
	var cases := [
		["v0.2.0", {}, "none", "the same version"],
		["v0.1.0", {}, "none", "an older one"],
		["v0.3.0", {"prerelease": true}, "none", "a prerelease"],
		["v0.3.0", {"draft": true}, "none", "a draft"],
		["v0.3.0-rc1", {}, "none", "a prerelease tag"],
	]
	for case in cases:
		var answer: Dictionary = data.duplicate(true)
		answer["tag_name"] = case[0]
		answer.merge(case[1], true)
		_http.json[SelfUpdate.API] = answer
		node.check(true)
		var shown: String = node.info()["state"]
		eq(shown in ["available", "failed"], case[2] != "none", case[3])
	_serve("0.10.0", next)
	node.check(true)
	eq([node.info()["state"], node.info()["version"]], ["available", "0.10.0"], "0.10.0 > 0.2.0")
	_http.json[SelfUpdate.API] = data
	node.check(true)
	eq(node.info()["state"], "available", "newer again")
	_http.offline = true
	node.check(true)
	eq(node.info()["state"], "available", "offline: nothing worse than before")
	eq(node.info()["error"], "", "and no error")
	_http.offline = false
	_http.requests.clear()
	var next_start := _make(path, {"clock": clock})
	eq(next_start.info()["state"], "available", "the next start shows it")
	eq(_http.requests, [], "without a request within the hour")
	now[0] += 7200
	_make(path, {"clock": clock, "check_updates": false})
	eq(_http.requests, [], "check_updates = false: no check at start")
	_make(path, {"clock": clock})
	eq(_http.requests, [SelfUpdate.API], "an hour later the start checks")
	_finish()


func test_a_release_is_read_strictly() -> void:
	var ok := {
		"tag_name": "v0.3.0",
		"assets":
		[
			{"name": NAME, "size": 1000.0, "browser_download_url": URL + NAME},
			{"name": "SHA256SUMS", "size": 10.0, "browser_download_url": URL + "SHA256SUMS"},
		],
	}
	var parsed := SelfUpdate.parse_release(ok, OWN)
	eq(parsed["ok"] and parsed["newer"], true, "a good release")
	eq(parsed["release"]["asset"]["sha256"], "", "no digest listed: SHA256SUMS alone")
	var bad := {
		"foreign host": {"browser_download_url": "https://evil.example/" + NAME},
		"another repo":
		{
			"browser_download_url":
			"https://github.com/evil/anchorage/releases/download/v0.3.0/" + NAME
		},
		"another tag": {"browser_download_url": URL.replace("v0.3.0", "v0.2.0") + NAME},
		"plain http": {"browser_download_url": URL.replace("https", "http") + NAME},
		"user info": {"browser_download_url": "https://github.com@evil.example/" + NAME},
		"over 200 MiB": {"size": 201.0 * 1024 * 1024},
		"an empty file": {"size": 0.0},
		"a size that is text": {"size": "1000"},
		"a broken digest": {"digest": "sha256:xyz"},
	}
	for why in bad:
		var data: Dictionary = ok.duplicate(true)
		data["assets"][0].merge(bad[why], true)
		eq(SelfUpdate.parse_release(data, OWN)["ok"], false, why)
	var twice: Dictionary = ok.duplicate(true)
	twice["assets"].append(twice["assets"][0])
	eq(SelfUpdate.parse_release(twice, OWN)["ok"], false, "the AppImage listed twice")
	var no_sums: Dictionary = ok.duplicate(true)
	no_sums["assets"].pop_back()
	eq(SelfUpdate.parse_release(no_sums, OWN)["ok"], false, "no SHA256SUMS")
	eq(SelfUpdate.parse_release("nonsense", OWN)["ok"], false, "not JSON of a release")
	var local := "http://127.0.0.1:8123"
	var hooked: Dictionary = ok.duplicate(true)
	hooked["assets"][0]["browser_download_url"] = local + "/download/v0.3.0/" + NAME
	hooked["assets"][1]["browser_download_url"] = local + "/download/v0.3.0/SHA256SUMS"
	eq(SelfUpdate.parse_release(hooked, OWN, local)["ok"], true, "the hook's own origin")
	eq(SelfUpdate.parse_release(hooked, OWN)["ok"], false, "but never without the hook")
	eq(SelfUpdate.parse_release(ok, OWN, local)["ok"], false, "and only that origin with it")
	eq(SelfUpdate.hook_url(local + "/api/latest"), local + "/api/latest", "the test hook")
	for refused in ["https://evil.example/x", "http://127.0.0.2:1/x", "http://localhost:1/x"]:
		eq(SelfUpdate.hook_url(refused), SelfUpdate.API, "hook ignored: %s" % refused)
	var sums := "%s  %s\n%s *other\n" % ["a".repeat(64), NAME, "b".repeat(64)]
	eq(SelfUpdate.sums_hash(sums, NAME), "a".repeat(64), "the line for the file")
	eq(SelfUpdate.sums_hash(sums, "missing"), "", "no line")
	eq(SelfUpdate.sums_hash(sums + "%s  %s\n" % ["c".repeat(64), NAME], NAME), "", "two lines")


func test_an_update_downloads_checks_and_swaps() -> void:
	var path := _setup("swap")
	var record := _dir.path_join("state/anchorage-installer/files.sha256")
	DirAccess.make_dir_recursive_absolute(record.get_base_dir())
	var old_sha := FileAccess.get_sha256(path)
	var lines := [
		"%s  /home/deck/.local/share/applications/x.desktop" % "1".repeat(64),
		"%s  %s" % [old_sha, path],
		"%s  /home/deck/.local/share/Steam/userdata/1/config/grid/1p.png" % old_sha,
	]
	var file := FileAccess.open(record, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var ports := PortsFake.new("self-update")
	ports.simulate = false
	var info_before := ports.list().map(func(id: String) -> Dictionary: return ports.info(id))
	var next := _new_file(
		"next.AppImage", '[ "$1" = --appimage-version ] || exit 9; echo "runtime version"; exit 0'
	)
	var next_sha := FileAccess.get_sha256(next)
	_serve(NEXT, next)
	var node := _make(path, {"ports": ports})
	node.check(true)
	var seen := []
	node.changed.connect(func() -> void: seen.append(node.info().duplicate()))
	node.start()
	await _until(node, ["ready", "failed"])
	eq(node.info()["state"], "ready", "swapped (UPD-4 .. UPD-6): %s" % node.info()["error"])
	var progress := seen.filter(func(i: Dictionary) -> bool: return i["progress"] > 0.0)
	check(not progress.is_empty(), "progress while it downloads")
	check(
		seen.any(func(i: Dictionary) -> bool: return i["detail"] == "Trying the new version"),
		"the new AppImage ran once"
	)
	eq(_bytes(path), _bytes(next), "the AppImage is the new one")
	eq(FileAccess.get_unix_permissions(path) & 0x40, 0x40, "and executable")
	eq(FileAccess.get_sha256(SelfUpdate.previous_path(path)), old_sha, "the old one kept")
	check(not FileAccess.file_exists(SelfUpdate.new_path(path)), "no .new left")
	var want := lines.duplicate()
	want[1] = "%s  %s" % [next_sha, path]
	eq(FileAccess.get_file_as_string(record), "\n".join(want) + "\n", "the record's line (UPD-7)")
	eq(ports.calls, [], "no port was called (UPD-8)")
	eq(
		ports.list().map(func(id: String) -> Dictionary: return ports.info(id)),
		info_before,
		"and none changed"
	)
	node.ports = null
	ports.free()
	check(
		_http.requests.has(URL + NAME) and _http.requests.has(URL + "SHA256SUMS"),
		"the AppImage and SHA256SUMS of the release"
	)
	var next_start := _make(path)
	await _until(next_start, ["none"])
	check(
		not FileAccess.file_exists(SelfUpdate.previous_path(path)),
		"the next start removes .previous after it ran a while (UPD-6)"
	)
	_finish()


func test_a_bad_download_is_deleted_and_the_appimage_stays() -> void:
	var path := _setup("bad")
	var before := _bytes(path)
	var next := _new_file("next.AppImage", "exit 0")
	var sha := FileAccess.get_sha256(next)
	var cases := {
		"bad hash": [{}, "%s  %s\n" % ["f".repeat(64), NAME], "different checksums"],
		"bad hash, both lists":
		[
			{"digest": "sha256:" + "f".repeat(64)},
			"%s  %s\n" % ["f".repeat(64), NAME],
			"does not match its checksum"
		],
		"wrong size": [{"size": 4.0}, null, "the release lists 4"],
		"missing line": [{}, "%s  other.AppImage\n" % sha, "has no line for"],
	}
	for why in cases:
		_serve(NEXT, next, cases[why][0], cases[why][1])
		var node := _make(path)
		node.check(true)
		node.start()
		await _until(node, ["failed", "ready"])
		eq(node.info()["state"], "failed", why)
		check(node.info()["error"].begins_with("Could not update “Anchorage”\n"), why)
		check(node.info()["error"].contains(cases[why][2]), "%s: %s" % [why, node.info()["error"]])
		check(not FileAccess.file_exists(SelfUpdate.new_path(path)), "%s: deleted" % why)
		eq(_bytes(path), before, "%s: the AppImage stays" % why)
	_serve(NEXT, next, {"browser_download_url": "https://evil.example/" + NAME})
	var foreign := _make(path, {"memory_path": ""})
	foreign.check(true)
	eq(foreign.info()["state"], "none", "a release with a foreign URL is not offered")
	_serve(NEXT, next)
	foreign.check(true)
	_serve(NEXT, next, {"browser_download_url": "https://evil.example/" + NAME})
	foreign.start()
	eq(foreign.info()["state"], "failed", "nor downloaded when it changed since the check")
	check(foreign.info()["error"].contains("unexpected URL"), foreign.info()["error"])
	check(not _http.requests.has("https://evil.example/" + NAME), "a foreign host is never asked")
	eq(_bytes(path), before, "foreign host: the AppImage stays")
	_serve(NEXT, next)
	var node := _make(path)
	node.check(true)
	node.changed.connect(
		func() -> void:
			if node.info()["progress"] > 0.3 and node.info()["state"] == "downloading":
				node.cancel()
	)
	node.start()
	eq(node.info()["state"], "available", "cancelled: offered again")
	check(not FileAccess.file_exists(SelfUpdate.new_path(path)), "cancelled: deleted")
	eq(_bytes(path), before, "cancelled: the AppImage stays")
	_finish()


func test_the_new_appimage_must_be_one_and_start() -> void:
	var path := _setup("smoke")
	var before := _bytes(path)
	var cases := [
		["not ELF", "exit 0", false, true, "not a Linux program"],
		["no AppImage magic", "exit 0", true, false, "not an AppImage"],
		["fails", "exit 3", true, true, "exit code 3"],
		["hangs", "sleep 30", true, true, "did not answer within 1 s"],
	]
	for case in cases:
		_serve(NEXT, _new_file("next-%d.AppImage" % cases.find(case), case[1], case[2], case[3]))
		var node := _make(path)
		node.check(true)
		var started := Time.get_ticks_msec()
		node.start()
		await _until(node, ["failed", "ready"])
		eq(node.info()["state"], "failed", case[0])
		check(node.info()["error"].contains(case[4]), "%s: %s" % [case[0], node.info()["error"]])
		check(not FileAccess.file_exists(SelfUpdate.new_path(path)), "%s: deleted" % case[0])
		eq(_bytes(path), before, "%s: the running AppImage untouched (UPD-5)" % case[0])
		if case[0] == "hangs":
			check(Time.get_ticks_msec() - started < 4000, "the hanging one was stopped")
	_finish()


func test_the_swap_is_one_rename_and_previous_goes_at_the_next_start() -> void:
	var path := _setup("rename")
	var running := FileAccess.open(path, FileAccess.READ)
	var old := _bytes(path)
	var fresh := SelfUpdate.new_path(path)
	_appimage(fresh, "echo new")
	var sha := FileAccess.get_sha256(fresh)
	var record := _dir.path_join("record")
	eq(SelfUpdate.swap(path, record, sha), "", "swapped")
	eq(FileAccess.get_sha256(path), sha, "the path holds the new file")
	eq(running.get_buffer(old.size()), old, "an open handle still reads the old file (rename)")
	running.close()
	eq(_bytes(SelfUpdate.previous_path(path)), old, "a copy of the old one")
	check(not FileAccess.file_exists(fresh), "no .new")
	check(not FileAccess.file_exists(record), "no record: none is made")
	eq(SelfUpdate.swap(path, record, sha).is_empty(), false, "no .new: an error")
	eq(FileAccess.get_sha256(path), sha, "and the path is as it was")
	# A young .new may be another Anchorage's download; an old one is left over.
	_appimage(fresh, "echo stale")
	var node := _make(path, {"settle_seconds": 0.3, "clock": func() -> int: return 0})
	check(FileAccess.file_exists(fresh), "a young .new stays")
	check(FileAccess.file_exists(SelfUpdate.previous_path(path)), "kept while it settles")
	await _until(node, ["never"], 0.6)
	check(not FileAccess.file_exists(SelfUpdate.previous_path(path)), "gone after it ran a while")
	var late := _make(path, {"clock": func() -> int: return 10 ** 10})
	check(not FileAccess.file_exists(fresh), "an old .new is deleted at start")
	eq(late.info()["state"], "none", "and nothing else happens")
	_finish()


func test_the_installers_record_follows_the_swap() -> void:
	var path := _setup("record")
	var record := _dir.path_join("files.sha256")
	var old := "a".repeat(64)
	var new := FileAccess.get_sha256(path)
	var text := "%s  /x/desktop\n%s  %s\n%s  /x/other\n" % ["b".repeat(64), old, path, old]
	var file := FileAccess.open(record, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	check(SelfUpdate.update_record(record, path, old, new), "updated (UPD-7)")
	eq(
		FileAccess.get_file_as_string(record),
		"%s  /x/desktop\n%s  %s\n%s  /x/other\n" % ["b".repeat(64), new, path, old],
		"only the AppImage's hash changed, every other byte stays"
	)
	check(not SelfUpdate.update_record(record, path, old, new), "a line with another hash stays")
	check(not FileAccess.file_exists(record + ".anchorage-self-update"), "no temp file")
	var link := _dir.path_join("home-link")
	OS.execute("ln", ["-s", _dir, link])
	var through := link.path_join("Applications/Anchorage.AppImage")
	file = FileAccess.open(record, FileAccess.WRITE)
	file.store_string("%s  %s\n" % [old, through])
	file.close()
	check(SelfUpdate.update_record(record, path, old, new), "a HOME behind a symlink")
	check(not SelfUpdate.update_record(_dir.path_join("none"), path, old, new), "no record")
	# A power loss after the rename and before the record: the next start finishes it.
	file = FileAccess.open(record, FileAccess.WRITE)
	file.store_string("%s  %s\n" % [old, path])
	file.close()
	var previous := SelfUpdate.previous_path(path)
	_appimage(previous, "echo old")
	var previous_sha := FileAccess.get_sha256(previous)
	file = FileAccess.open(record, FileAccess.WRITE)
	file.store_string("%s  %s\n" % [previous_sha, path])
	file.close()
	_make(path, {"record_path": record})
	eq(FileAccess.get_file_as_string(record), "%s  %s\n" % [new, path], "finished at start")
	check(not FileAccess.file_exists(previous), "and .previous removed")
	_finish()


func test_nothing_starts_or_swaps_while_a_port_is_busy() -> void:
	var path := _setup("busy")
	var before := _bytes(path)
	_serve(NEXT, _new_file("next.AppImage", "exit 0"))
	var busy := [true]
	var node := _make(path, {"blocked": func() -> bool: return busy[0]})
	node.check(true)
	_http.requests.clear()
	eq(node.info()["blocked"], true, "blocked shows (UPD-8)")
	node.start()
	eq(node.info()["state"], "waiting", "waits for the ports")
	eq(node.info()["detail"], "Finish what is running first", "and says so")
	eq(_http.requests, [], "nothing downloaded meanwhile")
	await _until(node, ["never"], 0.2)
	eq(node.info()["state"], "waiting", "still waiting")
	busy[0] = false
	await _until(node, ["ready", "failed"])
	eq(node.info()["state"], "ready", "starts once they are done")
	eq(node.restart() != "", false, "restart when idle")
	# Busy again by the time the download is checked: the swap waits.
	_appimage(path, "echo old")
	before = _bytes(path)
	node = _make(path, {"blocked": func() -> bool: return busy[0]})
	node.check(true)
	node.changed.connect(
		func() -> void:
			if node.info()["detail"] == "Trying the new version":
				busy[0] = true
	)
	node.start()
	await _until(node, ["waiting", "failed", "ready"])
	await _until(node, ["failed", "ready"], 0.3)
	eq(node.info()["state"], "waiting", "the swap waits")
	eq(_bytes(path), before, "and nothing is replaced")
	eq(node.restart(), "There is no new version to start", "no restart before the swap")
	busy[0] = false
	await _until(node, ["ready", "failed"])
	eq(node.info()["state"], "ready", "then swaps")
	busy[0] = true
	eq(node.restart(), "Finish what is running first", "no restart while busy")
	# The rule reads the ports through the screens' interface: busy or running blocks.
	for case in [["self-update", false], ["showcase", true], ["installing", true]]:
		var demo := PortsFake.new(case[0])
		eq(SelfUpdate.busy(demo), case[1], "ports %s" % case[0])
		demo.free()
	var running := PortsFake.new("playing")
	eq(SelfUpdate.busy(running), true, "a port running")
	var wired := _make(path, {"ports": running})
	eq(wired.info()["blocked"], true, "the node uses it")
	wired.ports = null
	running.free()
	_finish()


func test_restart_waits_for_this_process_and_drops_the_appimage_variables() -> void:
	_setup("restart")
	var program := _dir.path_join("new.AppImage")
	var file := FileAccess.open(program, FileAccess.WRITE)
	file.store_string('#!/bin/sh\necho "args: $*"\nenv\n')
	file.close()
	FileAccess.set_unix_permissions(program, 0x1ED)
	# What an AppImage runtime sets, on this process: a child inherits the live environment.
	var path := OS.get_environment("PATH")
	var runtime := {
		"PATH": "/tmp/.mount_x/usr/bin:" + path,
		"APPIMAGE": program,
		"APPDIR": "/tmp/.mount_x",
		"ARGV0": "Anchorage.AppImage",
		"OWD": _dir,
		"APPIMAGE_EXTRACT_AND_RUN": "1",
	}
	# What Game Mode sets (WIN-6): the new copy must find it too, to open fullscreen.
	var game_mode := {
		"XDG_CURRENT_DESKTOP": "gamescope",
		"GAMESCOPE_WAYLAND_DISPLAY": "gamescope-0",
		"SteamGameId": "15790555012393680896",
		"SteamAppId": "0",
	}
	var saved := {}
	for name in game_mode:
		if OS.has_environment(name):
			saved[name] = OS.get_environment(name)
		runtime[name] = game_mode[name]
	for name in runtime:
		OS.set_environment(name, runtime[name])
	var base := Launcher.current_environment()
	# Steam sets them before Anchorage starts, so they are in /proc/self/environ too.
	base.merge(game_mode, true)
	var log := _dir.path_join("restart.log")
	var waited := OS.create_process("/bin/sh", PackedStringArray(["-c", "sleep 0.6"]))
	var args := SelfUpdate.restart_command(
		waited, program, base, log, PackedStringArray(["--flag"]), PackedStringArray(["x"])
	)
	eq(
		args.slice(0, 5),
		PackedStringArray(
			["-c", SelfUpdate.WAIT_SCRIPT, "anchorage-restart", str(waited), "/bin/sh"]
		),
		"/bin/sh waits, then the launcher's script (UPD-9)"
	)
	for at in args.size() - 1:
		if args[at] == "-u":
			check(not game_mode.has(args[at + 1]), "%s is not unset" % args[at + 1])
	var spawned := OS.create_process("/bin/sh", args)
	check(spawned > 0, "spawned")
	OS.set_environment("PATH", path)
	for name in runtime:
		if name != "PATH":
			OS.unset_environment(name)
	for name in saved:
		OS.set_environment(name, saved[name])
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(0.3).timeout
	check(not FileAccess.file_exists(log), "nothing starts while the process runs")
	var left := 50
	while OS.is_process_running(waited) and left > 0:
		await tree.create_timer(0.05).timeout
		left -= 1
	left = 60
	while OS.is_process_running(spawned) and left > 0:
		await tree.create_timer(0.05).timeout
		left -= 1
	var out := FileAccess.get_file_as_string(log)
	check(out.contains("args: --flag -- x"), "the same arguments: %s" % out)
	for gone in ["APPIMAGE=", "APPDIR=", "ARGV0=", "OWD="]:
		check(not ("\n" + out).contains("\n" + gone), "no %s" % gone)
	check(out.contains("\nAPPIMAGE_EXTRACT_AND_RUN=1"), "extract-and-run kept: the user set it")
	check(out.contains("\nANCHORAGE_TEST_SENTINEL=a=b c"), "the rest of the environment")
	check(out.contains("\nPATH=%s\n" % path), "the mount's PATH entry dropped (PORT-15)")
	for name in game_mode:
		check(
			out.contains("\n%s=%s\n" % [name, game_mode[name]]),
			"%s kept: the new copy opens fullscreen in Game Mode (WIN-6)" % name
		)
	_finish()


func test_no_text_of_a_release_is_shown() -> void:
	var path := _setup("notes")
	_serve(NEXT, _new_file("next.AppImage", "exit 0"))
	var node := _make(path)
	node.check(true)
	var parsed := SelfUpdate.parse_release(_http.json[SelfUpdate.API], OWN)
	check(not var_to_str(parsed).contains("EVIL"), "the notes are not read (UPD-10)")
	check(not var_to_str(node.info()).contains("EVIL"), "nor shown")
	eq(node.info()["version"], NEXT, "only the version")
	_finish()


# The home screen (UPD-3) ------------------------------------------------------------------


func _home(scenario: String, simulate := false) -> Control:
	Keys.apply({})
	var ports := PortsFake.new(scenario)
	ports.simulate = simulate
	var own := SelfUpdateFake.new(scenario)
	own.simulate = simulate
	own.ports = ports
	var host := Control.new()
	host.theme = Style.build("mocha", "mauve")
	host.add_child(ports)
	host.add_child(own)
	var home := HomeScene.instantiate()
	home.ports = ports
	home.self_update = own
	host.add_child(home)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	return home


func _done(home: Control) -> void:
	var host := home.get_parent()
	host.get_parent().remove_child(host)
	host.free()


func _press(home: Control, keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		home.get_viewport().push_input(key)


func _entries(home: Control) -> Array:
	var out := []
	for button in home.get_node("%AppMenuLayer").find_children("*", "Button", true, false):
		if button.visible:
			out.append(button.text)
	return out


func test_the_chip_the_toast_and_the_menu_entry() -> void:
	var demo := SelfUpdateFake.new("self-update")
	var next: String = demo.info()["version"]
	demo.free()
	var home := _home("self-update")
	var chip: Control = home.get_node("%UpdateChip")
	check(chip.visible, "the chip (UPD-3)")
	eq(home.get_node("%UpdateChipText").text, "Update " + next, "its text")
	eq(home.toast_text(), "Anchorage %s is available" % next, "the toast")
	check(chip.get_parent().get_parent() == home.get_node("%HintBar"), "in the bottom bar")
	_press(home, KEY_F10)
	eq(_entries(home)[0], "Update Anchorage to " + next, "the first entry")
	eq(home.get_viewport().gui_get_focus_owner(), home.get_node("%SelfUpdateButton"), "focused")
	_press(home, KEY_ENTER)
	eq(home.self_update.calls, ["start"], "accept starts it")
	_done(home)
	home = _home("self-busy")
	_press(home, KEY_F10)
	eq(_entries(home)[0], "Finish what is running first", "while a port is busy (UPD-8)")
	_done(home)
	home = _home("self-unsupported")
	check(not home.get_node("%UpdateChip").visible, "not an AppImage: no chip")
	_press(home, KEY_F10)
	eq(_entries(home)[0], "Updates come from how you installed it", "the line instead (UPD-1)")
	eq(
		home.get_viewport().gui_get_focus_owner(),
		home.get_node("%CatalogButton"),
		"it takes no focus"
	)
	_press(home, KEY_UP)
	eq(
		home.get_viewport().gui_get_focus_owner(),
		home.get_node("%CatalogButton"),
		"not even from below"
	)
	_done(home)
	home = _home("showcase")
	check(not home.get_node("%UpdateChip").visible, "nothing newer: no chip")
	eq(home.toast_text(), "", "and no toast")
	_press(home, KEY_F10)
	eq(_entries(home).size(), 3, "and no entry")
	_done(home)


func test_the_dialog_shows_progress_cancel_and_restart() -> void:
	var home := _home("self-downloading")
	_press(home, KEY_F10)
	check(_entries(home)[0].begins_with("Updating Anchorage to "), "while it downloads")
	_press(home, KEY_ENTER)
	eq(home.mode, home.Mode.UPDATE, "the dialog")
	check(not home.get_node("%AppMenuLayer").visible, "in place of the app menu")
	check(home.get_node("%ConfirmTitle").text.begins_with("Updating Anchorage to "), "title")
	eq(home.get_node("%ConfirmBody").text, "20.2 MB of 48.1 MB", "the progress text")
	check(home.get_node("%ConfirmProgress").visible, "and bar (UPD-4)")
	eq(home.get_node("%ConfirmProgress").value, 42.0, "at 42 %")
	check(not home.get_node("%ConfirmButton").visible, "one button")
	eq(home.hint_text(), "A Enter Select · B Escape Cancel", "hints")
	_press(home, KEY_ESCAPE)
	eq(home.self_update.calls, ["cancel"], "back cancels")
	eq(home.mode, home.Mode.HOME, "and closes")
	_done(home)
	home = _home("self-ready")
	var quits := []
	home.quit_requested.connect(func() -> void: quits.append(true))
	check(home.get_node("%UpdateChipText").text.begins_with("Restart for "), "the chip once ready")
	_press(home, KEY_F10)
	check(_entries(home)[0].begins_with("Restart for Anchorage "), "the entry")
	_press(home, KEY_ENTER)
	eq(home.get_node("%CancelButton").text, "Later", "Later (UPD-9)")
	eq(home.get_node("%ConfirmButton").text, "Restart now", "Restart now")
	check(home.get_node("%ConfirmBody").text.contains("start it again from your library"), "Steam")
	_press(home, KEY_ENTER)
	eq(quits, [], "focus starts on Later: accept quits nothing")
	_press(home, KEY_F10)
	_press(home, KEY_ENTER)
	_press(home, KEY_RIGHT)
	_press(home, KEY_ENTER)
	eq(home.self_update.calls, ["restart"], "Restart now")
	eq(quits, [true], "then quits")
	_done(home)
	# Played out: start, download, ready, with the dialog following.
	home = _home("self-update", true)
	_press(home, KEY_F10)
	_press(home, KEY_ENTER)
	eq(home.mode, home.Mode.UPDATE, "the dialog opens with the download")
	check(home.get_node("%ConfirmProgress").visible, "with its bar")
	home.self_update.advance(10.0)
	check(home.get_node("%ConfirmButton").visible, "ready after the download")
	eq(home.get_node("%ConfirmButton").text, "Restart now", "Restart now")
	_done(home)

extends "res://tests/case.gd"
## The catalog fetched from the repository (PORT-18 .. PORT-23): parsing and the stricter
## checks of a fetched catalog, hostile entries, the merge, the cache, the throttle, the
## notice and the `New` marker, and downloads only from the merged catalog's repos. Ports
## runs over fake HTTP, temp folders and fake port scripts.

const Catalog := preload("res://src/catalog.gd")
const CatalogUpdate := preload("res://src/catalog_update.gd")
const Ports := preload("res://src/ports.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const Releases := preload("res://src/releases.gd")
const Launcher := preload("res://src/launcher.gd")
const State := preload("res://src/state.gd")
const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const URL := "https://raw.githubusercontent.com/test/anchorage/main/app/data/ports.json"
const NOW := 1_800_000_000

var _dir := ""
var _http: RefCounted


func _setup(name: String) -> void:
	_dir = temp_dir(name)
	_http = FakeHttp.new()


func _port(id: String, extra := {}) -> Dictionary:
	var port := {
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
		"first_run": "",
		"roms": [{"label": "US", "sha1": id.sha1_text()}],
	}
	port.merge(extra, true)
	return port


func _text(ports: Array, version: Variant = 2, schema: Variant = 1) -> String:
	var data := {"version": version, "ports": ports}
	if schema != null:
		data["schema"] = schema
	return JSON.stringify(data)


func _make(check := true, threaded := false) -> Node:
	var ports: Node = Ports.new()
	ports.root = _dir.path_join("ports")
	ports.state_path = _dir.path_join("state/state.ini")
	ports.roms_dir = _dir.path_join("roms")
	ports.check_updates = check
	ports.catalog = [_port("alpha"), _port("beta")]
	ports.catalog_version = 1
	ports.catalog_url = URL
	ports.catalog_cache = _cache()
	ports.http = _http
	ports.threaded = threaded
	ports.clock = func() -> int: return NOW
	(Engine.get_main_loop() as SceneTree).root.add_child(ports)
	return ports


func _cache() -> String:
	return _dir.path_join("cache/anchorage/catalog.json")


func _drop(ports: Node) -> void:
	ports.get_parent().remove_child(ports)
	ports.free()


func _free(ports: Node) -> void:
	_drop(ports)
	remove(_dir)


func _catalog_requests() -> int:
	return _http.requests.count(URL)


## Publishes `tag` of a port on the fake GitHub at `url` (a fake port script in a zip).
func _publish(id: String, repo: String, tag: String, url := "") -> String:
	var zip_path := _dir.path_join("%s-%s.zip" % [id, tag])
	DirAccess.make_dir_recursive_absolute(_dir)
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file(id + ".appimage")
	packer.write_file("#!/bin/sh\nexit 0\n".to_utf8_buffer())
	packer.close_file()
	packer.close()
	if url.is_empty():
		url = "https://github.com/%s/releases/download/%s/%s-Linux.zip" % [repo, tag, id]
	_http.files[url] = zip_path
	_http.json[Releases.API % repo] = {
		"tag_name": tag,
		"assets":
		[
			{
				"name": id + "-Linux.zip",
				"browser_download_url": url,
				"size": FileAccess.get_file_as_bytes(zip_path).size(),
			}
		],
	}
	return url


# Parsing a fetched catalog (PORT-19) ---------------------------------------------------


func test_the_shipped_catalog_has_a_schema_and_a_version() -> void:
	var data: Dictionary = JSON.parse_string(repo_file("app/data/ports.json"))
	eq(data.get("schema"), 1.0, "schema 1")
	check(data.get("version") is float and data["version"] >= 1.0, "a version")
	var shipped := Catalog.load_default()
	eq(shipped["version"], int(data["version"]), "read as the version in use")
	var fetched := Catalog.parse(repo_file("app/data/ports.json"), true)
	check(fetched["ok"], "it passes the fetched checks too")
	eq(fetched["errors"], PackedStringArray(), "with no problem")
	eq(fetched["ports"].size(), 7, "all seven")


func test_nonsense_oversize_and_future_schemas_are_refused_whole() -> void:
	var deep := '{"ports": ' + "[".repeat(100000)
	for bad in ["{nope", "[]", '{"ports": 5}', "", "null", deep, "\u0001"]:
		var parsed := Catalog.parse(bad, true)
		check(not parsed["ok"], "refused: %s" % bad)
		eq(parsed["ports"], [], "no ports from: %s" % bad)
	check(not Catalog.parse(_text([_port("x")], 2, 2), true)["ok"], "schema 2 is too new")
	check(
		str(Catalog.parse(_text([_port("x")], 2, 2), true)["errors"]).contains(Catalog.NEWER),
		"and says it needs a newer Anchorage"
	)
	check(not Catalog.parse(_text([_port("x")], 2, null), true)["ok"], "schema is required")
	check(not Catalog.parse(JSON.stringify({"schema": 1, "ports": []}), true)["ok"], "version too")
	for odd in [0, -1, 1.5, "1", true]:
		check(not Catalog.parse(_text([_port("x")], 2, odd), true)["ok"], "schema %s" % str(odd))
		check(not Catalog.parse(_text([_port("x")], odd), true)["ok"], "version %s" % str(odd))
	var big := _port("x", {"description": "d"})
	var many := []
	for i in 40:
		many.append(_port("p%d" % i, {"first_run": "n".repeat(390)}))
	var text := _text(many)
	var padded := (
		text.substr(0, text.length() - 1) + ', "pad": "%s"}' % "x".repeat(Catalog.MAX_BYTES)
	)
	check(not Catalog.parse(padded, true)["ok"], "over 256 KiB is refused")
	check(Catalog.parse(_text([big]), true)["ok"], "a small one is fine")


func test_one_bad_entry_is_skipped_and_the_rest_are_used() -> void:
	var broken := _port("broken", {"roms": [{"label": "US", "sha1": "nope"}]})
	var future := _port("future", {"rom_place": "cartridge"})
	var field := _port("field", {"homepage": "https://example.com"})
	var cwd := _port("cwd", {"launch": {"executable": "c", "cwd": "home", "args": []}})
	var parsed := Catalog.parse(_text([_port("a"), broken, future, field, cwd, _port("b")]), true)
	check(parsed["ok"], "the catalog is used")
	eq(parsed["ports"].map(func(p: Dictionary) -> String: return p["id"]), ["a", "b"], "good ones")
	eq(parsed["newer"], ["future", "field", "cwd"], "skipped as needing a newer Anchorage")
	eq(parsed["errors"].size(), 4, "one message each")
	check(str(parsed["errors"]).contains("future: needs a newer Anchorage"), "named so")
	var art := _port("art", {"art": {"url": "https://example.com/x.png"}})
	eq(Catalog.parse(_text([art]), true)["ports"], [], "bad art refuses a fetched entry")
	eq(Catalog.parse(_text([art]))["ports"].size(), 1, "the built-in one only loses its art")


# Hostile entries (PORT-22) -------------------------------------------------------------


## Every one of these must be refused, in a fetched catalog and in the built-in one.
func _hostile() -> Dictionary:
	var launch := func(field: String, value: Variant) -> Dictionary:
		var out := {"executable": "x.appimage", "cwd": "data", "args": []}
		out[field] = value
		return {"launch": out}
	var cases := {}
	for repo in [
		"evil.example/../x",
		"a/b/c",
		"owner/..",
		"../x",
		"owner/.",
		"ówner/x",
		"owner/x?y",
		"owner/x#",
		"owner/x y",
		"owner/x\n",
		"https://evil.example/x",
		"owner",
	]:
		cases["repo " + repo.c_escape()] = {"repo": repo}
	for path in [
		"/bin/sh",
		"../x",
		"a/../../x",
		"$(touch pwned)",
		"x;touch pwned",
		"x\ntouch pwned",
		"x\n",
		"x\u0001",
		"`id`",
		"-rf",
		".hidden",
		"a/.x",
		"a b",
		"x|y",
		"x&y",
		"x>y",
		"'x'",
		'"x"',
		"x\\y",
		"~/x",
		"a//b",
		"a/",
		"",
		"x".repeat(129),
		"x\u202e",
	]:
		cases["executable " + path.c_escape()] = launch.call("executable", path)
		cases["archive " + path.c_escape()] = {"archive": [path]}
		cases["extra_files " + path.c_escape()] = {"extra_files": ["ok.txt", path]}
		cases["rom_file " + path.c_escape()] = {"rom_file": path + ".z64"}
	for name in ["a/x.z64", "x.n64", "/tmp/x.z64", "../x.z64"]:
		cases["rom_file " + name] = {"rom_file": name}
	for arg in [
		"$(touch pwned)",
		"`touch pwned`",
		"a b",
		"a;b",
		"a|b",
		"a&b",
		"'",
		'"',
		"/etc/passwd",
		"../x",
		"--x=../../y",
		"a\nb",
		"a\n",
		"",
		"x".repeat(129),
		5,
	]:
		cases["arg " + str(arg).c_escape()] = launch.call("args", [arg])
	var many := []
	for i in Catalog.ARGS_MAX + 1:
		many.append("a")
	cases["17 args"] = launch.call("args", many)
	cases["args not a list"] = launch.call("args", "--x")
	cases["cwd /"] = launch.call("cwd", 5)
	for id in ["../x", "A", "x/y", "", "x".repeat(33), "x.y", "x\n"]:
		cases["id " + id] = {"id": id}
	for text in ["a\u0001b", "\u001b[31mred", "a\u202eb", "a\rb", "x\u200bx", "a\u0085b"]:
		cases["name " + text.c_escape()] = {"name": text}
		cases["first_run " + text.c_escape()] = {"first_run": text}
		cases["label " + text.c_escape()] = {"roms": [{"label": text, "sha1": "a".repeat(40)}]}
	cases["long description"] = {"description": "d".repeat(401)}
	cases["suffix with a slash"] = {"asset_suffix": "../x.zip"}
	var roms := []
	for i in Catalog.ROMS_MAX + 1:
		roms.append({"label": "L", "sha1": "a".repeat(40)})
	cases["65 roms"] = {"roms": roms}
	for url in [
		"https://evil.example/x.png",
		"https://cdn2.steamgriddb.com@evil.example/x.png",
		"https://cdn2.steamgriddb.com.evil.example/x.png",
		"https://cdn2.steamgriddb.com:8443/x.png",
		"http://cdn2.steamgriddb.com/x.png",
		"https://cdn2.steamgriddb.com/x.png?u=https://evil.example",
		"https://cdn2.steamgriddb.com/x\\@evil.example/x.png",
		"https://cdn2.steamgriddb.com/%2e%2e/x.png",
	]:
		cases["art " + url] = {
			"art":
			{
				"url": url,
				"author": "A",
				"source": "https://www.steamgriddb.com/grid/1",
				"style": "alternate",
			}
		}
	cases["art source elsewhere"] = {
		"art":
		{
			"url": "https://cdn2.steamgriddb.com/grid/x.png",
			"author": "A",
			"source": "https://www.steamgriddb.com.evil.example/",
			"style": "alternate",
		}
	}
	return cases


func test_hostile_entries_are_refused() -> void:
	var cases := _hostile()
	check(cases.size() > 150, "a long list: %d" % cases.size())
	for label in cases:
		var entry := _port("hostile", cases[label])
		var parsed := Catalog.parse(_text([_port("good"), entry]), true)
		check(parsed["ok"], "%s: the catalog itself is still used" % label)
		eq(parsed["ports"].size(), 1, "%s is refused (PORT-22)" % label)
	eq(Catalog.parse(_text([_port("good")]), true)["ports"].size(), 1, "the good one passes")


func test_allowed_values_reach_the_port_as_plain_arguments() -> void:
	_setup("catalog_argv")
	var args := ["--fullscreen", "-w", "1280", "mode=a:b,c+d", "x.o2r", "_x"]
	var entry := _port(
		"plain", {"launch": {"executable": "bin/plain.appimage", "cwd": "data", "args": args}}
	)
	var parsed := Catalog.parse(_text([entry]), true)
	eq(parsed["ports"].size(), 1, "accepted")
	var root := _dir.path_join("ports")
	var port: Dictionary = parsed["ports"][0]
	var exe := Launcher.executable(root, port)
	DirAccess.make_dir_recursive_absolute(exe.get_base_dir())
	var script := FileAccess.open(exe, FileAccess.WRITE)
	script.store_string('#!/bin/sh\nfor a in "$@"; do printf "ARG=%s\\n" "$a"; done\n')
	script.close()
	FileAccess.set_unix_permissions(exe, 493)
	var started := Launcher.start(root, port, {"PATH": "/usr/bin:/bin"})
	check(started["pid"] > 0, "started")
	for _i in 100:
		if not OS.is_process_running(started["pid"]):
			break
		OS.delay_msec(20)
	var log := FileAccess.get_file_as_string(Launcher.log_path(root, "plain"))
	eq(log, "".join(args.map(func(a: String) -> String: return "ARG=%s\n" % a)), "verbatim")
	remove(_dir)


## Even a value the catalog would refuse never reaches a shell as code: the launcher's
## script is fixed and the port's path and arguments are argv entries (`exec "$@"`).
func test_the_launcher_never_reads_a_value_as_shell_code() -> void:
	_setup("catalog_shell")
	var evil := [
		"$(touch pwned)",
		"`touch pwned`",
		"; touch pwned",
		"| touch pwned",
		"&& touch pwned",
		"\ntouch pwned",
		"' ; touch pwned ; '",
		'" ; touch pwned ; "',
		"${IFS}touch${IFS}pwned",
	]
	var cwd := _dir.path_join("cwd $(touch pwned) `touch pwned`")
	var program := cwd.path_join("echo args; touch pwned")
	DirAccess.make_dir_recursive_absolute(cwd)
	var script := FileAccess.open(program, FileAccess.WRITE)
	script.store_string('#!/bin/sh\nfor a in "$@"; do printf "ARG=%s\\n" "$a"; done\n')
	script.close()
	FileAccess.set_unix_permissions(program, 493)
	var log := _dir.path_join("log $(touch pwned); touch pwned")
	var env := {"X": "$(touch pwned)"}
	var args := Launcher.shell_args({}, env, cwd, log, program, evil)
	eq(args[1], Launcher.SCRIPT, "the script is the fixed one")
	# OS.create_process, as Launcher.start: fork and execvp, no shell between.
	var pid := OS.create_process(Launcher.SHELL, args)
	check(pid > 0, "started")
	for _i in 100:
		if not OS.is_process_running(pid):
			break
		OS.delay_msec(20)
	eq(OS.get_process_exit_code(pid), 0, "it ran")
	for dir in [_dir, cwd, OS.get_environment("PWD"), ProjectSettings.globalize_path("res://")]:
		check(not FileAccess.file_exists(dir.path_join("pwned")), "nothing ran in %s" % dir)
	var got := FileAccess.get_file_as_string(log)
	eq(got, "".join(evil.map(func(a: String) -> String: return "ARG=%s\n" % a)), "verbatim")
	remove(_dir)


## Godot's OS.execute with an output array joins its arguments into one popen() command
## line, quoted but not escaped (drivers/unix/os_unix.cpp), so a value with a `"` in it
## becomes shell code. The app starts processes only with OS.create_process (execvp).
func test_the_app_never_uses_os_execute() -> void:
	var words := RegEx.create_from_string(
		"\\bOS\\s*\\.\\s*(execute|execute_with_pipe|shell_open)\\b"
	)
	for dir in ["res://src", "res://src/ui"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var code := RegEx.create_from_string("#[^\\n]*").sub(
				FileAccess.get_file_as_string(dir.path_join(file)), "", true
			)
			eq(words.search(code), null, "%s/%s starts processes only through execvp" % [dir, file])


# Merging (PORT-20) ---------------------------------------------------------------------


func test_merge_adds_replaces_keeps_and_drops_by_id() -> void:
	var current := [_port("a"), _port("b"), _port("c")]
	var changed_a := _port("a", {"description": "New text"})
	var fetched := [changed_a, _port("c"), _port("d")]
	var keep := func(id: String) -> bool: return id == "b"
	var merged := Catalog.merge(current, 1, fetched, 2, keep)
	var ids: Array = merged["ports"].map(func(p: Dictionary) -> String: return p["id"])
	eq(ids, ["a", "b", "c", "d"], "known ones keep their place, new ones go last")
	eq(merged["added"], ["d"], "added")
	eq(merged["replaced"], ["a"], "replaced: only what changed")
	eq(merged["ports"][0]["description"], "New text", "by the newer entry")
	merged = Catalog.merge(current, 1, fetched, 2, func(_id: String) -> bool: return false)
	eq(merged["dropped"], ["b"], "a newer catalog drops an uninstalled port it no longer lists")
	merged = Catalog.merge(current, 2, fetched, 2, keep)
	eq(merged["replaced"], [], "the same version replaces nothing")
	eq(merged["ports"][0]["description"], "About a", "the entry in use stays")
	eq(merged["added"], ["d"], "but an unknown port is still added")
	eq(merged["dropped"], [], "and nothing is dropped")


func test_a_fetch_adds_new_ports_after_the_others() -> void:
	_setup("catalog_add")
	_http.text[URL] = _text([_port("alpha"), _port("beta"), _port("gamma"), _port("delta")])
	var notices := []
	var ports := _make(false)
	ports.notice_changed.connect(func() -> void: notices.append(ports.notice()))
	eq(_catalog_requests(), 0, "check_updates = false: no fetch at start")
	ports.refresh()
	eq(_catalog_requests(), 1, "refresh always fetches (PORT-18)")
	eq(ports.list(), ["alpha", "beta", "gamma", "delta"], "new ports after the existing ones")
	eq(notices, ["2 new ports: Gamma, Delta"], "one notice (PORT-23)")
	check(ports.info("gamma").is_new and ports.info("delta").is_new, "both are new")
	check(not ports.info("alpha").is_new, "a known one is not")
	eq(ports.info("gamma").installed, false, "listed, not installed")
	var api: Array = _http.requests.filter(
		func(u: String) -> bool: return u.begins_with("https://api.")
	)
	check(Releases.API % "test/gamma" in api, "the update check that follows asks about it too")
	ports.mark_seen("gamma")
	check(not ports.info("gamma").is_new, "focused once: not new")
	_drop(ports)
	ports = _make(false)
	eq(ports.list(), ["alpha", "beta", "gamma", "delta"], "the cache lists them at the next start")
	check(not ports.info("gamma").is_new, "seen stays seen")
	check(ports.info("delta").is_new, "the badge survives a restart (state.ini)")
	check(
		"delta" in State.load_from(_dir.path_join("state/state.ini")).catalog()["new"],
		"stored there"
	)
	ports.notice_changed.connect(func() -> void: notices.append(ports.notice()))
	ports.refresh()
	eq(notices.size(), 1, "the same catalog again: no notice")
	_free(ports)


func test_an_unchanged_catalog_changes_nothing() -> void:
	_setup("catalog_same")
	_http.text[URL] = _text([_port("alpha"), _port("beta")], 1)
	var ports := _make(false)
	var events := []
	ports.notice_changed.connect(func() -> void: events.append("notice"))
	ports.changed.connect(func(id: String) -> void: events.append(id))
	ports.refresh()
	eq(ports.list(), ["alpha", "beta"], "same list")
	eq(events.filter(func(e: String) -> bool: return e == "notice"), [], "no notice")
	eq(ports.notice(), "", "nothing to say")
	_free(ports)


func test_a_newer_catalog_replaces_known_entries_and_never_touches_installed_ports() -> void:
	_setup("catalog_replace")
	_publish("alpha", "test/alpha", "1.0")
	var ports := _make(false)
	ports.install("alpha")
	check(ports.info("alpha").installed, "installed")
	var data := _dir.path_join("ports/alpha/data")
	DirAccess.make_dir_recursive_absolute(data)
	var save := FileAccess.open(data.path_join("save.sav"), FileAccess.WRITE)
	save.store_string("progress")
	save.close()
	var state_before := FileAccess.get_file_as_string(_dir.path_join("state/state.ini"))
	var same_version := _port("alpha", {"description": "Old catalog says"})
	_http.text[URL] = _text([same_version, _port("beta")], 1)
	ports.refresh()
	eq(ports.info("alpha").description, "About alpha", "an equal version replaces nothing")
	var changed := []
	ports.changed.connect(func(id: String) -> void: changed.append(id))
	var newer := _port("alpha", {"description": "Fixed text", "first_run": "Press Play"})
	_http.text[URL] = _text([newer], 3)
	ports.refresh()
	eq(ports.info("alpha").description, "Fixed text", "a higher version replaces it")
	check("alpha" in changed, "and says so")
	eq(ports.list(), ["alpha", "beta"], "beta, gone from the catalog, stays until the next start")
	check(ports.info("alpha").installed, "still installed")
	eq(ports.info("alpha").installed_version, "1.0", "same version")
	eq(FileAccess.get_file_as_string(data.path_join("save.sav")), "progress", "data kept")
	var state := State.load_from(_dir.path_join("state/state.ini"))
	eq(state.installed_version("alpha"), "1.0", "state kept")
	check(state_before.contains("alpha.installed = 1.0"), "it was there before")
	_drop(ports)
	ports = _make(false)
	eq(ports.list(), ["alpha"], "beta (not installed) dropped at the next start")
	eq(ports.info("alpha").description, "Fixed text", "the cached entry is used")
	_free(ports)


func test_an_installed_port_the_catalog_drops_stays() -> void:
	_setup("catalog_keep")
	_publish("beta", "test/beta", "1.0")
	var ports := _make(false)
	ports.install("beta")
	_http.text[URL] = _text([_port("alpha")], 5)
	ports.refresh()
	_drop(ports)
	ports = _make(false)
	eq(ports.list(), ["alpha", "beta"], "beta is installed, so it stays (PORT-20)")
	_free(ports)


# Cache and throttle (PORT-18, PORT-21) -------------------------------------------------


func test_the_cache_is_used_before_any_network_and_a_broken_one_is_ignored() -> void:
	_setup("catalog_cache")
	_http.text[URL] = _text([_port("alpha"), _port("beta"), _port("gamma")])
	var ports := _make(false)
	ports.refresh()
	_drop(ports)
	check(FileAccess.file_exists(_cache()), "cached (PORT-21)")
	check(not FileAccess.file_exists(_cache() + ".tmp"), "no temp file left")
	eq(FileAccess.get_file_as_string(_cache()), _http.text[URL], "the fetched text")
	_http.offline = true
	_http.requests.clear()
	ports = _make(true)
	eq(ports.list(), ["alpha", "beta", "gamma"], "offline: listed from the cache")
	eq(ports.info("gamma").error, "", "no error")
	_drop(ports)
	for broken in ["{nope", _text([_port("x")], 2, 9), "x".repeat(Catalog.MAX_BYTES + 1)]:
		var file := FileAccess.open(_cache(), FileAccess.WRITE)
		file.store_string(broken)
		file.close()
		ports = _make(false)
		eq(ports.list(), ["alpha", "beta"], "a broken cache is ignored")
		_drop(ports)
	remove(_dir)


func test_a_failed_or_bad_fetch_changes_nothing() -> void:
	_setup("catalog_fail")
	_http.text[URL] = _text([_port("alpha"), _port("beta"), _port("gamma")])
	var ports := _make(false)
	ports.refresh()
	var cached := FileAccess.get_file_as_string(_cache())
	for answer in ["offline", "500", "{nope", "future", "big"]:
		_http.offline = answer == "offline"
		_http.status.erase(URL)
		if answer == "500":
			_http.status[URL] = 500
		match answer:
			"{nope":
				_http.text[URL] = "{nope"
			"future":
				_http.text[URL] = _text([_port("zeta")], 9, 2)
			"big":
				_http.text[URL] = "x".repeat(Catalog.MAX_BYTES + 1)
		ports.refresh()
		eq(ports.list(), ["alpha", "beta", "gamma"], "%s: same list (PORT-19)" % answer)
		eq(ports.info("alpha").error, "", "%s: no error" % answer)
		eq(FileAccess.get_file_as_string(_cache()), cached, "%s: cache kept" % answer)
	_free(ports)


func test_the_start_fetch_is_hourly_and_a_failed_one_does_not_count() -> void:
	_setup("catalog_hour")
	_http.offline = true
	var ports := _make(true)
	eq(_catalog_requests(), 1, "fetched at start")
	_drop(ports)
	_http.offline = false
	_http.text[URL] = _text([_port("alpha"), _port("beta")], 1)
	ports = _make(true)
	eq(_catalog_requests(), 2, "the failed fetch did not count")
	_drop(ports)
	ports = _make(true)
	eq(_catalog_requests(), 2, "a moment later: not again")
	_drop(ports)
	var state := State.load_from(_dir.path_join("state/state.ini"))
	eq(state.catalog()["last_check"], NOW, "the time is stored")
	state.set_catalog({"last_check": NOW - 3601})
	ports = _make(true)
	eq(_catalog_requests(), 3, "an hour later it fetches again")
	_drop(ports)
	ports = _make(false)
	ports.refresh()
	eq(_catalog_requests(), 4, "refresh always fetches")
	_free(ports)


# Notice (PORT-23) --------------------------------------------------------------------


func test_the_notice_names_new_ports_and_ones_that_need_a_newer_app() -> void:
	eq(CatalogUpdate.notice(["Foo"], 0), "1 new port: Foo", "one")
	eq(CatalogUpdate.notice(["Foo", "Bar"], 0), "2 new ports: Foo, Bar", "two")
	eq(CatalogUpdate.notice([], 1), "1 port needs a newer Anchorage", "newer only")
	eq(CatalogUpdate.notice(["Foo"], 2), "1 new port: Foo\n2 more need a newer Anchorage", "both")
	eq(CatalogUpdate.notice([], 0), "", "nothing")
	_setup("catalog_newer")
	var future := _port("future", {"rom_place": "cartridge"})
	_http.text[URL] = _text([_port("alpha"), future], 2)
	var ports := _make(false)
	var notices := []
	ports.notice_changed.connect(func() -> void: notices.append(ports.notice()))
	ports.refresh()
	eq(notices, ["1 port needs a newer Anchorage"], "said once")
	ports.refresh()
	eq(notices.size(), 1, "not again for the same catalog version")
	eq(ports.list(), ["alpha", "beta"], "and not listed")
	_free(ports)


# Downloads only from the merged catalog's repos (PORT-13, PORT-22) ----------------------


func test_downloads_come_only_from_the_entrys_own_repo() -> void:
	_setup("catalog_repos")
	_http.text[URL] = _text([_port("alpha"), _port("beta"), _port("gamma")])
	var ports := _make(false)
	ports.refresh()
	_publish("gamma", "test/gamma", "1.0")
	ports.install("gamma")
	check(ports.info("gamma").installed, "a fetched port installs from its own repo")
	ports.remove("gamma")
	for repo in ["test/alpha", "someone/else"]:
		var url := "https://github.com/%s/releases/download/1.0/gamma-Linux.zip" % repo
		_publish("gamma", "test/gamma", "2.0", url)
		_http.requests.clear()
		ports.install("gamma")
		check(not ports.info("gamma").installed, "%s refused for gamma" % repo)
		check(ports.info("gamma").error.contains("unexpected URL"), "says why: %s" % repo)
		check(not url in _http.requests, "never requested: %s" % repo)
		ports.dismiss_error("gamma")
	var outside := _port("outside")
	check(
		not Releases.url_allowed(outside, "https://github.com/test/gamma/releases/download/1/x"),
		"a repo in neither catalog gets nothing from another's"
	)
	for port in ports.catalog:
		check(port["repo"] in ["test/alpha", "test/beta", "test/gamma"], "only catalog repos")
	_free(ports)


func test_the_catalog_url_and_its_test_hook() -> void:
	eq(
		CatalogUpdate.URL,
		"https://raw.githubusercontent.com/DisposableSoftware/anchorage/main/app/data/ports.json",
		"the repository's main branch (PORT-18)"
	)
	for good in [
		"https://raw.githubusercontent.com/someone/anchorage/branch/app/data/ports.json",
		"http://127.0.0.1:8123/ports.json",
	]:
		check(CatalogUpdate.override_allowed(good), good)
	for bad in [
		"https://evil.example/ports.json",
		"https://raw.githubusercontent.com.evil.example/x",
		"https://raw.githubusercontent.com@evil.example/x",
		"http://raw.githubusercontent.com/x",
		"http://127.0.0.1.evil.example:80/x",
		"http://10.0.0.1:80/x",
		"https://raw.githubusercontent.com/a/../../x",
		"file:///etc/passwd",
	]:
		check(not CatalogUpdate.override_allowed(bad), "refused: " + bad)
	check(not CatalogUpdate.override_allowed("http://127.0.0.1:80/x\n"), "no trailing line break")
	eq(CatalogUpdate.url(), CatalogUpdate.URL, "no override in the test run")


# The home screen (PORT-23) -------------------------------------------------------------


## A catalog fetch that adds a port while the home screen is open, over ports_fake.
func test_new_ports_get_a_card_a_toast_and_a_badge_until_focused() -> void:
	Keys.apply({})
	var ports := PortsFake.new("new-ports")
	ports.simulate = false
	var host := Control.new()
	host.theme = Style.build("mocha", "mauve")
	host.add_child(ports)
	var home := HomeScene.instantiate()
	home.ports = ports
	host.add_child(home)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	eq(home.toast_text(), "", "nothing before the fetch")
	var count: int = home.get_node("%Cards").get_child_count()
	ports.add_new_ports()
	var card: Control = home.card_for("township")
	check(card != null, "a card for the new port")
	eq(home.get_node("%Cards").get_child_count(), count + 1, "one more card")
	eq(home.get_node("%Cards").get_children()[-1], card, "at the end of the row")
	eq(home.toast_text(), "1 new port: Township", "the notice as a toast")
	check(card.shows_new(), "a New badge")
	check(not home.card_for("soh").shows_new(), "only on the new one")
	var focus := func() -> Control: return home.get_viewport().gui_get_focus_owner()
	eq(focus.call(), home.card_for("soh"), "focus stays where it was")
	for _i in count:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_RIGHT
			key.physical_keycode = KEY_RIGHT
			key.pressed = pressed
			home.get_viewport().push_input(key)
	eq(focus.call(), card, "the D-pad reaches the new card")
	check(not card.shows_new(), "focused once: the badge goes")
	check(["mark_seen", "township"] in ports.calls, "and Ports is told")
	home._toast._process(home.Toast.SECONDS + 0.1)
	eq(home.toast_text(), "", "the toast goes after a few seconds")
	host.get_parent().remove_child(host)
	host.free()

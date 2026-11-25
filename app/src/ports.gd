extends Node
## The one object screens talk to (PORT-14). The contract is in spec/ports.md
## ("Service contract"); `ports_fake.gd` has the same interface. Everything slow runs off
## the main loop: HTTP through `http.gd`, unpacking and ROM preparation on the worker
## pool, ROM scans on `Roms.ScanJob`, and a launched port is polled, never waited for.
##
## Set the variables below before the node enters the tree; the defaults are the app's.
## Tests pass a temp `root` and `state_path`, `res://tests/fake_http.gd` as `http`, and
## `threaded = false`, so every step completes inside the call that started it.

signal changed(id: String)
signal launched(id: String)
signal exited(id: String)
## The ROM folder changed: `rom_folder_info()` has the new one (ROM-12, ROM-13).
signal rom_folder_changed
## The answer to `browse(path)`, with the folder's listing (ROM-11).
signal folder_listed(path: String, listing: Dictionary)
## `search_info()` changed (ROM-14).
signal search_changed
## A catalog fetch added ports (they are at the end of `list()` already) or found entries
## that need a newer Anchorage: `notice()` says which (PORT-23).
signal notice_changed

const RomFolders := preload("res://src/rom_folders.gd")
const Ini := preload("res://src/ini.gd")
const Catalog := preload("res://src/catalog.gd")
const CatalogUpdate := preload("res://src/catalog_update.gd")
const Releases := preload("res://src/releases.gd")
const Installer := preload("res://src/installer.gd")
const State := preload("res://src/state.gd")
const Http := preload("res://src/http.gd")
const Roms := preload("res://src/roms.gd")
const Launcher := preload("res://src/launcher.gd")
const Art := preload("res://src/art.gd")

const IDLE := {"action": "", "progress": -1.0, "detail": ""}
const VERBS := {"install": "install", "update": "update", "launch": "start", "remove": "remove"}
const POLL_SECONDS := 0.25

## The ports folder; empty means user://ports.
var root := ""
## state.ini; empty means $XDG_STATE_HOME/anchorage/state.ini.
var state_path := ""
## `[roms] directory` as written (CONF-8): one folder or several separated by `;`, `~`
## expanded when used; "" when config.ini sets none, and then the folders are the ones
## chosen in the app (ROM-12, ROM-17) or the one found (ROM-10).
var roms_dir := ""
## config.ini, which the chooser names when it sets the folder (ROM-12).
var config_file := ""
## Where ROM-10 and ROM-14 look; tests pass fake trees. An empty `home` means $HOME.
var home := ""
var media_dir := RomFolders.MEDIA
var mounts_file := RomFolders.MOUNTS_FILE
## `[ports] check_updates` (CONF-9).
var check_updates := true
## Catalog entries; empty means res://data/ports.json. After `_ready` it is the merged list
## in use (PORT-20).
var catalog: Array = []
## The `version` of `catalog` when it is given; read from the file otherwise.
var catalog_version := 0
## Where the catalog is fetched from; empty means `CatalogUpdate.url()` (PORT-18).
var catalog_url := ""
## The fetched catalog's cache; empty means $XDG_CACHE_HOME/anchorage/catalog.json (PORT-21).
var catalog_cache := ""
## Something with http.gd's methods; null means a new http.gd child.
var http: Object = null
## The same for cover art (ART-3). Null means a new http.gd child, unless `http` was given:
## then that one serves the art too, so tests never reach the network.
var art_http: Object = null
## The art cache folder; empty means $XDG_CACHE_HOME/anchorage/art.
var art_dir := ""
var threaded := true
## Unix seconds; empty means the system clock.
var clock := Callable()
## A port that keeps running this long counts as started (PORT-6, PORT-8).
var settle_seconds := 10.0

var _state: RefCounted
var _ports := {}
var _ids: Array[String] = []
var _busy := {}
var _errors := {}
var _offline := {}
var _roms := {}
## "" before the first scan has finished, then the scan's status ("ok" or "missing").
var _scan_status := ""
var _scan_job: RefCounted
var _scan_again := false
## The ROM folders scanned, in order (absolute paths), and where they came from: "config",
## "chosen", "emudeck", "retrodeck", "default", "mount", "search" or "fallback"; "" while
## ROM-10 looks. `_folder` is the first of them.
var _folders: Array[String] = []
var _folder := ""
var _folder_source := ""
## The last scan's word on each folder: path -> {status: "ok"|"missing", ports: count}.
var _folder_scan := {}
## ROM-14: {status: "idle"|"running"|"done"|"no_card"|"cancelled", results}.
var _search := {"status": "idle", "results": []}
var _search_job: RefCounted
## The search ROM-10 started by itself: its first result becomes the folder.
var _search_auto := false
## The running search was cancelled, and a new one is to start once it has stopped.
var _search_cancelled := false
var _search_again := false
## Launches asked for while a scan ran: they start with its result (the first scan at start
## has no ROMs yet).
var _launch_after_scan: Array[String] = []
var _checking := false
## Installs and updates waiting for the one download at a time (PORT-12), and the
## running one: {action, id, installer, cancelled, ended}.
var _queue: Array = []
var _active := {}
## Running ports: id -> {pid, started (msec), settled}.
var _runs := {}
var _poll_left := 0.0
var _art := {}
var _art_loader: RefCounted
var _art_http_given := false
## PORT-23: the last catalog notice, "" before there is one.
var _notice := ""
## The highest catalog version merged so far (PORT-20).
var _version_in_use := 0
## The HTTP object the catalog is fetched with: `http`, or one that may reach 127.0.0.1
## for the ANCHORAGE_CATALOG_URL test hook.
var _catalog_http: Object
var _http_given := false


func _ready() -> void:
	if root.is_empty():
		root = ProjectSettings.globalize_path("user://ports")
	if state_path.is_empty():
		state_path = State.default_path()
	if catalog.is_empty():
		var loaded := Catalog.load_default()
		for error in loaded["errors"]:
			push_warning(error)
		catalog = loaded["ports"]
		catalog_version = loaded["version"]
	_version_in_use = catalog_version
	if catalog_url.is_empty():
		catalog_url = CatalogUpdate.url()
	if catalog_cache.is_empty():
		catalog_cache = CatalogUpdate.default_cache()
	_use_catalog(catalog)
	_merge_cached()
	_http_given = http != null
	if http == null:
		http = Http.new()
		add_child(http)
	if home.is_empty():
		home = OS.get_environment("HOME")
	_state = State.load_from(state_path)
	Installer.cleanup_stale(root)
	set_process(false)
	_pick_folder()
	_start_art(_http_given)
	_check(false)


func _exit_tree() -> void:
	_queue.clear()
	if _scan_job != null:
		_scan_job.finished.disconnect(_on_scanned)
		_scan_job.abort()
		_scan_job.join()
		_scan_job = null
	if _search_job != null:
		_search_job.finished.disconnect(_on_searched)
		_search_job.abort()
		_search_job.join()
		_search_job = null
	if not _active.is_empty() and _active.get("installer") != null:
		_active["cancelled"] = true
		_active["installer"].cancel()


func list() -> Array:
	return _ids.duplicate()


func info(id: String) -> Dictionary:
	var port: Dictionary = _ports[id]
	var installed := _installed(id)
	var version: String = _state.installed_version(id)
	var latest: String = _state.latest_version(id)
	return {
		"id": id,
		"name": port["name"],
		"game": port["game"],
		"monogram": port.get("monogram", ""),
		"description": port["description"],
		"installed": installed,
		"installed_version": version if not (installed and version.is_empty()) else "Unknown",
		"latest_version": latest,
		"update_available": installed and not latest.is_empty() and version != latest,
		"offline": _offline.get(id, false),
		"rom": _rom_info(port),
		"busy": _busy.get(id, IDLE).duplicate(),
		"running": _runs.has(id),
		"first_run": port.get("first_run", "") if not Launcher.extracted(root, port) else "",
		"art": _art.get(id),
		"error": _errors.get(id, ""),
		"is_new": id in _state.catalog()["new"],
	}


## PORT-23: what the last catalog fetch brought, e.g. "2 new ports: Foo, Bar".
func notice() -> String:
	return _notice


## PORT-23: the port's card has been focused, so it is no longer new.
func mark_seen(id: String) -> void:
	var marked: Array = _state.catalog()["new"]
	if _ports.has(id) and id in marked:
		marked.erase(id)
		_state.set_catalog({"new": marked})
		changed.emit(id)


func install(id: String) -> void:
	if _ports.has(id) and not _installed(id):
		_enqueue("install", id)


func update(id: String) -> void:
	if _ports.has(id) and _installed(id):
		_enqueue("update", id)


## PORT-7. Never while the port is busy or running.
func remove(id: String) -> void:
	if not _ports.has(id) or _is_busy(id) or not _installed(id):
		return
	_errors.erase(id)
	_busy[id] = {"action": "remove", "progress": -1.0, "detail": ""}
	changed.emit(id)
	_offload(
		Installer.remove.bind(root, id),
		func(result: Dictionary) -> void:
			_busy.erase(id)
			if result["ok"]:
				_state.clear_installed(id)
			else:
				_errors[id] = _error_text("remove", id, result["error"])
			changed.emit(id),
		{"ok": false, "error": "Deleting stopped with an internal error"}
	)


func launch(id: String) -> void:
	if not _ports.has(id) or _is_busy(id) or not _installed(id):
		return
	_errors.erase(id)
	if _scan_job != null or _folder_source.is_empty():
		_busy[id] = {"action": "launch", "progress": -1.0, "detail": "Looking for ROMs"}
		_launch_after_scan.append(id)
		changed.emit(id)
		return
	_prepare_launch(id)


## Places the ROM and the extra files on the worker pool, then starts the port (PORT-9).
func _prepare_launch(id: String) -> void:
	_busy[id] = {"action": "launch", "progress": -1.0, "detail": "Getting ready"}
	changed.emit(id)
	var port: Dictionary = _ports[id]
	_offload(
		Launcher.prepare.bind(
			root,
			port,
			_roms.get(id, {}),
			_archive_current(id),
			_state.placed_rom(id),
			_folders.duplicate()
		),
		func(result: Dictionary) -> void: _on_prepared(id, result),
		{
			"ok": false,
			"error": "Getting ready stopped with an internal error",
			"placed": "",
			"args": []
		}
	)


func cancel(id: String) -> void:
	for job in _queue:
		if job["id"] == id:
			_queue.erase(job)
			_busy.erase(id)
			changed.emit(id)
			return
	if _active.get("id") != id or _active["cancelled"]:
		return
	_active["cancelled"] = true
	if _active["installer"] != null:
		_busy[id] = {"action": _active["action"], "progress": -1.0, "detail": "Cancelling"}
		changed.emit(id)
		_active["installer"].cancel()
	else:
		_end_job(_active)


## HOME-6: always fetches the catalog (PORT-18), checks for updates (PORT-5) and rescans
## the ROM folder (ROM-5).
func refresh() -> void:
	_check(true)
	_scan()


func dismiss_error(id: String) -> void:
	if _errors.erase(id):
		changed.emit(id)


# The ROM folders (ROM-10 .. ROM-17) -----------------------------------------------------


## {path (as shown, `~` for home), full, source, locked (config.ini sets it), config_file,
## folders: [{path, full, source, status, ports}], chosen: [paths]}; `path`, `full` and
## `source` are the first folder's (spec/ports.md, "Service contract").
func rom_folder_info() -> Dictionary:
	var folders := []
	for dir in _folders:
		var folder := {"path": RomFolders.display(dir, home), "full": dir, "source": _folder_source}
		folder.merge({"status": "", "ports": 0}.merged(_folder_scan.get(dir, {}), true))
		folders.append(folder)
	return {
		"path": RomFolders.display(_folder, home),
		"full": _folder,
		"source": _folder_source,
		"locked": not roms_dir.is_empty(),
		"config_file": RomFolders.display(config_file, home),
		"folders": folders,
		"chosen": _state.rom_dirs(),
	}


## ROM-12, ROM-13, ROM-17: adds the folder to the chosen ones in state.ini and rescans.
## Does nothing while config.ini sets the folders (CONF-3: Anchorage never writes
## config.ini) or when the folder is chosen already.
func set_rom_folder(path: String) -> void:
	if not roms_dir.is_empty() or not path.is_absolute_path():
		return
	var dir := path.simplify_path()
	var chosen: Array[String] = _state.rom_dirs()
	if dir in chosen:
		return
	_search_auto = false
	if chosen.is_empty() and _found_folder_in_use():
		# The first choice keeps the found folder's games found (ROM-10, ROM-17).
		chosen.append(_folder)
	if not dir in chosen:
		chosen.append(dir)
	_state.set_rom_dirs(chosen)
	_use_folders(chosen, "chosen")


## ROM-17: removes a chosen folder and rescans the others; with none left, ROM-10 looks
## for a folder again.
func remove_rom_folder(path: String) -> void:
	var chosen: Array[String] = _state.rom_dirs()
	if not roms_dir.is_empty() or not path in chosen:
		return
	chosen.erase(path)
	_state.set_rom_dirs(chosen)
	if not chosen.is_empty():
		_use_folders(chosen, "chosen")
		return
	_folders = []
	_folder = ""
	_folder_source = ""
	_folder_scan = {}
	_scan_status = ""
	rom_folder_changed.emit()
	_emit_all()
	_pick_folder()


## The folder ROM-10 found is in use and a port takes its ROM from it.
func _found_folder_in_use() -> bool:
	if _folder_source in ["", "config", "chosen", "fallback"] or _folders.size() != 1:
		return false
	return _folder_scan.get(_folder, {}).get("ports", 0) > 0


## Lists `path` (the ROM folder when empty) on the worker pool; `folder_listed` answers.
func browse(path: String) -> void:
	var dir := path if not path.is_empty() else (_folder if not _folder.is_empty() else home)
	var where := [home, media_dir, mounts_file]
	_offload(
		func() -> Dictionary:
			return RomFolders.list_folder(dir, where[0], where[1], RomFolders.read_mounts(where[2])),
		func(listing: Dictionary) -> void: folder_listed.emit(path, listing),
		{"ok": false, "path": dir, "roms": 0, "folders": [], "places": []}
	)


## ROM-14: looks for ROM folders on the SD card and other drives, on a worker thread.
func search_sd_card() -> void:
	_search_auto = false
	_start_search(false)


func cancel_search() -> void:
	if _search_job != null:
		_search_cancelled = true
		_search_again = false
		_search_job.abort()


## {status: "idle"|"running"|"done"|"no_card"|"cancelled", results: [{path, display,
## label (the drive), folder (the path on it), roms}]}.
func search_info() -> Dictionary:
	return _search.duplicate(true)


func _pick_folder() -> void:
	if not roms_dir.is_empty():
		var configured: Array[String] = []
		for item in Ini.split_list(roms_dir):
			configured.append(Roms.expand_dir(item))
		_use_folders(configured, "config")
		return
	if not _state.rom_dirs().is_empty():
		_use_folders(_state.rom_dirs(), "chosen")
		return
	var where := [home, media_dir, mounts_file]
	_offload(
		func() -> Dictionary:
			var found := RomFolders.detect(where[0], where[1], RomFolders.read_mounts(where[2]))
			if found["path"].is_empty():
				found = {"path": RomFolders.fallback(where[0]), "source": "fallback"}
			return found,
		_on_detected,
		{"path": RomFolders.fallback(home), "source": "fallback"}
	)


func _on_detected(found: Dictionary) -> void:
	if not _folder_source.is_empty():
		return
	_use_folder(found["path"], found["source"])
	if found["source"] == "fallback":
		_start_search(true)


func _use_folder(path: String, source: String) -> void:
	_use_folders([path], source)


func _use_folders(paths: Array, source: String) -> void:
	_folders.assign(paths)
	_folder = _folders[0] if not _folders.is_empty() else ""
	_folder_source = source
	rom_folder_changed.emit()
	_scan()


func _start_search(auto: bool) -> void:
	if _search_job != null:
		# A cancelled search may still be stopping: search again once it has.
		_search_again = _search_again or _search_cancelled
		return
	_search_auto = auto
	_search_cancelled = false
	_search_again = false
	_search = {"status": "running", "results": []}
	search_changed.emit()
	if not threaded:
		var mounts := RomFolders.mounts(media_dir, RomFolders.read_mounts(mounts_file))
		_on_searched(RomFolders.search(mounts))
		return
	_search_job = RomFolders.SearchJob.new()
	_search_job.finished.connect(_on_searched)
	_search_job.start(media_dir, mounts_file)


func _on_searched(result: Dictionary) -> void:
	_search_job = null
	if _search_again:
		_start_search(false)
		return
	var statuses := {"ok": "done", "no_card": "no_card", "aborted": "cancelled"}
	var results := []
	for entry in result.get("results", []):
		var shown: Dictionary = entry.duplicate()
		shown["display"] = RomFolders.display(entry["path"], home)
		results.append(shown)
	_search = {"status": statuses.get(result.get("status"), "done"), "results": results}
	search_changed.emit()
	if _search_auto and _folder_source == "fallback" and not results.is_empty():
		_use_folder(results[0]["path"], "search")
	_search_auto = false


## Checks the running ports; `_process` calls it every POLL_SECONDS. Public for tests.
func poll() -> void:
	for id in _runs.keys():
		var run: Dictionary = _runs[id]
		var elapsed: float = (Time.get_ticks_msec() - int(run["started"])) / 1000.0
		if OS.is_process_running(run["pid"]):
			if not run["settled"] and elapsed >= settle_seconds:
				run["settled"] = true
				_offload(Installer.cleanup_previous.bind(root, id), func(_r: Variant) -> void: pass)
			continue
		var code := OS.get_process_exit_code(run["pid"])
		_runs.erase(id)
		var after := Launcher.after_exit(
			root, _ports[id], _state.placed_rom(id), _folders, run["unix"], run["settled"]
		)
		if after["archive_current"]:
			_state.set_archive_version(id, _state.installed_version(id))
		_state.set_placed_rom(id, after["placed"])
		if code != 0 and elapsed < settle_seconds:
			var detail := "It stopped after %d s with exit code %d." % [ceili(elapsed), code]
			var line := Launcher.last_line(Launcher.log_path(root, id))
			if not line.is_empty():
				detail += " " + line
			_errors[id] = _error_text("launch", id, detail)
		changed.emit(id)
		exited.emit(id)
	if _runs.is_empty():
		set_process(false)


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_SECONDS
		poll()


func _installed(id: String) -> bool:
	return FileAccess.file_exists(Launcher.executable(root, _ports[id]))


func _is_busy(id: String) -> bool:
	return _busy.has(id) or _runs.has(id)


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


func _error_text(action: String, id: String, detail: String) -> String:
	return "Could not %s “%s”\n%s" % [VERBS[action], _ports[id]["name"], detail]


## ROM-9: the matched file, or what the port takes and where Anchorage looked. A port
## whose archive exists needs no ROM.
## PORT-9: the archive was made (or kept) by the installed version, so no ROM is needed.
func _archive_current(id: String) -> bool:
	var version: String = _state.installed_version(id)
	return (
		not version.is_empty()
		and _state.archive_version(id) == version
		and Launcher.extracted(root, _ports[id])
	)


func _rom_info(port: Dictionary) -> Dictionary:
	var wanted: Array[String] = []
	for rom in port["roms"]:
		if not rom["label"] in wanted:
			wanted.append(rom["label"])
	var match: Dictionary = _roms.get(port["id"], {})
	if match.get("found", false):
		var entry: String = match.get("entry", "")
		var label: String = entry.get_file() if not entry.is_empty() else match["path"].get_file()
		return {"found": true, "label": label, "path": match["path"], "wanted": wanted}
	if _archive_current(port["id"]):
		return {
			"found": true, "label": "Not needed, already extracted", "path": "", "wanted": wanted
		}
	var label := "No matching ROM"
	if _scan_status.is_empty():
		label = "Looking for ROMs"
	elif _scan_status == "missing":
		label = "ROM folder not found"
	return {"found": false, "label": label, "path": _looked_in(), "wanted": wanted}


## ROM-9: the folders scanned, as config.ini writes them or with `~`, comma separated; with
## several, a missing one is marked.
func _looked_in() -> String:
	var written := Array(Ini.split_list(roms_dir)) if not roms_dir.is_empty() else []
	var shown: Array[String] = []
	for i in _folders.size():
		var text: String = (
			written[i] if i < written.size() else RomFolders.display(_folders[i], home)
		)
		if _folders.size() > 1 and _folder_scan.get(_folders[i], {}).get("status") == "missing":
			text += " (not found)"
		shown.append(text)
	return ", ".join(shown)


func _emit_all() -> void:
	for id in _ids:
		changed.emit(id)


# Cover art ---------------------------------------------------------------------------


## ART-3: in the background, one file at a time, on its own HTTP object so it never waits
## for or blocks a port download.
func _start_art(http_was_given: bool) -> void:
	_art_http_given = http_was_given
	_fetch_art(_ids)


func _fetch_art(ids: Array) -> void:
	var items := []
	for id in ids:
		var port: Dictionary = _ports[id]
		if port.has("art"):
			items.append({"id": id, "url": port["art"]["url"]})
	if items.is_empty():
		return
	if _art_loader != null:
		_art_loader.fetch(items, _on_art)
		return
	if art_http == null:
		if _art_http_given:
			art_http = http
		else:
			art_http = Http.new()
			art_http.redirect_check = Art.url_allowed
			add_child(art_http)
	if art_dir.is_empty():
		art_dir = OS.get_cache_dir().path_join("anchorage").path_join("art")
	_art_loader = Art.new(art_http, art_dir)
	_art_loader.offload = _offload
	_art_loader.fetch(items, _on_art)


func _on_art(id: String, texture: Texture2D) -> void:
	_art[id] = texture
	changed.emit(id)


# Installs and updates ----------------------------------------------------------------


func _enqueue(action: String, id: String) -> void:
	if _is_busy(id):
		return
	_errors.erase(id)
	_queue.append({"action": action, "id": id, "installer": null, "cancelled": false})
	_busy[id] = {"action": action, "progress": -1.0, "detail": ""}
	changed.emit(id)
	_next_job()


func _next_job() -> void:
	if _active.is_empty() and not _queue.is_empty():
		_active = _queue.pop_front()
		_active["ended"] = false
		var job := _active
		var id: String = job["id"]
		_busy[id] = {"action": job["action"], "progress": -1.0, "detail": "Looking for the release"}
		changed.emit(id)
		Releases.fetch_latest(
			http, _ports[id], func(result: Dictionary) -> void: _on_release(job, result)
		)
	if _active.is_empty():
		return
	for job in _queue:
		var waiting := "Waiting for %s" % _ports[_active["id"]]["name"]
		if _busy[job["id"]]["detail"] != waiting:
			_busy[job["id"]]["detail"] = waiting
			changed.emit(job["id"])


func _on_release(job: Dictionary, result: Dictionary) -> void:
	if job["cancelled"] or job["ended"]:
		return
	var id: String = job["id"]
	_offline[id] = result.get("offline", false)
	if not result["ok"]:
		var detail: String = result.get("error", "")
		if result.get("offline", false):
			detail = "GitHub could not be reached: %s" % detail
		_fail(job, detail)
		return
	var release: Dictionary = result["release"]
	_state.set_latest(id, release["tag"])
	if job["action"] == "update" and release["tag"] == _state.installed_version(id):
		_end_job(job)
		return
	var installer := Installer.new(root, http)
	installer.threaded = threaded
	job["installer"] = installer
	var progress := func(stage: String, got: int, total: int) -> void:
		_on_progress(job, stage, got, total)
	var done := func(r: Dictionary) -> void: _on_installed(job, r)
	if job["action"] == "install":
		installer.install(_ports[id], release, progress, done)
	else:
		installer.update(_ports[id], release, progress, done)


## Progress in whole percent, with the bytes shown at that percent, so `changed` fires at
## most about a hundred times per download instead of for every chunk (HOME-13).
func _on_progress(job: Dictionary, stage: String, got: int, total: int) -> void:
	if job["cancelled"] or job["ended"]:
		return
	var busy := {"action": job["action"], "progress": -1.0, "detail": ""}
	match stage:
		"download":
			if total > 0:
				var percent := clampi(floori(100.0 * got / total), 0, 100)
				busy["progress"] = percent / 100.0
				var shown := int(total * percent / 100.0)
				busy["detail"] = "%s of %s" % [_megabytes(shown), _megabytes(total)]
			else:
				busy["detail"] = _megabytes(got - got % 1_000_000)
		"unpack":
			busy["detail"] = "Unpacking"
		_:
			busy["detail"] = "Finishing"
	if _busy.get(job["id"]) == busy:
		return
	_busy[job["id"]] = busy
	changed.emit(job["id"])


func _on_installed(job: Dictionary, result: Dictionary) -> void:
	if job["ended"]:
		return
	var id: String = job["id"]
	if result["ok"]:
		_state.set_installed(id, result["version"])
		_end_job(job)
		_scan()
	elif result.get("cancelled", false) or job["cancelled"]:
		_end_job(job)
	else:
		_fail(job, result["error"])


func _fail(job: Dictionary, detail: String) -> void:
	_errors[job["id"]] = _error_text(job["action"], job["id"], detail)
	_end_job(job)


func _end_job(job: Dictionary) -> void:
	if job["ended"]:
		return
	job["ended"] = true
	if _active == job:
		_active = {}
	_busy.erase(job["id"])
	changed.emit(job["id"])
	_next_job()


static func _megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1e6)


# Launching ---------------------------------------------------------------------------


func _on_prepared(id: String, result: Dictionary) -> void:
	if not result["ok"]:
		_busy.erase(id)
		_errors[id] = _error_text("launch", id, result["error"])
		changed.emit(id)
		return
	_state.set_placed_rom(id, result["placed"])
	var started := Launcher.start(root, _ports[id], {}, result["args"])
	_busy.erase(id)
	if started["pid"] <= 0:
		_errors[id] = _error_text("launch", id, started["error"])
		changed.emit(id)
		return
	_runs[id] = {
		"pid": started["pid"],
		"started": Time.get_ticks_msec(),
		"unix": int(Time.get_unix_time_from_system()),
		"settled": false,
	}
	_poll_left = POLL_SECONDS
	set_process(true)
	changed.emit(id)
	launched.emit(id)


# ROM scans and update checks -----------------------------------------------------------


## ROM-4, ROM-5: one scan at a time; a request during a scan runs another one after it.
func _scan() -> void:
	# While ROM-10 still looks there is no folder yet; it scans when it has one.
	if _folder_source.is_empty():
		return
	if _scan_job != null:
		_scan_again = true
		return
	var dirs := _folders.duplicate()
	var hashes := {}
	for port in catalog:
		hashes[port["id"]] = port["roms"]
	if not threaded:
		_on_scanned(Roms.scan_all(dirs, hashes, _state.rom_cache()))
		return
	_scan_job = Roms.ScanJob.new()
	_scan_job.finished.connect(_on_scanned)
	_scan_job.start(dirs, hashes, _state.rom_cache())


## A port's match changes only here, from a scan of the whole folder list (ROM-17).
func _on_scanned(result: Dictionary) -> void:
	_scan_job = null
	if result["dirs"] != _folders:
		# The folders changed during the scan (ROM-13): only the new list's result counts.
		_scan_again = false
		_scan()
		return
	_scan_status = result["status"]
	_roms = result["matches"]
	# An unmounted SD card is "missing": keep the cache for when it is back.
	if _scan_status == "ok" and result["cache"] != _state.rom_cache():
		_state.set_rom_cache(result["cache"])
	var seen := {}
	for folder: Dictionary in result["folders"]:
		var status: String = "missing" if folder["status"] == "missing" else "ok"
		seen[folder["path"]] = {"status": status, "ports": folder["ports"].size()}
	if seen != _folder_scan:
		_folder_scan = seen
		rom_folder_changed.emit()
	_emit_all()
	var waiting := _launch_after_scan
	_launch_after_scan = []
	for id in waiting:
		_prepare_launch(id)
	if _scan_again:
		_scan_again = false
		_scan()


## PORT-18, PORT-5: fetches the catalog, then asks GitHub about every port; a failed answer
## marks that port offline. At start (`manual` false) each runs only when due; `refresh`
## runs both.
func _check(manual: bool) -> void:
	if _checking:
		return
	var updates := Releases.check_due(_state.last_check(), _now(), check_updates, manual)
	var last_fetch: int = _state.catalog()["last_check"]
	var fetch := Releases.check_due(last_fetch, _now(), check_updates, manual)
	if not (updates or fetch):
		return
	_checking = true
	if not fetch:
		_check_releases()
		return
	CatalogUpdate.fetch(
		_catalog_client(),
		catalog_url,
		func(result: Dictionary) -> void:
			_on_catalog(result)
			if updates:
				_check_releases()
			else:
				_checking = false
	)


func _check_releases() -> void:
	Releases.check_all(http, _state, catalog, _now(), _on_checked)


func _on_checked(results: Dictionary) -> void:
	_checking = false
	for id in results:
		_offline[id] = not results[id]["ok"] and results[id].get("offline", false)
	_emit_all()


# The catalog (PORT-18 .. PORT-23) ----------------------------------------------------


func _use_catalog(ports: Array) -> void:
	catalog = ports
	_ports = {}
	_ids = []
	for port in catalog:
		_ports[port["id"]] = port
		_ids.append(port["id"])


## PORT-21: the last fetched catalog, before any network. Dropping a port the newer
## catalog no longer lists happens only here, at start, and never to an installed one.
func _merge_cached() -> void:
	var cached := CatalogUpdate.read_cache(catalog_cache)
	if not cached["ok"]:
		if FileAccess.file_exists(catalog_cache):
			push_warning("%s ignored: %s" % [catalog_cache, "; ".join(cached["errors"])])
		return
	var merged := Catalog.merge(
		catalog, _version_in_use, cached["ports"], cached["version"], _installed
	)
	_version_in_use = maxi(_version_in_use, cached["version"])
	_use_catalog(merged["ports"])


func _catalog_client() -> Object:
	if _http_given or not catalog_url.begins_with("http://"):
		return http
	if _catalog_http == null:
		_catalog_http = Http.new()
		_catalog_http.allow_http = true
		add_child(_catalog_http)
	return _catalog_http


## PORT-19, PORT-20, PORT-23: a fetched catalog is cached and merged; ports are only ever
## appended here, and the ones added are new until focused. A failed fetch changes nothing.
func _on_catalog(result: Dictionary) -> void:
	if not result["ok"]:
		push_warning("The port catalog was not updated: %s" % result["error"])
		return
	var fetched: Dictionary = result["catalog"]
	for error in fetched["errors"]:
		push_warning(error)
	CatalogUpdate.write_cache(catalog_cache, result["text"])
	var marks: Dictionary = _state.catalog()
	var merged := Catalog.merge(
		catalog,
		_version_in_use,
		fetched["ports"],
		fetched["version"],
		func(_id: String) -> bool: return true
	)
	_version_in_use = maxi(_version_in_use, fetched["version"])
	_use_catalog(merged["ports"])
	var added: Array = merged["added"]
	var changed_ids: Array = added + merged["replaced"]
	for id in merged["replaced"]:
		if not _ports[id].has("art"):
			_art.erase(id)
	if not changed_ids.is_empty():
		_fetch_art(changed_ids)
		_scan()
	var newer := 0
	if fetched["version"] > marks["version"]:
		for id in fetched["newer"]:
			if not _ports.has(id):
				newer += 1
	(
		_state
		. set_catalog(
			{
				"last_check": _now(),
				"version": maxi(marks["version"], fetched["version"]),
				"new": marks["new"] + added,
			}
		)
	)
	var names := []
	for id in added:
		names.append(_ports[id]["name"])
	var text := CatalogUpdate.notice(names, newer)
	for id in merged["replaced"]:
		changed.emit(id)
	if not text.is_empty():
		_notice = text
		notice_changed.emit()


## Runs `work` on the worker pool (inline when not `threaded`) and hands its result to
## `finished` on the main thread. A task that ends without a result of the fallback's type
## (a script error inside it) hands over `fallback`, so nothing stays busy forever.
func _offload(work: Callable, finished: Callable, fallback: Variant = null) -> void:
	if not threaded or not is_inside_tree():
		finished.call(_or_fallback(work.call(), fallback))
		return
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void: box["result"] = work.call())
	_wait_for(task, box, finished, fallback)


func _wait_for(task: int, box: Dictionary, finished: Callable, fallback: Variant) -> void:
	if WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		finished.call(_or_fallback(box.get("result"), fallback))
		return
	get_tree().create_timer(0.05).timeout.connect(_wait_for.bind(task, box, finished, fallback))


static func _or_fallback(result: Variant, fallback: Variant) -> Variant:
	if fallback != null and typeof(result) != typeof(fallback):
		return fallback
	return result

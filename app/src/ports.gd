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

const Catalog := preload("res://src/catalog.gd")
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
## `[roms] directory` as written (CONF-8); `~` is expanded when scanning.
var roms_dir := "~/Roms/n64"
## `[ports] check_updates` (CONF-9).
var check_updates := true
## Catalog entries; empty means res://data/ports.json.
var catalog: Array = []
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
	for port in catalog:
		_ports[port["id"]] = port
		_ids.append(port["id"])
	var injected := http != null
	if http == null:
		http = Http.new()
		add_child(http)
	_state = State.load_from(state_path)
	Installer.cleanup_stale(root)
	set_process(false)
	_scan()
	_start_art(injected)
	if Releases.check_due(_state.last_check(), _now(), check_updates):
		_check()


func _exit_tree() -> void:
	_queue.clear()
	if _scan_job != null:
		_scan_job.finished.disconnect(_on_scanned)
		_scan_job.join()
		_scan_job = null
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
		"description": port["description"],
		"installed": installed,
		"installed_version": version if not (installed and version.is_empty()) else "Unknown",
		"latest_version": latest,
		"update_available": installed and not latest.is_empty() and version != latest,
		"offline": _offline.get(id, false),
		"rom": _rom_info(port),
		"busy": _busy.get(id, IDLE).duplicate(),
		"running": _runs.has(id),
		"art": _art.get(id),
		"error": _errors.get(id, ""),
	}


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
	var result := Installer.remove(root, id)
	if result["ok"]:
		_state.clear_installed(id)
	else:
		_errors[id] = _error_text("remove", id, result["error"])
	changed.emit(id)


func launch(id: String) -> void:
	if not _ports.has(id) or _is_busy(id) or not _installed(id):
		return
	_errors.erase(id)
	_busy[id] = {"action": "launch", "progress": -1.0, "detail": "Getting ready"}
	changed.emit(id)
	var port: Dictionary = _ports[id]
	_offload(
		Launcher.prepare.bind(root, port, _roms.get(id, {})),
		func(result: Dictionary) -> void: _on_prepared(id, result),
		{"ok": false, "error": "Getting ready stopped with an internal error", "placed": ""}
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


## HOME-6: always checks for updates (PORT-5) and rescans the ROM folder (ROM-5).
func refresh() -> void:
	_check()
	_scan()


func dismiss_error(id: String) -> void:
	if _errors.erase(id):
		changed.emit(id)


## Checks the running ports; `_process` calls it every POLL_SECONDS. Public for tests.
func poll() -> void:
	for id in _runs.keys():
		var run: Dictionary = _runs[id]
		var elapsed: float = (Time.get_ticks_msec() - int(run["started"])) / 1000.0
		if OS.is_process_running(run["pid"]):
			if not run["settled"] and elapsed >= settle_seconds:
				run["settled"] = true
				Installer.cleanup_previous(root, id)
			continue
		var code := OS.get_process_exit_code(run["pid"])
		_runs.erase(id)
		Launcher.after_exit(root, _ports[id])
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
	if Launcher.extracted(root, port):
		return {
			"found": true, "label": "Not needed, already extracted", "path": "", "wanted": wanted
		}
	var label := "No matching ROM"
	if _scan_status.is_empty():
		label = "Looking for ROMs"
	elif _scan_status == "missing":
		label = "ROM folder not found"
	return {"found": false, "label": label, "path": roms_dir, "wanted": wanted}


func _emit_all() -> void:
	for id in _ids:
		changed.emit(id)


# Cover art ---------------------------------------------------------------------------


## ART-3: in the background, one file at a time, on its own HTTP object so it never waits
## for or blocks a port download.
func _start_art(http_was_given: bool) -> void:
	var items := []
	for port in catalog:
		if port.has("art"):
			items.append({"id": port["id"], "url": port["art"]["url"]})
	if items.is_empty():
		return
	if art_http == null:
		if http_was_given:
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


func _on_progress(job: Dictionary, stage: String, got: int, total: int) -> void:
	if job["cancelled"] or job["ended"]:
		return
	var busy := {"action": job["action"], "progress": -1.0, "detail": ""}
	match stage:
		"download":
			if total > 0:
				busy["progress"] = clampf(float(got) / total, 0.0, 1.0)
				busy["detail"] = "%s of %s" % [_megabytes(got), _megabytes(total)]
			else:
				busy["detail"] = _megabytes(got)
		"unpack":
			busy["detail"] = "Unpacking"
		_:
			busy["detail"] = "Finishing"
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
	var started := Launcher.start(root, _ports[id])
	_busy.erase(id)
	if started["pid"] <= 0:
		_errors[id] = _error_text("launch", id, started["error"])
		changed.emit(id)
		return
	_runs[id] = {"pid": started["pid"], "started": Time.get_ticks_msec(), "settled": false}
	_poll_left = POLL_SECONDS
	set_process(true)
	changed.emit(id)
	launched.emit(id)


# ROM scans and update checks -----------------------------------------------------------


## ROM-4, ROM-5: one scan at a time; a request during a scan runs another one after it.
func _scan() -> void:
	if _scan_job != null:
		_scan_again = true
		return
	var dir := Roms.expand_dir(roms_dir)
	var hashes := {}
	for port in catalog:
		hashes[port["id"]] = port["roms"]
	if not threaded:
		_on_scanned(Roms.scan(dir, hashes, _state.rom_cache()))
		return
	_scan_job = Roms.ScanJob.new()
	_scan_job.finished.connect(_on_scanned)
	_scan_job.start(dir, hashes, _state.rom_cache())


func _on_scanned(result: Dictionary) -> void:
	_scan_job = null
	_scan_status = result["status"]
	_roms = result["matches"]
	# An unmounted SD card is "missing": keep the cache for when it is back.
	if _scan_status == "ok" and result["cache"] != _state.rom_cache():
		_state.set_rom_cache(result["cache"])
	_emit_all()
	if _scan_again:
		_scan_again = false
		_scan()


## PORT-5: asks GitHub about every port; a failed answer marks that port offline.
func _check() -> void:
	if _checking:
		return
	_checking = true
	Releases.check_all(http, _state, catalog, _now(), _on_checked)


func _on_checked(results: Dictionary) -> void:
	_checking = false
	for id in results:
		_offline[id] = not results[id]["ok"] and results[id].get("offline", false)
	_emit_all()


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

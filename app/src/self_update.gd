extends Node
## Updating Anchorage's own AppImage from Game Mode (UPD-1 .. UPD-10, spec/update.md).
## main.gd adds one next to Ports and hands it to the home screen (`home.self_update`);
## with the fake ports it adds `self_update_fake.gd`, which has the same interface:
##
##   info() -> {state, version, current, progress, detail, error, blocked}
##       state: "unsupported" (not run from an AppImage: UPD-1), "none" (nothing newer
##       known), "available", "waiting" (for the ports: UPD-8), "downloading", "verifying",
##       "ready" (swapped in, a restart starts it: UPD-9) or "failed" (`error` says why, and
##       the update can be started again). `version` is the newer version, "" when none.
##   check(manual)          UPD-2: at start (`manual` false: hourly, `check_updates`) or now
##   start()                UPD-4 .. UPD-8: looks the release up again, downloads, checks, swaps
##   cancel()               stops a wait, a download or a check; the AppImage stays as it is
##   restart() -> String    UPD-9: "" once the new copy waits for this process to end
##   signal changed         info() changed
##
## Set the variables below before the node enters the tree; the defaults are the app's.
## Nothing here touches the ports, their data or their state (UPD-8), and nothing of a
## release is read but its tag, assets, sizes and digests (UPD-10).

signal changed

const Http := preload("res://src/http.gd")
const Ini := preload("res://src/ini.gd")
const Launcher := preload("res://src/launcher.gd")
const Releases := preload("res://src/releases.gd")

const API := "https://api.github.com/repos/DisposableSoftware/anchorage/releases/latest"
const DOWNLOADS := "https://github.com/DisposableSoftware/anchorage/releases/download/%s/%s"
const HOOK := "ANCHORAGE_RELEASES_URL"
const LOCAL_ORIGIN := "^(http://127\\.0\\.0\\.1:[0-9]{1,5})/[A-Za-z0-9._/-]*$"
const SUMS := "SHA256SUMS"
const MAX_BYTES := 200 * 1024 * 1024
const SUMS_MAX_BYTES := 64 * 1024
## Room kept free beside the download and the copy of the old file.
const SPARE_BYTES := 16 * 1024 * 1024
## A `.new` this old at start is left over from an update that never finished (UPD-6); a
## younger one may be another Anchorage's download.
const STALE_SECONDS := 600
const MODE := 0x1ED
const ERROR_TITLE := "Could not update “Anchorage”"
const BLOCKED_TEXT := "Finish what is running first"
## $1 the process to wait for, then the command to run once it has ended. Gives up after
## about a minute, so a process that never quits never gets a second copy beside it.
const WAIT_SCRIPT := """pid=$1
shift
n=0
while kill -0 "$pid" 2>/dev/null; do
  n=$((n + 1))
  [ "$n" -le 300 ] || exit 1
  sleep 0.2
done
exec "$@"
"""

## The running AppImage (UPD-1): the runtime sets APPIMAGE to its real path.
var appimage := OS.get_environment("APPIMAGE")
## Anchorage's own version.
var version := str(ProjectSettings.get_setting("application/config/version", ""))
## Something with http.gd's methods; null means a new http.gd child of its own, so a port
## download never waits for this one.
var http: Object = null
## The `releases/latest` URL; empty means API, or the test hook (HOOK) when it is valid.
var api_url := ""
## Where the last check is remembered (UPD-2): its time and the newest version it found.
var memory_path := default_memory()
## `[ports] check_updates` (CONF-9).
var check_updates := true
## Unix seconds; empty means the system clock.
var clock := Callable()
var threaded := true
var smoke_seconds := 10.0
var settle_seconds := 10.0
## A program the new AppImage is handed to (with its arguments first) instead of being run
## itself; empty runs it. Tests set one: a host with an AppImage binfmt handler (NixOS)
## hands every file with the AppImage magic to appimage-run.
var smoke_runner := PackedStringArray()
## The ports service: while any port is busy or running nothing starts or swaps (UPD-8).
var ports: Object = null
## Replaces that rule when valid (tests).
var blocked := Callable()
## The installer's record (INT-33); empty means where install-steamos.sh keeps it.
var record_path := ""
## The environment a restarted copy inherits from; empty means Anchorage's own.
var base_env := {}

var _supported := false
var _state := "unsupported"
var _newer := ""
var _progress := -1.0
var _detail := ""
var _error := ""
var _checking := false
## The running update: {cancelled, stage ("start" or "swap" while waiting), release,
## sha256, pid}.
var _job := {}
## "http://127.0.0.1:<port>" while the test hook is in use, else "".
var _origin := ""


func _ready() -> void:
	set_process(false)
	_supported = supported(appimage)
	if not _supported:
		return
	_state = "none"
	if api_url.is_empty():
		api_url = hook_url(OS.get_environment(HOOK))
	_origin = local_origin(api_url)
	if http == null:
		http = Http.new()
		http.allow_http = not _origin.is_empty()
		add_child(http)
	if record_path.is_empty():
		record_path = default_record()
	var known := _known()
	if newer(known["latest"], version):
		_newer = known["latest"]
		_state = "available"
	_tidy_up()
	check(false)


func info() -> Dictionary:
	return {
		"state": _state,
		"version": _newer,
		"current": version,
		"progress": _progress,
		"detail": _detail,
		"error": _error,
		"blocked": _is_blocked(),
	}


## UPD-2. A failed check changes nothing and shows nothing.
func check(manual := false) -> void:
	if not _supported or _checking or not _state in ["none", "available", "failed"]:
		return
	var known := _known()
	if not Releases.check_due(known["last_check"], _now(), check_updates, manual):
		return
	_checking = true
	_fetch_release(
		func(result: Dictionary) -> void:
			_checking = false
			if result["ok"] and _state in ["none", "available", "failed"]:
				_found(result)
	)


## UPD-4, UPD-8: waits while a port is busy or running, then starts.
func start() -> void:
	if not _supported or not _state in ["available", "failed"]:
		return
	_error = ""
	_job = {"cancelled": false, "stage": "start"}
	if _is_blocked():
		_to("waiting", -1.0, BLOCKED_TEXT)
		set_process(true)
		return
	_begin(_job)


func cancel() -> void:
	if _job.is_empty() or _job.get("stage") == "swapping":
		return
	_job["cancelled"] = true
	if _state == "downloading":
		http.cancel_download()
	if int(_job.get("pid", 0)) > 0:
		OS.kill(_job["pid"])
	_remove(new_path(appimage))
	_job = {}
	set_process(false)
	_to("available" if not _newer.is_empty() else "none", -1.0, "")


## UPD-9: starts the new AppImage once this process has ended. The caller quits.
func restart() -> String:
	if _state != "ready":
		return "There is no new version to start"
	if _is_blocked():
		return BLOCKED_TEXT
	var base := base_env if not base_env.is_empty() else Launcher.current_environment()
	var args := restart_command(
		OS.get_process_id(),
		appimage,
		base,
		OS.get_user_data_dir().path_join("restart.log"),
		OS.get_cmdline_args(),
		OS.get_cmdline_user_args()
	)
	if OS.create_process(Launcher.SHELL, args) <= 0:
		return "Could not run %s" % Launcher.SHELL
	return ""


func _process(_delta: float) -> void:
	if _state != "waiting" or _job.is_empty() or _is_blocked():
		return
	set_process(false)
	if _job["stage"] == "swap":
		_swap(_job)
	else:
		_begin(_job)


# The pure parts ------------------------------------------------------------------------


## UPD-1: an existing file the user may write, in a folder the user may write.
static func supported(path: String) -> bool:
	if path.is_empty() or not path.is_absolute_path() or not FileAccess.file_exists(path):
		return false
	if FileAccess.get_unix_permissions(path) & FileAccess.UNIX_WRITE_OWNER == 0:
		return false
	var probe := path.get_base_dir().path_join(".anchorage-write-check-%d" % OS.get_process_id())
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


static func new_path(path: String) -> String:
	return path + ".new"


static func previous_path(path: String) -> String:
	return path + ".previous"


## $XDG_STATE_HOME/anchorage/self-update.ini, beside state.ini.
static func default_memory() -> String:
	var base := OS.get_environment("XDG_STATE_HOME")
	if base.is_empty() or not base.is_absolute_path():
		base = OS.get_environment("HOME").path_join(".local/state")
	return base.path_join("anchorage").path_join("self-update.ini")


## Where install-steamos.sh keeps its record: `${XDG_STATE_HOME:-$HOME/.local/state}`, and
## `$HOME/.local/state` when that is not absolute.
static func default_record() -> String:
	var home := OS.get_environment("HOME")
	if home != "/":
		home = home.trim_suffix("/")
	var base := OS.get_environment("XDG_STATE_HOME")
	if not base.begins_with("/"):
		base = home + "/.local/state"
	return base + "/anchorage-installer/files.sha256"


## The test hook when it is a plain local URL, else the real API.
static func hook_url(value: String) -> String:
	return value if not local_origin(value).is_empty() else API


static func local_origin(url: String) -> String:
	var found := RegEx.create_from_string(LOCAL_ORIGIN).search(url)
	if found == null or url.contains(".."):
		return ""
	return found.get_string(1)


## [major, minor, patch] of `X.Y.Z` or `vX.Y.Z`; empty for anything else (a prerelease too).
static func parse_version(text: String) -> PackedInt32Array:
	var found := RegEx.create_from_string("^v?([0-9]{1,6})\\.([0-9]{1,6})\\.([0-9]{1,6})$").search(
		text
	)
	if found == null:
		return PackedInt32Array()
	return PackedInt32Array(
		[int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))]
	)


## UPD-2: compared as numbers, so 0.10.0 is newer than 0.9.0.
static func newer(candidate: String, current: String) -> bool:
	var a := parse_version(candidate)
	var b := parse_version(current)
	if a.is_empty() or b.is_empty():
		return false
	for i in 3:
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## The `releases/latest` answer: {ok, error, newer, version, release: {tag, asset: {name,
## url, size, sha256}, sums: {url}}}. Only the tag, the assets' names, URLs, sizes and
## digests are read (UPD-10). `origin` is the test hook's, or "" for GitHub.
static func parse_release(data: Variant, own: String, origin := "") -> Dictionary:
	if not (data is Dictionary and data.get("tag_name") is String and data.get("assets") is Array):
		return {"ok": false, "error": "Unexpected answer from GitHub"}
	if data.get("draft") == true or data.get("prerelease") == true:
		return {"ok": true, "newer": false, "version": ""}
	var tag: String = data["tag_name"]
	var parts := parse_version(tag)
	if parts.is_empty():
		return {"ok": true, "newer": false, "version": ""}
	var found := "%d.%d.%d" % [parts[0], parts[1], parts[2]]
	if not newer(found, own):
		return {"ok": true, "newer": false, "version": found}
	var name := "Anchorage-%s-x86_64.AppImage" % found
	var assets := {}
	for asset in data["assets"]:
		if asset is Dictionary and asset.get("name") in [name, SUMS]:
			if assets.has(asset["name"]):
				return {"ok": false, "error": "Release %s lists %s twice" % [tag, asset["name"]]}
			assets[asset["name"]] = asset
	for wanted in [name, SUMS]:
		if not assets.has(wanted):
			return {"ok": false, "error": "Release %s has no %s" % [tag, wanted]}
		var url: Variant = assets[wanted].get("browser_download_url")
		if not (url is String and asset_url_ok(url, tag, wanted, origin)):
			return {"ok": false, "error": "Release %s has %s at an unexpected URL" % [tag, wanted]}
	var app: Dictionary = assets[name]
	var size := int(app.get("size", 0)) if app.get("size") is float or app.get("size") is int else 0
	if size <= 0 or size > MAX_BYTES:
		return {"ok": false, "error": "Release %s lists an AppImage of %d bytes" % [tag, size]}
	var sha256 := ""
	var digest: Variant = app.get("digest")
	if digest is String and (digest as String).to_lower().begins_with("sha256:"):
		sha256 = (digest as String).substr(7).to_lower()
		if not RegEx.create_from_string("^[0-9a-f]{64}$").search(sha256):
			return {"ok": false, "error": "Release %s lists a broken digest" % tag}
	return {
		"ok": true,
		"newer": true,
		"version": found,
		"release":
		{
			"tag": tag,
			"asset":
			{"name": name, "url": app["browser_download_url"], "size": size, "sha256": sha256},
			"sums": {"url": assets[SUMS]["browser_download_url"]},
		},
	}


## UPD-4: exactly the release download of this repository, or with the test hook a file on
## its own origin.
static func asset_url_ok(url: String, tag: String, name: String, origin := "") -> bool:
	if origin.is_empty():
		return url == DOWNLOADS % [tag, name]
	return local_origin(url) == origin and url.ends_with("/" + name)


## The hash SHA256SUMS lists for `name`, "" when none or more than one differ.
static func sums_hash(text: String, name: String) -> String:
	var line := RegEx.create_from_string("^([0-9a-fA-F]{64}) [ *](.+)$")
	var found := ""
	for raw in text.split("\n"):
		var m := line.search(raw.strip_edges(false, true))
		if m == null or m.get_string(2) != name:
			continue
		var hash := m.get_string(1).to_lower()
		if not found.is_empty() and found != hash:
			return ""
		found = hash
	return found


## UPD-4, UPD-5 on the downloaded file: size, checksum, ELF and AppImage type 2 magic, and
## the executable bit. "" when it passes, else why not.
static func verify(path: String, size: int, sha256: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "The download is missing"
	var length := file.get_length()
	var head := file.get_buffer(16)
	file.close()
	if length != size or length > MAX_BYTES:
		return "The download has %d bytes, the release lists %d" % [length, size]
	if FileAccess.get_sha256(path) != sha256:
		return "The download does not match its checksum"
	if head.slice(0, 4) != PackedByteArray([0x7F, 0x45, 0x4C, 0x46]):
		return "The download is not a Linux program"
	if head.slice(8, 11) != PackedByteArray([0x41, 0x49, 0x02]):
		return "The download is not an AppImage"
	FileAccess.set_unix_permissions(path, MODE)
	if FileAccess.get_unix_permissions(path) & FileAccess.UNIX_EXECUTE_OWNER == 0:
		return "The download could not be made executable"
	return ""


## UPD-6, UPD-7: copies the AppImage to `.previous`, renames `.new` over it (one rename, so
## the path holds the old file or the new one, never a part), then updates the installer's
## record. "" when it worked; on a failure the AppImage is the old one.
static func swap(path: String, record: String, sha256: String) -> String:
	var fresh := new_path(path)
	var previous := previous_path(path)
	if FileAccess.get_sha256(fresh) != sha256:
		return "The checked download is gone"
	var old := FileAccess.get_sha256(path)
	_remove(previous)
	var err := DirAccess.copy_absolute(path, previous, MODE)
	if err != OK:
		_remove(previous)
		return "Could not keep a copy of the running version: %s" % error_string(err)
	_sync([fresh, previous])
	err = DirAccess.rename_absolute(fresh, path)
	if err != OK:
		_remove(previous)
		return "Could not replace %s: %s" % [path, error_string(err)]
	update_record(record, path, old, sha256)
	_sync([path.get_base_dir(), record], false)
	return ""


## UPD-7: the installer's lines are "<sha256>  <path>". The one for this file that still
## holds the replaced file's hash gets the new hash; every other byte stays. A line under
## another path counts when that path is now the new file (a HOME behind a symlink). True
## when the record changed.
static func update_record(record: String, path: String, old: String, sha256: String) -> bool:
	if old == sha256 or not FileAccess.file_exists(record):
		return false
	var lines := FileAccess.get_file_as_string(record).split("\n")
	var line := RegEx.create_from_string("^([0-9a-f]{64})  (/.*)$")
	var changed_any := false
	for i in lines.size():
		var m := line.search(lines[i])
		if m == null or m.get_string(1) != old:
			continue
		var named := m.get_string(2)
		if named != path:
			if named.get_file() != path.get_file() or not FileAccess.file_exists(named):
				continue
			if FileAccess.get_sha256(named) != sha256:
				continue
		lines[i] = "%s  %s" % [sha256, named]
		changed_any = true
	if not changed_any:
		return false
	var tmp := record + ".anchorage-self-update"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("%s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string("\n".join(lines))
	file.close()
	if DirAccess.rename_absolute(tmp, record) != OK:
		_remove(tmp)
		push_warning("Could not update %s" % record)
		return false
	return true


## At start, when `.previous` is still there: a swap whose record update a power loss cut
## off is finished (UPD-7).
static func recover_record(record: String, path: String) -> bool:
	var previous := previous_path(path)
	if not FileAccess.file_exists(previous) or not FileAccess.file_exists(path):
		return false
	return update_record(record, path, FileAccess.get_sha256(previous), FileAccess.get_sha256(path))


## UPD-9: /bin/sh waits for `pid` to end, then the launcher's script (PORT-15) starts
## `program` with `base` minus the AppImage runtime's variables, with the same arguments.
static func restart_command(
	pid: int,
	program: String,
	base: Dictionary,
	log_file: String,
	args: PackedStringArray,
	user_args: PackedStringArray
) -> PackedStringArray:
	var env := Launcher.clean_environment(base)
	# Set by the user, not by the runtime: a copy that needed it needs it again.
	if base.has("APPIMAGE_EXTRACT_AND_RUN"):
		env["APPIMAGE_EXTRACT_AND_RUN"] = base["APPIMAGE_EXTRACT_AND_RUN"]
	var cwd := str(base.get("OWD", ""))
	if cwd.is_empty() or not DirAccess.dir_exists_absolute(cwd):
		cwd = str(base.get("HOME", "/"))
	var all := Array(args)
	if not user_args.is_empty():
		all += ["--"] + Array(user_args)
	var out := PackedStringArray(["-c", WAIT_SCRIPT, "anchorage-restart", str(pid), Launcher.SHELL])
	out.append_array(Launcher.shell_args(base, env, cwd, log_file, program, all))
	return out


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Flushes `paths` to the disk (`sync FILE...`), so a power loss after the rename finds
## whole files. Waits up to 30 s when `wait`; failures do not matter.
static func _sync(paths: Array, wait := true) -> void:
	var args := PackedStringArray(["-c", 'sync -- "$@" 2>/dev/null; exit 0', "sync"])
	args.append_array(PackedStringArray(paths))
	var pid := OS.create_process(Launcher.SHELL, args)
	var left := 3000
	while wait and pid > 0 and OS.is_process_running(pid) and left > 0:
		OS.delay_msec(10)
		left -= 1


# The update, step by step ------------------------------------------------------------------


func _known() -> Dictionary:
	var text := FileAccess.get_file_as_string(memory_path) if not memory_path.is_empty() else ""
	var own: Dictionary = Ini.parse(text).get("anchorage", {})
	var last: String = own.get("last_check", "")
	var latest: String = own.get("latest", "")
	return {
		"last_check": int(last) if last.is_valid_int() else 0,
		"latest": latest if not parse_version(latest).is_empty() else "",
	}


## Written to a temp file and renamed over, like state.ini.
func _remember(latest: String) -> void:
	if memory_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(memory_path.get_base_dir())
	var tmp := memory_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(
		(
			"# Anchorage's own update check (UPD-2). Safe to delete.\n[anchorage]\n"
			+ "last_check = %d\nlatest = %s\n" % [_now(), latest]
		)
	)
	file.close()
	if DirAccess.rename_absolute(tmp, memory_path) != OK:
		_remove(tmp)


func _found(result: Dictionary) -> void:
	_remember(result["version"])
	if result["newer"]:
		_newer = result["version"]
		if _state == "none":
			_to("available", -1.0, "")
		else:
			changed.emit()
	elif _state != "none":
		_newer = ""
		_error = ""
		_to("none", -1.0, "")


func _fetch_release(done: Callable) -> void:
	http.fetch_json(
		api_url,
		func(res: Dictionary) -> void:
			if not res.get("ok", false):
				done.call(
					{"ok": false, "error": "GitHub could not be reached: %s" % res.get("error", "")}
				)
				return
			done.call(parse_release(res.get("data"), version, _origin))
	)


func _begin(job: Dictionary) -> void:
	_to("downloading", -1.0, "Looking for the release")
	_fetch_release(
		func(result: Dictionary) -> void:
			if job["cancelled"]:
				return
			if not result["ok"]:
				_fail(job, result["error"])
				return
			_found(result)
			if not result["newer"]:
				_job = {}
				return
			job["release"] = result["release"]
			var room := _room_for(result["release"]["asset"]["size"])
			if not room.is_empty():
				_fail(job, room)
				return
			http.fetch_text(
				result["release"]["sums"]["url"],
				SUMS_MAX_BYTES,
				func(res: Dictionary) -> void: _on_sums(job, res)
			)
	)


func _room_for(size: int) -> String:
	var dir := DirAccess.open(appimage.get_base_dir())
	if dir == null:
		return ""
	var own := FileAccess.open(appimage, FileAccess.READ)
	var need := size + (own.get_length() if own != null else size) + SPARE_BYTES
	if dir.get_space_left() < need:
		return "Not enough free space: the update needs %s" % _megabytes(need)
	return ""


func _on_sums(job: Dictionary, res: Dictionary) -> void:
	if job["cancelled"]:
		return
	var asset: Dictionary = job["release"]["asset"]
	if not res.get("ok", false):
		_fail(job, "Could not download %s: %s" % [SUMS, res.get("error", "")])
		return
	var want := sums_hash(res["text"], asset["name"])
	if want.is_empty():
		_fail(job, "%s has no line for %s" % [SUMS, asset["name"]])
		return
	if not asset["sha256"].is_empty() and asset["sha256"] != want:
		_fail(job, "%s and GitHub list different checksums" % SUMS)
		return
	job["sha256"] = want
	var dest := new_path(appimage)
	_remove(dest)
	_to("downloading", 0.0, "")
	http.download(
		asset["url"],
		dest,
		func(got: int, total: int) -> void: _on_progress(job, got, total),
		func(r: Dictionary) -> void: _on_downloaded(job, r),
		asset["size"]
	)


func _on_progress(job: Dictionary, got: int, total: int) -> void:
	if job["cancelled"] or _state != "downloading":
		return
	var size: int = job["release"]["asset"]["size"]
	var percent := clampi(floori(100.0 * got / maxi(total if total > 0 else size, 1)), 0, 100)
	var detail := "%s of %s" % [_megabytes(int(size * percent / 100.0)), _megabytes(size)]
	if percent / 100.0 != _progress or detail != _detail:
		_to("downloading", percent / 100.0, detail)


func _on_downloaded(job: Dictionary, res: Dictionary) -> void:
	if job["cancelled"]:
		return
	if not res.get("ok", false):
		_fail(job, "The download stopped: %s" % res.get("error", ""))
		return
	_to("verifying", -1.0, "Checking the download")
	var asset: Dictionary = job["release"]["asset"]
	_offload(
		verify.bind(new_path(appimage), asset["size"], job["sha256"]),
		func(err: String) -> void:
			if job["cancelled"]:
				return
			if not err.is_empty():
				_fail(job, err)
			else:
				_smoke(job),
		"The check stopped with an internal error"
	)


## UPD-5: the new AppImage must answer `--appimage-version` with status 0 in time. It runs
## through the launcher's script, so it gets none of this AppImage's variables (PORT-15).
func _smoke(job: Dictionary) -> void:
	_to("verifying", -1.0, "Trying the new version")
	var base := base_env if not base_env.is_empty() else Launcher.current_environment()
	var program := new_path(appimage)
	var program_args := ["--appimage-version"]
	if not smoke_runner.is_empty():
		program_args = Array(smoke_runner.slice(1)) + [program] + program_args
		program = smoke_runner[0]
	var args := Launcher.shell_args(
		base,
		Launcher.clean_environment(base),
		appimage.get_base_dir(),
		"/dev/null",
		program,
		program_args
	)
	var pid := OS.create_process(Launcher.SHELL, args)
	if pid <= 0:
		_fail(job, "Could not run %s" % Launcher.SHELL)
		return
	job["pid"] = pid
	_wait_smoke(job, Time.get_ticks_msec())


func _wait_smoke(job: Dictionary, started: int) -> void:
	if job["cancelled"]:
		return
	var pid: int = job["pid"]
	if OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > smoke_seconds * 1000.0:
			OS.kill(pid)
			job["pid"] = 0
			_fail(job, "The new version did not answer within %d s" % ceili(smoke_seconds))
			return
		get_tree().create_timer(0.05).timeout.connect(_wait_smoke.bind(job, started))
		return
	job["pid"] = 0
	var code := OS.get_process_exit_code(pid)
	if code != 0:
		_fail(job, "The new version does not start (exit code %d)" % code)
		return
	_swap(job)


func _swap(job: Dictionary) -> void:
	if job["cancelled"]:
		return
	if _is_blocked():
		job["stage"] = "swap"
		_to("waiting", -1.0, BLOCKED_TEXT)
		set_process(true)
		return
	job["stage"] = "swapping"
	_to("verifying", -1.0, "Replacing the old version")
	_offload(
		swap.bind(appimage, record_path, job["sha256"]),
		func(err: String) -> void:
			if not err.is_empty():
				_fail(job, err)
				return
			_job = {}
			_to("ready", -1.0, ""),
		"Replacing stopped with an internal error"
	)


func _fail(job: Dictionary, detail: String) -> void:
	job["cancelled"] = true
	if job.get("stage") != "swapping":
		_remove(new_path(appimage))
	_job = {}
	set_process(false)
	_error = "%s\n%s" % [ERROR_TITLE, detail]
	_to("failed" if not _newer.is_empty() else "none", -1.0, "")


func _to(next: String, progress: float, detail: String) -> void:
	_state = next
	_progress = progress
	_detail = detail
	changed.emit()


func _is_blocked() -> bool:
	if blocked.is_valid():
		return bool(blocked.call())
	return ports != null and busy(ports)


## UPD-8: a port installing, updating, removing, starting or running, through the screens'
## own interface (PORT-14).
static func busy(service: Object) -> bool:
	for id in service.list():
		var port: Dictionary = service.info(id)
		if port["running"] or not str(port["busy"]["action"]).is_empty():
			return true
	return false


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


## UPD-6 at start: a leftover `.new` goes, and so does `.previous` once this copy has run
## for `settle_seconds` (after the record of a cut-off swap is finished).
func _tidy_up() -> void:
	var fresh := new_path(appimage)
	if FileAccess.file_exists(fresh):
		if _now() - FileAccess.get_modified_time(fresh) > STALE_SECONDS:
			_remove(fresh)
	if not FileAccess.file_exists(previous_path(appimage)):
		return
	var path := appimage
	var record := record_path
	_offload(
		func() -> bool: return recover_record(record, path),
		func(_changed: bool) -> void:
			if settle_seconds <= 0.0 or not is_inside_tree():
				_remove(previous_path(path))
			else:
				get_tree().create_timer(settle_seconds).timeout.connect(
					func() -> void: _remove(previous_path(path))
				),
		false
	)


static func _megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1e6)


## As Ports does: `work` on the worker pool (inline when not `threaded`), its result to
## `finished` on the main thread; `fallback` when the task ends without one.
func _offload(work: Callable, finished: Callable, fallback: Variant) -> void:
	if not threaded or not is_inside_tree():
		var result: Variant = work.call()
		finished.call(result if typeof(result) == typeof(fallback) else fallback)
		return
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void: box["result"] = work.call())
	_wait_for(task, box, finished, fallback)


func _wait_for(task: int, box: Dictionary, finished: Callable, fallback: Variant) -> void:
	if WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		var result: Variant = box.get("result")
		finished.call(result if typeof(result) == typeof(fallback) else fallback)
		return
	get_tree().create_timer(0.05).timeout.connect(_wait_for.bind(task, box, finished, fallback))

extends RefCounted
## Install, update and remove a port on disk (PORT-3, PORT-4, PORT-6, PORT-7, PORT-10).
##
## Layout under `root` (the app passes `user://ports`):
##   <id>/download/   the download and the unpacked new version, while one is in progress
##   <id>/current/    the installed version
##   <id>/previous/   the version before the last update, until `cleanup_previous`
##   <id>/data/       saves, config, generated archives: never touched by this file's
##                    delete functions
##
## API (everything asynchronous takes callbacks and returns at once):
##   var installer := Installer.new(root, http)      one per operation, `http` is http.gd
##   installer.install(port, release, progress, done)
##   installer.update(port, release, progress, done)  same code path: a present `current/`
##                                                    moves to `previous/`
##   installer.cancel()                               stops a running install or update
##   Installer.remove(root, id) -> {ok, error}
##   Installer.cleanup_previous(root, id)             call 10 s after a launch (PORT-6)
##   Installer.cleanup_stale(root) -> int             call at start (PORT-12)
##   Installer.copy_extra_files(port, from, data, only_missing) -> error   PORT-9, PORT-10
## `port` is a catalog entry and `release` a `Releases` release. `progress` is called as
## progress(stage, done, total) with stage "download" (bytes), "unpack" or "finish" (0/1).
## `done` gets {ok, cancelled, error, version}; `error` is plain text for the UI's detail
## line. A failed or cancelled run leaves `current/` as it was and removes `download/`.

const Releases := preload("res://src/releases.gd")
const EXECUTABLE_MODE := 493  # rwxr-xr-x

## Unpack on a worker thread (the app). Tests turn it off to run inline.
var threaded := true

var _root: String
var _http: Object
var _busy := false
var _cancelled := false
var _progress := Callable()
var _done := Callable()


func _init(root: String, http: Object) -> void:
	_root = root
	_http = http


static func port_dir(root: String, id: String) -> String:
	return root.path_join(id)


static func current_dir(root: String, id: String) -> String:
	return port_dir(root, id).path_join("current")


static func previous_dir(root: String, id: String) -> String:
	return port_dir(root, id).path_join("previous")


static func download_dir(root: String, id: String) -> String:
	return port_dir(root, id).path_join("download")


static func data_dir(root: String, id: String) -> String:
	return port_dir(root, id).path_join("data")


func install(port: Dictionary, release: Dictionary, progress: Callable, done: Callable) -> void:
	_run(port, release, progress, done)


func update(port: Dictionary, release: Dictionary, progress: Callable, done: Callable) -> void:
	_run(port, release, progress, done)


func cancel() -> void:
	if _busy:
		_cancelled = true
		_http.cancel_download()


## PORT-7: deletes the program, never `data/`.
static func remove(root: String, id: String) -> Dictionary:
	for dir in [current_dir(root, id), previous_dir(root, id), download_dir(root, id)]:
		rm_rf(dir)
		if DirAccess.dir_exists_absolute(dir):
			return {"ok": false, "error": "Could not delete %s" % dir}
	return {"ok": true, "error": ""}


## PORT-6: deletes the old version once the new one has run for a while.
static func cleanup_previous(root: String, id: String) -> void:
	rm_rf(previous_dir(root, id))


## Removes `download/` folders left by a killed run, and puts `previous/` back as
## `current/` when a kill came between the two renames of a swap. Returns how many
## folders it dealt with.
static func cleanup_stale(root: String) -> int:
	var count := 0
	if not DirAccess.dir_exists_absolute(root):
		return count
	for id in DirAccess.get_directories_at(root):
		var download := download_dir(root, id)
		if DirAccess.dir_exists_absolute(download):
			rm_rf(download)
			count += 1
		var current := current_dir(root, id)
		var previous := previous_dir(root, id)
		if not DirAccess.dir_exists_absolute(current) and DirAccess.dir_exists_absolute(previous):
			if DirAccess.rename_absolute(previous, current) == OK:
				count += 1
	return count


## Moves `staging` to `<port_dir>/current`, keeping the old `current` as `previous`. When
## the second step fails the first is undone. Returns an error text, empty on success.
static func swap(port_path: String, staging: String) -> String:
	var current := port_path.path_join("current")
	var previous := port_path.path_join("previous")
	var had_current := DirAccess.dir_exists_absolute(current)
	if had_current:
		rm_rf(previous)
		if DirAccess.rename_absolute(current, previous) != OK:
			return "Could not keep the old version"
	if DirAccess.rename_absolute(staging, current) != OK:
		if had_current:
			DirAccess.rename_absolute(previous, current)
		return "Could not put the new version in place"
	return ""


## Deletes a file or a folder with everything in it. Symbolic links are removed, not
## followed.
static func rm_rf(path: String) -> void:
	if _is_link(path) or FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		rm_rf(path.path_join(name))
	DirAccess.remove_absolute(path)


static func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path)


## Unpacks `zip_path` into `dest`. Every entry is checked before anything is written.
## Returns an error text, empty on success.
static func extract_zip(zip_path: String, dest: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download is not a valid zip file"
	var entries := zip.get_files()
	for entry in entries:
		if not safe_entry(entry):
			zip.close()
			return "The zip has an unsafe entry “%s”" % entry
	for entry in entries:
		var target := dest.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			zip.close()
			return "Could not write “%s”" % entry
		file.store_buffer(zip.read_file(entry))
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			zip.close()
			return "Could not write “%s”: %s" % [entry, error_string(write_error)]
	zip.close()
	return ""


## A zip entry name that stays inside the folder it is unpacked to.
static func safe_entry(entry: String) -> bool:
	if entry.is_empty() or entry.begins_with("/") or entry.contains("\\"):
		return false
	if RegEx.create_from_string("^[A-Za-z]:").search(entry) != null:
		return false
	return not ".." in entry.split("/")


func _run(port: Dictionary, release: Dictionary, progress: Callable, done: Callable) -> void:
	if _busy:
		done.call(_failure("Another install is running"))
		return
	var problem := _release_problem(port, release)
	if not problem.is_empty():
		done.call(_failure(problem))
		return
	_busy = true
	_cancelled = false
	_progress = progress
	_done = done
	var id: String = port["id"]
	var download := download_dir(_root, id)
	rm_rf(download)
	if DirAccess.make_dir_recursive_absolute(download) != OK:
		_finish(port, _failure("Could not create %s" % download))
		return
	var asset: Dictionary = release["asset"]
	_report("download", 0, asset["size"])
	_http.download(
		asset["url"],
		download.path_join("asset"),
		func(got: int, total: int) -> void: _report("download", got, total),
		func(result: Dictionary) -> void: _on_downloaded(port, release, result),
		asset["size"]
	)


func _on_downloaded(port: Dictionary, release: Dictionary, result: Dictionary) -> void:
	if _cancelled or result.get("cancelled", false):
		_finish(port, _cancel_result())
		return
	if not result.get("ok", false):
		_finish(port, _failure(str(result.get("error", "The download failed"))))
		return
	var download := download_dir(_root, port["id"])
	var archive := download.path_join("asset")
	var size := _file_size(archive)
	if size != release["asset"]["size"]:
		_finish(
			port,
			_failure(
				(
					"The download is %d bytes but the release says %d"
					% [size, release["asset"]["size"]]
				)
			)
		)
		return
	_report("unpack", 0, 1)
	_offload(
		_unpack.bind(port, archive, release["asset"]["name"], download.path_join("staging")),
		func(error: String) -> void: _on_unpacked(port, release, error)
	)


func _on_unpacked(port: Dictionary, release: Dictionary, error: String) -> void:
	if _cancelled:
		_finish(port, _cancel_result())
		return
	if not error.is_empty():
		_finish(port, _failure(error))
		return
	var staging := download_dir(_root, port["id"]).path_join("staging")
	error = copy_extra_files(port, staging, data_dir(_root, port["id"]))
	if error.is_empty():
		_report("finish", 0, 1)
		error = swap(port_dir(_root, port["id"]), staging)
	if not error.is_empty():
		_finish(port, _failure(error))
		return
	_report("finish", 1, 1)
	_finish(port, {"ok": true, "cancelled": false, "error": "", "version": release["tag"]})


## Runs on a worker thread: touches only files, never a node.
func _unpack(port: Dictionary, archive: String, asset_name: String, staging: String) -> String:
	DirAccess.make_dir_recursive_absolute(staging)
	var executable: String = port["launch"]["executable"]
	if asset_name.to_lower().ends_with(".zip"):
		var error := extract_zip(archive, staging)
		if not error.is_empty():
			return error
	else:
		var target := staging.path_join(executable)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.rename_absolute(archive, target) != OK:
			return "Could not unpack the download"
	var path := staging.path_join(executable)
	if not FileAccess.file_exists(path):
		return "The release does not contain %s" % executable
	FileAccess.set_unix_permissions(path, EXECUTABLE_MODE)
	for extra in port["extra_files"]:
		var extra_path := staging.path_join(extra)
		if not (FileAccess.file_exists(extra_path) or DirAccess.dir_exists_absolute(extra_path)):
			return "The release does not contain %s" % extra
	return ""


## PORT-10: copies the catalog's extra files and folders from `from` (the unpacked release)
## into `data`, named by their last path part. With `only_missing` an extra already in
## `data` is left alone (PORT-9, before a launch). Returns an error text, empty on success.
static func copy_extra_files(
	port: Dictionary, from: String, data: String, only_missing := false
) -> String:
	for extra in port["extra_files"]:
		if DirAccess.make_dir_recursive_absolute(data) != OK:
			return "Could not create %s" % data
		var source := from.path_join(extra)
		var target := data.path_join((extra as String).get_file())
		if (
			only_missing
			and (FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target))
		):
			continue
		if DirAccess.dir_exists_absolute(source):
			rm_rf(target)
			if not copy_tree(source, target):
				return "Could not copy %s" % extra
		elif DirAccess.copy_absolute(source, target) != OK:
			return "Could not copy %s" % extra
	return ""


## Copies the folder `from` to `to` with everything in it. Links are skipped.
static func copy_tree(from: String, to: String) -> bool:
	var dir := DirAccess.open(from)
	if dir == null or DirAccess.make_dir_recursive_absolute(to) != OK:
		return false
	dir.include_hidden = true
	for name in dir.get_files():
		if dir.is_link(from.path_join(name)):
			continue
		if DirAccess.copy_absolute(from.path_join(name), to.path_join(name)) != OK:
			return false
	for name in dir.get_directories():
		if dir.is_link(from.path_join(name)):
			continue
		if not copy_tree(from.path_join(name), to.path_join(name)):
			return false
	return true


func _offload(work: Callable, finished: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not threaded or tree == null:
		finished.call(work.call())
		return
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void: box["result"] = work.call())
	_wait_for(task, box, finished, tree)


func _wait_for(task: int, box: Dictionary, finished: Callable, tree: SceneTree) -> void:
	if WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		finished.call(box["result"])
		return
	tree.create_timer(0.05).timeout.connect(_wait_for.bind(task, box, finished, tree))


func _finish(port: Dictionary, result: Dictionary) -> void:
	rm_rf(download_dir(_root, port["id"]))
	var done := _done
	_busy = false
	_done = Callable()
	_progress = Callable()
	done.call(result)


func _report(stage: String, got: int, total: int) -> void:
	if _progress.is_valid():
		_progress.call(stage, got, total)


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "cancelled": false, "error": error, "version": ""}


static func _cancel_result() -> Dictionary:
	return {"ok": false, "cancelled": true, "error": "Cancelled", "version": ""}


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return -1 if file == null else file.get_length()


## PORT-13: only the catalog repo's release assets.
static func _release_problem(port: Dictionary, release: Dictionary) -> String:
	var asset: Variant = release.get("asset")
	if not (release.get("tag") is String and asset is Dictionary):
		return "No release to install"
	if not (asset.get("url") is String and Releases.url_allowed(port, asset["url"])):
		return "The download is not from the port's release page"
	if not (asset.get("name") is String and asset.get("size") is int and asset["size"] > 0):
		return "The release has no usable download"
	return ""

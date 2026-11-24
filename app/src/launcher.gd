extends RefCounted
## Starting a port (PORT-8, PORT-9, PORT-15, PORT-16). `Ports` calls these and keeps what
## they return in state.ini; nothing here keeps state.
##
##   Launcher.prepare(root, port, rom, archive_current, placed, roms_dir)
##           -> {ok, error, placed, args}
##       Before a launch, on a worker thread: copies missing extra files (PORT-9) and,
##       unless the archive is current, writes the ROM (`rom` is a `Roms.scan` match) where
##       the port looks for it. `placed` in and out is the copy Anchorage wrote ("" when
##       none); `args` is the ROM path for a `rom_place: argv` port while it has no archive.
##   Launcher.start(root, port, base_env := {}, extra_args := []) -> {pid, error}
##       Spawns the port through /bin/sh: working directory, environment and output to
##       `launch.log` (OS.create_process takes neither a directory nor an environment).
##   Launcher.after_exit(root, port, placed, roms_dir, started, settled)
##           -> {archive_current, placed}
##       After a run: whether the run made or kept the archive, and then deletes the copy.
##
## `root` is the ports folder (user://ports, globalized) and `port` a catalog entry.

const Installer := preload("res://src/installer.gd")
const Roms := preload("res://src/roms.gd")

const SHELL := "/bin/sh"
const LOG_NAME := "launch.log"
## $1 working directory, $2 log file, then `-u NAME` / `-e NAME=VALUE` pairs, `--`, and
## the program with its arguments. The log is opened first so a failing `cd` lands in it.
const SCRIPT := """exec >"$2" 2>&1
cd -- "$1" || exit 126
shift 2
while [ "$#" -gt 0 ]; do
  case $1 in
    -u) unset "$2"; shift 2 ;;
    -e) export "$2"; shift 2 ;;
    --) shift; break ;;
    *) exit 125 ;;
  esac
done
exec "$@"
"""
## Variables an AppImage runtime sets for the program it runs (PORT-15).
const APPIMAGE_VARS := ["APPDIR", "APPIMAGE", "ARGV0", "OWD"]
const PATH_VARS := ["LD_LIBRARY_PATH", "LD_PRELOAD", "PATH", "XDG_DATA_DIRS"]
## Names the shell manages itself; changing them could make it exit.
const SHELL_OWNED := ["PWD", "OLDPWD", "SHLVL", "_", "IFS", "PS4", "UID", "EUID", "PPID"]


static func executable(root: String, port: Dictionary) -> String:
	return Installer.current_dir(root, port["id"]).path_join(port["launch"]["executable"])


static func working_dir(root: String, port: Dictionary) -> String:
	if port["launch"]["cwd"] == "current":
		return Installer.current_dir(root, port["id"])
	return Installer.data_dir(root, port["id"])


static func log_path(root: String, id: String) -> String:
	return Installer.port_dir(root, id).path_join(LOG_NAME)


## Where the ROM is written for the port (catalog `rom_place` and `rom_file`): the working
## directory for "cwd", else the data folder ("data_dir", and "argv", PORT-16).
static func rom_target(root: String, port: Dictionary) -> String:
	var dir := Installer.data_dir(root, port["id"])
	if port["rom_place"] == "cwd":
		dir = working_dir(root, port)
	return dir.path_join(port["rom_file"])


## The newest modification time (unix seconds) of the port's archives, 0 when none exists.
static func archive_time(root: String, port: Dictionary) -> int:
	var data := Installer.data_dir(root, port["id"])
	var newest := 0
	for archive in port["archive"]:
		var path := data.path_join(archive)
		if FileAccess.file_exists(path):
			newest = maxi(newest, FileAccess.get_modified_time(path))
	return newest


## True when any of the port's generated archives is in its data folder.
static func extracted(root: String, port: Dictionary) -> bool:
	var data := Installer.data_dir(root, port["id"])
	for archive in port["archive"]:
		if FileAccess.file_exists(data.path_join(archive)):
			return true
	return false


## PORT-15: `env` without what an AppImage runtime added. Unchanged when `APPIMAGE` is not
## set. Entries of the path lists under the mount point (`APPDIR`) are dropped, and a list
## left empty is removed.
static func clean_environment(env: Dictionary) -> Dictionary:
	var out := env.duplicate()
	if not env.has("APPIMAGE"):
		return out
	var mount: String = str(env.get("APPDIR", "")).trim_suffix("/")
	for name in env:
		if name in APPIMAGE_VARS or (name as String).begins_with("APPIMAGE_"):
			out.erase(name)
	for name in PATH_VARS:
		if not out.has(name) or mount.is_empty():
			continue
		var separator := " " if name == "LD_PRELOAD" and not str(out[name]).contains(":") else ":"
		var kept := PackedStringArray()
		for entry in str(out[name]).split(separator, false):
			if entry != mount and not entry.begins_with(mount + "/"):
				kept.append(entry)
		if kept.is_empty():
			out.erase(name)
		else:
			out[name] = separator.join(kept)
	return out


## The environment a port runs with (PORT-8): the cleaned one plus its data folder and
## extract-and-run, so AppImages need no FUSE.
static func port_environment(env: Dictionary, data_dir: String) -> Dictionary:
	var out := clean_environment(env)
	out["SHIP_HOME"] = data_dir
	out["APPIMAGE_EXTRACT_AND_RUN"] = "1"
	return out


## Arguments for /bin/sh: SCRIPT, then what turns `base` (what the shell inherits) into
## `env`, then the program and its arguments.
static func shell_args(
	base: Dictionary, env: Dictionary, cwd: String, log_file: String, program: String, args: Array
) -> PackedStringArray:
	var out := PackedStringArray(["-c", SCRIPT, "anchorage", cwd, log_file])
	var valid := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$")
	var names := base.keys()
	names.sort()
	for name in names:
		if not env.has(name) and valid.search(name) and not name in SHELL_OWNED:
			out.append_array(["-u", name])
	names = env.keys()
	names.sort()
	for name in names:
		if base.get(name) == env[name] or not valid.search(name) or name in SHELL_OWNED:
			continue
		out.append_array(["-e", "%s=%s" % [name, env[name]]])
	out.append("--")
	out.append(program)
	for arg in args:
		out.append(str(arg))
	return out


## Anchorage's environment as a child would inherit it: the start-up environment from
## /proc, with live values for the names PORT-15 and PORT-8 care about.
static func current_environment() -> Dictionary:
	var env := {}
	var file := FileAccess.open("/proc/self/environ", FileAccess.READ)
	if file != null:
		var raw := file.get_buffer(4 << 20)
		file.close()
		# Split the bytes, not a decoded string: decoding stops being exact at the first NUL.
		var start := 0
		while start < raw.size():
			var end := raw.find(0, start)
			if end < 0:
				end = raw.size()
			var item := raw.slice(start, end).get_string_from_utf8()
			start = end + 1
			var eq := item.find("=")
			if eq > 0:
				env[item.left(eq)] = item.substr(eq + 1)
	for name in APPIMAGE_VARS + PATH_VARS + ["SHIP_HOME", "APPIMAGE_EXTRACT_AND_RUN"]:
		if OS.has_environment(name):
			env[name] = OS.get_environment(name)
		else:
			env.erase(name)
	return env


## PORT-9, PORT-16, before a launch. Only touches files, so it can run on a worker thread.
## `archive_current`: the archive was made by the installed version, so no ROM is needed.
## `placed`: the copy Anchorage wrote before (state.ini). `roms_dir`: the ROM folder.
static func prepare(
	root: String,
	port: Dictionary,
	rom: Dictionary,
	archive_current := false,
	placed := "",
	roms_dir := ""
) -> Dictionary:
	var id: String = port["id"]
	var data := Installer.data_dir(root, id)
	var out := {"ok": true, "error": "", "placed": "", "args": []}
	if DirAccess.make_dir_recursive_absolute(data) != OK:
		return {"ok": false, "error": "Could not create %s" % data, "placed": placed, "args": []}
	var error := Installer.copy_extra_files(port, Installer.current_dir(root, id), data, true)
	if not error.is_empty():
		return {"ok": false, "error": error, "placed": placed, "args": []}
	var target := rom_target(root, port)
	var ours := placed == target and FileAccess.file_exists(target)
	if archive_current:
		if ours:
			delete_placed(target, port, root, roms_dir)
		return out
	var rom_path := ""
	if FileAccess.file_exists(target) and not ours:
		# Not written by Anchorage (the user's own copy): left alone, and used.
		rom_path = target
	elif rom.get("found", false) and not str(rom.get("path", "")).is_empty():
		var err := Roms.prepare(rom, target)
		if err == ERR_FILE_CORRUPT:
			var name: String = rom["path"].get_file()
			out["ok"] = false
			out["error"] = "%s changed since it was scanned. Refresh and try again." % name
		elif err != OK:
			out["ok"] = false
			out["error"] = "Could not write the ROM to %s: %s" % [target, error_string(err)]
		else:
			ours = true
			rom_path = target
	elif ours:
		rom_path = target
	out["placed"] = target if ours else ""
	if port["rom_place"] == "argv" and not rom_path.is_empty() and archive_time(root, port) == 0:
		out["args"] = [rom_path]
	return out


## Spawns the port. `base_env` is what the child would inherit (tests pass one); empty
## means Anchorage's own. `extra_args` go after the catalog's (the ROM, PORT-16).
## {pid, error}: pid is 0 when it could not start.
static func start(root: String, port: Dictionary, base_env := {}, extra_args := []) -> Dictionary:
	var program := executable(root, port)
	if not FileAccess.file_exists(program):
		return {"pid": 0, "error": "%s is missing" % program}
	var data := Installer.data_dir(root, port["id"])
	var cwd := working_dir(root, port)
	DirAccess.make_dir_recursive_absolute(data)
	DirAccess.make_dir_recursive_absolute(cwd)
	var base := base_env if not base_env.is_empty() else current_environment()
	var args := shell_args(
		base,
		port_environment(base, data),
		cwd,
		log_path(root, port["id"]),
		program,
		port["launch"]["args"] + extra_args
	)
	var pid := OS.create_process(SHELL, args)
	if pid <= 0:
		return {"pid": 0, "error": "Could not run %s" % SHELL}
	return {"pid": pid, "error": ""}


## When the installed version was unpacked (unix seconds): the installer writes the
## executable then, and nothing writes it later. 0 when it is missing.
static func installed_time(root: String, port: Dictionary) -> int:
	var program := executable(root, port)
	return FileAccess.get_modified_time(program) if FileAccess.file_exists(program) else 0


## PORT-9, after a run that started at `started` (unix seconds) and, if `settled`, kept
## going for the settle time. The archive is now the installed version's when the run ended
## with it there and either wrote it, or settled with an archive no older than the
## installed version (an outdated archive left open in a prompt never counts); then the
## placed copy is deleted. {archive_current, placed}: what is left of Anchorage's copy.
static func after_exit(
	root: String, port: Dictionary, placed: String, roms_dir: String, started: int, settled: bool
) -> Dictionary:
	var made := archive_time(root, port)
	var kept := settled and made >= installed_time(root, port)
	if made == 0 or not (kept or made >= started):
		return {"archive_current": false, "placed": placed}
	if not placed.is_empty() and not delete_placed(placed, port, root, roms_dir):
		return {"archive_current": true, "placed": placed}
	return {"archive_current": true, "placed": ""}


## Deletes the ROM copy at `path` when it is the one Anchorage writes for the port, and it
## does not resolve into the ROM folder (ROM-6). True when it is gone.
static func delete_placed(path: String, port: Dictionary, root: String, roms_dir: String) -> bool:
	if path != rom_target(root, port):
		return false
	if not roms_dir.is_empty() and Roms.same_folder(path, roms_dir.path_join("x")):
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return not FileAccess.file_exists(path)


## The last non-empty line of a log, at most 200 characters, for an error's detail.
## Absolute paths are cut to their file name: they are long (an AppImage's extraction
## folder) and would push the reason off the screen.
static func last_line(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var length := file.get_length()
	file.seek(maxi(length - 4096, 0))
	var text := file.get_buffer(mini(length, 4096)).get_string_from_utf8()
	file.close()
	var lines := text.strip_edges().split("\n", false)
	if lines.is_empty():
		return ""
	var paths := RegEx.create_from_string("(?:/[^\\s/:]+)+/([^\\s/:]+)")
	var line := paths.sub(lines[-1].strip_edges(), "$1", true)
	return line if line.length() <= 200 else line.left(199) + "…"

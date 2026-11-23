extends "res://tests/case.gd"
## PORT-8, PORT-9, PORT-15: the environment and command a port starts with, a fake port
## (a shell script that records what it got) run for real, and ROM placement.

const Launcher := preload("res://src/launcher.gd")
const Installer := preload("res://src/installer.gd")

## Records its environment, working directory and arguments in $SHIP_HOME/record.txt,
## says something on stdout and exits with 3.
const FAKE_PORT := """#!/bin/sh
{
  echo "SHIP_HOME=$SHIP_HOME"
  echo "EXTRACT=$APPIMAGE_EXTRACT_AND_RUN"
  echo "APPDIR=${APPDIR-unset}"
  echo "APPIMAGE=${APPIMAGE-unset}"
  echo "OWD=${OWD-unset}"
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH-unset}"
  echo "PATH=$PATH"
  echo "HOME=$HOME"
  echo "PWD=$(pwd)"
  for a in "$@"; do echo "ARG=$a"; done
} > "$SHIP_HOME/record.txt"
echo "first line"
echo "the port gave up"
exit 3
"""

var _root := ""


func _port(cwd := "data", rom_place := "data_dir") -> Dictionary:
	return {
		"id": "fake",
		"name": "Fake",
		"archive": ["fake.o2r"],
		"launch": {"executable": "fake.appimage", "cwd": cwd, "args": ["--one", "two words"]},
		"extra_files": ["gamecontrollerdb.txt", "assets"],
		"rom_place": rom_place,
		"rom_file": "fake.z64",
	}


## A root with the fake port installed in current/.
func _install(name: String) -> Dictionary:
	_root = temp_dir(name).path_join("ports")
	var port := _port()
	var current := Installer.current_dir(_root, "fake")
	DirAccess.make_dir_recursive_absolute(current.path_join("assets/sub"))
	_write(current.path_join("fake.appimage"), FAKE_PORT)
	FileAccess.set_unix_permissions(current.path_join("fake.appimage"), 493)
	_write(current.path_join("gamecontrollerdb.txt"), "db")
	_write(current.path_join("assets/sub/a.yaml"), "a")
	return port


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Waits up to 5 s for the process to end; its exit code, or -2 on a timeout.
func _wait(pid: int) -> int:
	for _i in 100:
		if not OS.is_process_running(pid):
			return OS.get_process_exit_code(pid)
		OS.delay_msec(50)
	OS.kill(pid)
	return -2


func _record() -> PackedStringArray:
	var path := Installer.data_dir(_root, "fake").path_join("record.txt")
	return FileAccess.get_file_as_string(path).split("\n", false)


func _done() -> void:
	remove(_root.get_base_dir())


func test_clean_environment_drops_what_the_appimage_runtime_added() -> void:
	var mount := "/tmp/.mount_AnchorXYZ"
	var env := {
		"APPIMAGE": "/home/deck/Anchorage.AppImage",
		"APPDIR": mount,
		"ARGV0": "./Anchorage.AppImage",
		"OWD": "/home/deck",
		"APPIMAGE_EXTRACT_AND_RUN": "1",
		"APPIMAGE_SILENT_INSTALL": "1",
		"PATH": mount + "/usr/bin:/usr/bin:" + mount + ":/bin",
		"LD_LIBRARY_PATH": mount + "/usr/lib:" + mount + "/usr/lib64",
		"LD_PRELOAD": "/usr/lib/gameoverlayrenderer.so " + mount + "/usr/lib/libx.so",
		"XDG_DATA_DIRS": mount + "/usr/share:/usr/local/share:/usr/share",
		"HOME": "/home/deck",
		"APPDIRECTORY_NOT_OURS": "kept",
		"MOUNTISH": mount + "x/usr/bin",
	}
	var out := Launcher.clean_environment(env)
	for name in ["APPIMAGE", "APPDIR", "ARGV0", "OWD", "APPIMAGE_SILENT_INSTALL"]:
		check(not out.has(name), "%s removed" % name)
	check(not out.has("APPIMAGE_EXTRACT_AND_RUN"), "APPIMAGE_* removed")
	eq(out.get("PATH"), "/usr/bin:/bin", "PATH entries under the mount dropped")
	check(not out.has("LD_LIBRARY_PATH"), "a list left empty is removed")
	eq(out.get("LD_PRELOAD"), "/usr/lib/gameoverlayrenderer.so", "Steam's overlay stays")
	eq(out.get("XDG_DATA_DIRS"), "/usr/local/share:/usr/share", "XDG_DATA_DIRS")
	eq(out.get("HOME"), "/home/deck", "the rest stays")
	eq(out.get("APPDIRECTORY_NOT_OURS"), "kept", "only the exact names")
	eq(out.get("MOUNTISH"), mount + "x/usr/bin", "other variables are never edited")
	eq(env["APPDIR"], mount, "the input is not changed")


func test_without_an_appimage_the_environment_is_kept() -> void:
	var env := {"APPDIR": "/x", "PATH": "/x/bin:/bin", "LD_LIBRARY_PATH": "/x/lib"}
	eq(Launcher.clean_environment(env), env, "APPIMAGE unset: nothing to scrub")
	var port_env := Launcher.port_environment(env, "/data")
	eq(port_env["SHIP_HOME"], "/data", "SHIP_HOME is the data folder")
	eq(port_env["APPIMAGE_EXTRACT_AND_RUN"], "1", "extract and run")


func test_shell_args_unset_and_export_only_the_differences() -> void:
	var base := {"KEEP": "1", "DROP": "x", "CHANGE": "old", "BAD-NAME": "y", "PWD": "/"}
	var env := {"KEEP": "1", "CHANGE": "new value", "NEW": "n", "BAD-NAME": "z"}
	var args := Launcher.shell_args(base, env, "/cwd", "/log", "/prog", ["a", "b c"])
	eq(args[0], "-c", "sh -c")
	eq(args.slice(2, 5), PackedStringArray(["anchorage", "/cwd", "/log"]), "$0, cwd, log")
	var rest := args.slice(5)
	eq(
		rest,
		PackedStringArray(
			["-u", "DROP", "-e", "CHANGE=new value", "-e", "NEW=n", "--", "/prog", "a", "b c"]
		),
		"unset, export, program; invalid and shell-owned names left alone"
	)


func test_a_fake_port_runs_with_its_environment_folder_and_arguments() -> void:
	var port := _install("launch_run")
	var started := Launcher.start(_root, port)
	eq(started["error"], "", "started")
	check(started["pid"] > 0, "a process id")
	eq(_wait(started["pid"]), 3, "the exit code is the port's own")
	var data := Installer.data_dir(_root, "fake")
	var record := _record()
	check(("SHIP_HOME=" + data) in record, "SHIP_HOME is the data folder: %s" % str(record))
	check("EXTRACT=1" in record, "APPIMAGE_EXTRACT_AND_RUN=1")
	check(("PWD=" + data) in record, "runs in the data folder")
	check(("HOME=" + OS.get_environment("HOME")) in record, "the rest is inherited")
	var args := Array(record).filter(func(l: String) -> bool: return l.begins_with("ARG="))
	eq(args, ["ARG=--one", "ARG=two words"], "the catalog's arguments, one each")
	eq(Launcher.last_line(Launcher.log_path(_root, "fake")), "the port gave up", "output logged")
	_done()


func test_a_port_can_run_in_its_unpacked_folder() -> void:
	_install("launch_current")
	var port := _port("current")
	var started := Launcher.start(_root, port)
	_wait(started["pid"])
	check(("PWD=" + Installer.current_dir(_root, "fake")) in _record(), "cwd current is current/")
	_done()


func test_the_appimage_environment_never_reaches_the_port() -> void:
	var port := _install("launch_appimage")
	var mount := _root.get_base_dir().path_join("mount")
	var saved := {}
	var fake := {
		"APPIMAGE": "/somewhere/Anchorage.AppImage",
		"APPDIR": mount,
		"OWD": "/somewhere",
		"LD_LIBRARY_PATH": mount + "/usr/lib",
		"PATH": mount + "/usr/bin:" + OS.get_environment("PATH"),
	}
	for name in fake:
		saved[name] = OS.get_environment(name) if OS.has_environment(name) else null
		OS.set_environment(name, fake[name])
	var started := Launcher.start(_root, port)
	for name in saved:
		if saved[name] == null:
			OS.unset_environment(name)
		else:
			OS.set_environment(name, saved[name])
	eq(_wait(started["pid"]), 3, "ran")
	var record := _record()
	for line in ["APPDIR=unset", "APPIMAGE=unset", "OWD=unset", "LD_LIBRARY_PATH=unset"]:
		check(line in record, "%s (PORT-15): %s" % [line, str(record)])
	check(("PATH=" + OS.get_environment("PATH")) in record, "the mount left PATH")
	_done()


func test_a_missing_program_does_not_start() -> void:
	var port := _install("launch_missing")
	DirAccess.remove_absolute(Launcher.executable(_root, port))
	var started := Launcher.start(_root, port)
	eq(started["pid"], 0, "no process")
	check(started["error"].contains("fake.appimage"), "names the program")
	_done()


## A tiny "ROM" in v64 (byte-swapped) order; prepare must write it big-endian.
func _v64_rom(dir: String) -> String:
	var v64 := PackedByteArray([0x37, 0x80, 0x40, 0x12, 2, 1, 4, 3])
	var path := dir.path_join("game.v64")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(v64)
	file.close()
	return path


func test_the_rom_is_placed_until_the_archive_exists() -> void:
	var port := _install("launch_rom")
	var rom := {"found": true, "path": _v64_rom(_root.get_base_dir().path_join("roms"))}
	rom.merge({"entry": "", "order": "v64", "label": "US", "sha1": ""})
	var data := Installer.data_dir(_root, "fake")
	var result := Launcher.prepare(_root, port, rom)
	check(result["ok"], "prepared: %s" % result["error"])
	var placed := data.path_join("fake.z64")
	eq(result["placed"], placed, "written where the catalog says")
	eq(
		FileAccess.get_file_as_bytes(placed),
		PackedByteArray([0x80, 0x37, 0x12, 0x40, 1, 2, 3, 4]),
		"as big-endian .z64"
	)
	eq(FileAccess.get_file_as_string(data.path_join("gamecontrollerdb.txt")), "db", "extra file")
	check(FileAccess.file_exists(data.path_join("assets/sub/a.yaml")), "extra folder")
	Launcher.after_exit(_root, port)
	check(FileAccess.file_exists(placed), "kept while the archive is missing")
	_write(data.path_join("fake.o2r"), "o2r")
	Launcher.after_exit(_root, port)
	check(not FileAccess.file_exists(placed), "deleted once the archive exists")
	result = Launcher.prepare(_root, port, rom)
	eq(result["placed"], "", "not placed again when the archive exists")
	check(not FileAccess.file_exists(placed), "still gone")
	_done()


func test_rom_place_cwd_and_no_rom() -> void:
	var port := _install("launch_cwd")
	port["launch"]["cwd"] = "current"
	port["rom_place"] = "cwd"
	eq(
		Launcher.rom_target(_root, port),
		Installer.current_dir(_root, "fake").path_join("fake.z64"),
		"cwd placement follows the working directory"
	)
	var result := Launcher.prepare(_root, port, {"found": false, "path": ""})
	check(result["ok"] and result["placed"] == "", "no ROM: nothing placed, launch goes on")
	_done()


func test_last_line_of_a_log() -> void:
	var dir := temp_dir("launch_log")
	var path := dir.path_join("log")
	_write(path, "one\ntwo\n\n  ")
	eq(Launcher.last_line(path), "two", "last non-empty line")
	_write(path, "x".repeat(300))
	eq(Launcher.last_line(path).length(), 200, "cut to 200 characters")
	eq(Launcher.last_line(dir.path_join("none")), "", "no log")
	_write(
		path,
		(
			"/home/deck/.cache/appimage-run/1a8c73041a2e87d4fb3c202eba443f6c/AppRun: error while"
			+ " loading shared libraries: libgpg-error.so.0: cannot open shared object file\n"
		)
	)
	eq(
		Launcher.last_line(path),
		(
			"AppRun: error while loading shared libraries: libgpg-error.so.0: cannot open"
			+ " shared object file"
		),
		"paths cut to the file name, so the reason shows"
	)
	remove(dir)

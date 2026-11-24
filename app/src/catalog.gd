extends RefCounted
## The port catalog, `res://data/ports.json` (PORT-1, PROD-13). Adding a port is adding an
## entry to that file.
##
## Schema, one object per port in `"ports"` (every key is required unless it says optional):
##   id            short unique name, also the folder name under user://ports/ (a-z, 0-9, _, -)
##   name          display name of the port
##   game          title of the game it plays
##   description   one or two sentences for the detail panel
##   repo          GitHub "owner/name"; releases come from its releases/latest
##   asset_suffix  the Linux release asset is the one whose name ends with this, compared
##                 without case (codenames in asset names change per version)
##   archive       Array of generated archive names (e.g. "oot.o2r"); the port is extracted
##                 when any of them exists
##   launch        {executable, cwd, args}
##                   executable  path inside current/ after unpacking. A bare AppImage asset
##                               is saved under this name; a zip must contain it
##                   cwd         "data" (the port's data folder) or "current" (the unpacked
##                               folder, for ports that read config files next to themselves)
##                   args        Array of arguments (optional, default [])
##   extra_files   Array of paths of files or folders inside the unpacked release that
##                 install copies to the data folder, keeping the last path part as the
##                 name; launch copies them again when missing (optional, default [])
##   rom_place     where the ROM is written: "data_dir" (data folder), "cwd" (the launch
##                 working directory) or "argv" (the data folder, and its path is passed as
##                 an argument while the port has no archive: PORT-16)
##   first_run     a short note for the detail panel until the port has made its archive,
##                 lines split by \n (optional, default "": PORT-17)
##   rom_file      file name of the written ROM, a big-endian ".z64"
##   roms          Array of {label, sha1}: the accepted ROMs. sha1 is 40 lowercase hex
##                 characters of the big-endian data. Order is priority (ROM-7); several
##                 hashes may share one label
##   art           the cover art of the card (ART-1), an object (optional):
##                   url     https URL of a SteamGridDB CDN image (cdn2.steamgriddb.com or
##                           cdn.steamgriddb.com), a horizontal 920x430 grid
##                   author  the artist's name on SteamGridDB
##                   source  the asset's page on steamgriddb.com
##                   style   the SteamGridDB style it was chosen from; the same for every
##                           entry (ART-2)
##               A bad `art` object is reported and dropped; the port stays, with its monogram.
##
## Values from this file are untrusted data to the rest of the code: `parse` drops any
## entry that breaks the schema and reports why.

const Art := preload("res://src/art.gd")

const PATH := "res://data/ports.json"
const ART_KEYS := ["url", "author", "source", "style"]
const ART_SOURCE := "https://www.steamgriddb.com/"
const CWD_VALUES := ["data", "current"]
const ROM_PLACES := ["data_dir", "cwd", "argv"]
const STRING_KEYS := ["id", "name", "game", "description", "repo", "asset_suffix", "rom_file"]


## The shipped catalog: {ports: Array[Dictionary], errors: PackedStringArray}.
static func load_default() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"ports": [], "errors": PackedStringArray([PATH + " is missing"])}
	return parse(FileAccess.get_file_as_string(PATH))


## Valid entries in file order, normalised (optional keys filled in), and a message for
## every problem found.
static func parse(text: String) -> Dictionary:
	var ports := []
	var errors := PackedStringArray()
	var json := JSON.new()
	var data: Variant = json.data if json.parse(text) == OK else null
	if not (data is Dictionary and data.get("ports") is Array):
		errors.append('ports.json: expected an object with a "ports" array')
		return {"ports": ports, "errors": errors}
	var seen := {}
	for raw in data["ports"]:
		var problems := validate(raw)
		var label: String = str(raw.get("id", "?")) if raw is Dictionary else "?"
		if problems.is_empty() and seen.has(raw["id"]):
			problems.append("duplicate id")
		if not problems.is_empty():
			for problem in problems:
				errors.append("ports.json: %s: %s" % [label, problem])
			continue
		seen[raw["id"]] = true
		var port := _normalise(raw)
		if port.has("art"):
			var art_problems := validate_art(port["art"])
			for problem in art_problems:
				errors.append("ports.json: %s: art: %s" % [label, problem])
			if not art_problems.is_empty():
				port.erase("art")
		ports.append(port)
	return {"ports": ports, "errors": errors}


static func find(ports: Array, id: String) -> Dictionary:
	for port in ports:
		if port["id"] == id:
			return port
	return {}


## What is wrong with one raw entry; empty when it is fine.
static func validate(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Dictionary:
		out.append("not an object")
		return out
	for key in STRING_KEYS:
		if not (raw.get(key) is String and not (raw[key] as String).strip_edges().is_empty()):
			out.append("%s must be a non-empty string" % key)
	if raw.get("id") is String and not RegEx.create_from_string("^[a-z0-9_-]+$").search(raw["id"]):
		out.append("id may only have a-z, 0-9, _ and -")
	if (
		raw.get("repo") is String
		and not RegEx.create_from_string("^[\\w.-]+/[\\w.-]+$").search(raw["repo"])
	):
		out.append("repo must look like owner/name")
	if raw.get("rom_file") is String and not (raw["rom_file"] as String).ends_with(".z64"):
		out.append("rom_file must end with .z64")
	if not raw.get("rom_place") in ROM_PLACES:
		out.append("rom_place must be one of %s" % str(ROM_PLACES))
	if raw.has("first_run") and not raw["first_run"] is String:
		out.append("first_run must be a string")
	_check_string_list(raw, "archive", true, out)
	_check_string_list(raw, "extra_files", false, out)
	var launch: Variant = raw.get("launch")
	if not launch is Dictionary:
		out.append("launch must be an object")
	else:
		if not (launch.get("executable") is String and _is_safe_path(launch["executable"])):
			out.append("launch.executable must be a relative path")
		if not launch.get("cwd") in CWD_VALUES:
			out.append("launch.cwd must be one of %s" % str(CWD_VALUES))
		if launch.has("args") and not launch["args"] is Array:
			out.append("launch.args must be an array")
	var roms: Variant = raw.get("roms")
	if not (roms is Array and not (roms as Array).is_empty()):
		out.append("roms must be a non-empty array")
	else:
		for rom in roms:
			if not (rom is Dictionary and rom.get("label") is String and is_sha1(rom.get("sha1"))):
				out.append("each rom needs a label and a 40 character lowercase hex sha1")
				break
	return out


## What is wrong with an `art` object; empty when it is fine (ART-1, ART-4).
static func validate_art(art: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not art is Dictionary:
		out.append("must be an object")
		return out
	for key in ART_KEYS:
		if not (art.get(key) is String and not (art[key] as String).strip_edges().is_empty()):
			out.append("%s must be a non-empty string" % key)
	if art.get("url") is String and not Art.url_allowed(art["url"]):
		out.append("url must be an https URL on cdn2.steamgriddb.com or cdn.steamgriddb.com")
	if art.get("source") is String and not (art["source"] as String).begins_with(ART_SOURCE):
		out.append("source must be a page on steamgriddb.com")
	return out


static func is_sha1(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{40}$").search(value) != null


## True for a relative path without `..` segments or a leading slash.
static func _is_safe_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("\\"):
		return false
	return not ".." in path.split("/")


static func _check_string_list(
	raw: Dictionary, key: String, required: bool, out: PackedStringArray
) -> void:
	if not raw.has(key):
		if required:
			out.append("%s is required" % key)
		return
	var list: Variant = raw[key]
	if not list is Array or (required and (list as Array).is_empty()):
		out.append("%s must be an array of paths" % key)
		return
	for item in list:
		if not (item is String and _is_safe_path(item)):
			out.append("%s must hold relative paths" % key)
			return


static func _normalise(raw: Dictionary) -> Dictionary:
	var port := raw.duplicate(true)
	port["asset_suffix"] = (port["asset_suffix"] as String).to_lower()
	if not port.has("first_run"):
		port["first_run"] = ""
	if not port.has("extra_files"):
		port["extra_files"] = []
	if not port["launch"].has("args"):
		port["launch"]["args"] = []
	return port

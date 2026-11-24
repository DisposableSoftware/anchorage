extends RefCounted
## The port catalog, `res://data/ports.json` (PORT-1, PROD-13), and the same format fetched
## from the repository (PORT-18 .. PORT-22, `catalog_update.gd`). Adding a port is adding an
## entry; docs/adding-a-port.md walks through it.
##
## Top level: {schema, version, ports}.
##   schema        the version of this format, SCHEMA today. A catalog with a higher one is
##                 refused whole, so a format change never breaks an older app
##   version       an integer raised whenever the list changes; a fetched catalog replaces
##                 known entries only when its version is higher than the one in use
##   ports         one object per port, below
##
## Schema, one object per port in `"ports"` (every key is required unless it says optional).
## An entry with a key not listed here, or a `rom_place` or `launch.cwd` this app does not
## know, is skipped as "needs a newer Anchorage". Text has no control characters.
##   id            short unique name, also the folder name under user://ports/: at most
##                 ID_MAX of a-z, 0-9, _ and -
##   name          display name of the port
##   game          title of the game it plays
##   description   one or two sentences for the detail panel
##   repo          GitHub "owner/name" (ASCII letters, digits, ., _, -); releases come from
##                 its releases/latest
##   asset_suffix  the Linux release asset is the one whose name ends with this, compared
##                 without case (codenames in asset names change per version)
##   archive       Array of generated archive names (e.g. "oot.o2r"); the port is extracted
##                 when any of them exists
##   launch        {executable, cwd, args}
##                   executable  path inside current/ after unpacking. A bare AppImage asset
##                               is saved under this name; a zip must contain it
##                   cwd         "data" (the port's data folder) or "current" (the unpacked
##                               folder, for ports that read config files next to themselves)
##                   args        Array of arguments (optional, default []): at most ARGS_MAX,
##                               each of letters, digits and . _ = : , + -, without ".."
##   extra_files   Array of paths of files or folders inside the unpacked release that
##                 install copies to the data folder, keeping the last path part as the
##                 name; launch copies them again when missing (optional, default [])
##   rom_place     where the ROM is written: "data_dir" (data folder), "cwd" (the launch
##                 working directory) or "argv" (the data folder, and its path is passed as
##                 an argument while the port has no archive: PORT-16)
##   first_run     a short note for the detail panel until the port has made its archive,
##                 lines split by \n (optional, default "": PORT-17)
##   monogram      the card's short name when the one built from `game` is not the usual
##                 one (e.g. "PM64"), at most MONOGRAM_MAX characters (optional, default "")
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
##               In the built-in catalog a bad `art` object is reported and dropped and the
##               port stays, with its monogram; in a fetched one the entry is refused.
##
## Paths (executable, archive, extra_files) are relative: parts of letters, digits and
## . _ + -, none starting with . or -, at most PATH_MAX characters. `rom_file` is one such
## part. They become argv entries and file names, never shell text (launcher.gd).
##
## Values from these files are untrusted data to the rest of the code: `parse` drops any
## entry that breaks the schema and reports why.

const Art := preload("res://src/art.gd")

const PATH := "res://data/ports.json"
## The newest catalog format this app understands.
const SCHEMA := 1
## A fetched catalog larger than this is refused (PORT-19).
const MAX_BYTES := 256 * 1024
const MAX_PORTS := 64
const NEWER := "needs a newer Anchorage"
const ART_KEYS := ["url", "author", "source", "style"]
const ART_SOURCE := "https://www.steamgriddb.com/"
const CWD_VALUES := ["data", "current"]
const MONOGRAM_MAX := 5
const ID_MAX := 32
const PATH_MAX := 128
const ARGS_MAX := 16
const ROMS_MAX := 64
const ROM_PLACES := ["data_dir", "cwd", "argv"]
const STRING_KEYS := ["id", "name", "game", "description", "repo", "asset_suffix", "rom_file"]
## The longest text per key.
const LENGTHS := {
	"name": 80,
	"game": 120,
	"description": 400,
	"repo": 140,
	"asset_suffix": 64,
	"rom_file": 64,
	"first_run": 400,
	"label": 40,
	"author": 80,
	"style": 40,
	"url": 300,
	"source": 300,
}
const PORT_KEYS := [
	"id",
	"name",
	"game",
	"description",
	"repo",
	"asset_suffix",
	"archive",
	"launch",
	"extra_files",
	"rom_place",
	"rom_file",
	"roms",
	"first_run",
	"monogram",
	"art",
]
const LAUNCH_KEYS := ["executable", "cwd", "args"]
const ROM_KEYS := ["label", "sha1"]
## C0 and C1 controls, DEL, zero-width and bidirectional overrides: nothing a name needs,
## and enough to make one text look like another.
const CONTROL := (
	"[\\x{0}-\\x{1f}\\x{7f}-\\x{9f}\\x{200b}-\\x{200f}"
	+ "\\x{202a}-\\x{202e}\\x{2066}-\\x{2069}\\x{feff}]"
)
const PATH_PART := "[A-Za-z0-9_+][A-Za-z0-9._+-]*"
const ARG := "^[A-Za-z0-9._=:,+-]{1,128}$"
const REPO := "^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$"
const SUFFIX := "^[A-Za-z0-9._-]+$"
const ART_URL := "^https://cdn2?\\.steamgriddb\\.com/[A-Za-z0-9_./-]+$"
const ART_PAGE := "^https://www\\.steamgriddb\\.com/[A-Za-z0-9_./-]*$"


## The shipped catalog, as `parse` returns it.
static func load_default() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return _refused(PATH + " is missing")
	return parse(FileAccess.get_file_as_string(PATH))


## {ok, ports: Array[Dictionary], errors: PackedStringArray, version: int, newer: Array}.
## `ports` are the valid entries in file order, normalised (optional keys filled in), with a
## message in `errors` for every problem found; `newer` names the entries skipped because
## they need a newer Anchorage. `ok` is false when the whole catalog is refused.
## `fetched` is a catalog from the network or its cache (PORT-19): `schema` and `version`
## are required and bad art refuses its entry.
static func parse(text: String, fetched := false) -> Dictionary:
	if fetched and text.to_utf8_buffer().size() > MAX_BYTES:
		return _refused("ports.json: larger than %d KiB" % (MAX_BYTES / 1024))
	var json := JSON.new()
	var data: Variant = json.data if json.parse(text) == OK else null
	if not (data is Dictionary and data.get("ports") is Array):
		return _refused('ports.json: expected an object with a "ports" array')
	var schema := _whole(data.get("schema"))
	var version := _whole(data.get("version"))
	if (data.has("schema") and schema < 1) or (data.has("version") and version < 1):
		return _refused("ports.json: schema and version must be positive whole numbers")
	if fetched and (schema < 1 or version < 1):
		return _refused("ports.json: schema and version are required")
	if schema > SCHEMA:
		return _refused("ports.json: schema %d %s" % [schema, NEWER])
	var out := {
		"ok": true,
		"ports": [],
		"errors": PackedStringArray(),
		"version": maxi(version, 0),
		"newer": [],
	}
	var seen := {}
	for raw in data["ports"]:
		var label: String = _label(raw)
		if out["ports"].size() >= MAX_PORTS:
			out["errors"].append("ports.json: more than %d ports, the rest ignored" % MAX_PORTS)
			break
		var newer := needs_newer(raw)
		if not newer.is_empty():
			out["errors"].append("ports.json: %s: %s (%s)" % [label, NEWER, newer])
			out["newer"].append(label)
			continue
		var problems := validate(raw)
		if problems.is_empty() and seen.has(raw["id"]):
			problems.append("duplicate id")
		var art_problems := PackedStringArray()
		if problems.is_empty() and raw.has("art"):
			art_problems = validate_art(raw["art"])
			if fetched and not art_problems.is_empty():
				problems.append("art: " + "; ".join(art_problems))
		if not problems.is_empty():
			for problem in problems:
				out["errors"].append("ports.json: %s: %s" % [label, problem])
			continue
		seen[raw["id"]] = true
		var port := _normalise(raw)
		for problem in art_problems:
			out["errors"].append("ports.json: %s: art: %s" % [label, problem])
		if not art_problems.is_empty():
			port.erase("art")
		out["ports"].append(port)
	return out


static func find(ports: Array, id: String) -> Dictionary:
	for port in ports:
		if port["id"] == id:
			return port
	return {}


## PORT-20: `fetched` (at `fetched_version`) merged into `current` (at `current_version`),
## by id. Known ports keep their place and are replaced only by a newer catalog; a newer
## catalog drops the ports it no longer lists unless `keep(id)` (installed); unknown ports
## go after the others, in the fetched order. {ports, added, replaced, dropped}: ids.
static func merge(
	current: Array, current_version: int, fetched: Array, fetched_version: int, keep: Callable
) -> Dictionary:
	var newer := fetched_version > current_version
	var out := {"ports": [], "added": [], "replaced": [], "dropped": []}
	for port in current:
		var other := find(fetched, port["id"])
		if other.is_empty():
			if newer and not keep.call(port["id"]):
				out["dropped"].append(port["id"])
			else:
				out["ports"].append(port)
		elif newer and other != port:
			out["ports"].append(other)
			out["replaced"].append(port["id"])
		else:
			out["ports"].append(port)
	for port in fetched:
		if find(current, port["id"]).is_empty():
			out["ports"].append(port)
			out["added"].append(port["id"])
	return out


## Why `raw` needs a newer app than this one, or "": a key, `rom_place` or `launch.cwd`
## this version does not know (PORT-19).
static func needs_newer(raw: Variant) -> String:
	if not raw is Dictionary:
		return ""
	for key in raw:
		if not key in PORT_KEYS:
			return 'unknown field "%s"' % _short(key)
	var place: Variant = raw.get("rom_place")
	if place is String and not place in ROM_PLACES:
		return 'unknown rom_place "%s"' % _short(place)
	var launch: Variant = raw.get("launch")
	if launch is Dictionary:
		for key in launch:
			if not key in LAUNCH_KEYS:
				return 'unknown field "launch.%s"' % _short(key)
		if launch.get("cwd") is String and not launch["cwd"] in CWD_VALUES:
			return 'unknown launch.cwd "%s"' % _short(launch["cwd"])
	if raw.get("roms") is Array:
		for rom in raw["roms"]:
			if rom is Dictionary:
				for key in rom:
					if not key in ROM_KEYS:
						return 'unknown field "roms.%s"' % _short(key)
	return ""


## What is wrong with one raw entry; empty when it is fine.
static func validate(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Dictionary:
		out.append("not an object")
		return out
	for key in STRING_KEYS:
		if not (raw.get(key) is String and not (raw[key] as String).strip_edges().is_empty()):
			out.append("%s must be a non-empty string" % key)
		elif not is_plain_text(raw[key], LENGTHS.get(key, ID_MAX)):
			out.append(
				"%s must be at most %d characters of plain text" % [key, LENGTHS.get(key, ID_MAX)]
			)
	if raw.get("id") is String and not _matches("^[a-z0-9_-]{1,%d}$" % ID_MAX, raw["id"]):
		out.append("id may only have a-z, 0-9, _ and -, at most %d" % ID_MAX)
	if raw.get("repo") is String and not is_repo(raw["repo"]):
		out.append("repo must look like owner/name")
	if raw.get("asset_suffix") is String and not _matches(SUFFIX, raw["asset_suffix"]):
		out.append("asset_suffix may only have letters, digits, ., _ and -")
	if (
		raw.get("rom_file") is String
		and not (
			(raw["rom_file"] as String).ends_with(".z64") and is_safe_path(raw["rom_file"], false)
		)
	):
		out.append("rom_file must be a plain file name ending with .z64")
	if not raw.get("rom_place") in ROM_PLACES:
		out.append("rom_place must be one of %s" % str(ROM_PLACES))
	if (
		raw.has("first_run")
		and not (
			raw["first_run"] is String
			and is_plain_text(raw["first_run"], LENGTHS["first_run"], true)
		)
	):
		out.append("first_run must be a string of at most %d characters" % LENGTHS["first_run"])
	if (
		raw.has("monogram")
		and not (
			raw["monogram"] is String
			and (raw["monogram"] as String).strip_edges().length() in range(1, MONOGRAM_MAX + 1)
			and is_plain_text(raw["monogram"], MONOGRAM_MAX)
		)
	):
		out.append("monogram must be 1 to %d characters" % MONOGRAM_MAX)
	_check_string_list(raw, "archive", true, out)
	_check_string_list(raw, "extra_files", false, out)
	_check_launch(raw.get("launch"), out)
	var roms: Variant = raw.get("roms")
	if not (roms is Array and not (roms as Array).is_empty() and roms.size() <= ROMS_MAX):
		out.append("roms must be an array of 1 to %d" % ROMS_MAX)
	else:
		for rom in roms:
			if not (
				rom is Dictionary
				and rom.get("label") is String
				and not (rom["label"] as String).strip_edges().is_empty()
				and is_plain_text(rom["label"], LENGTHS["label"])
				and is_sha1(rom.get("sha1"))
			):
				out.append("each rom needs a label and a 40 character lowercase hex sha1")
				break
	return out


## What is wrong with an `art` object; empty when it is fine (ART-1, ART-4).
static func validate_art(art: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not art is Dictionary:
		out.append("must be an object")
		return out
	for key in art:
		if not key in ART_KEYS:
			out.append('unknown field "%s"' % _short(key))
	for key in ART_KEYS:
		if not (art.get(key) is String and not (art[key] as String).strip_edges().is_empty()):
			out.append("%s must be a non-empty string" % key)
		elif not is_plain_text(art[key], LENGTHS[key]):
			out.append("%s must be at most %d characters of plain text" % [key, LENGTHS[key]])
	if (
		art.get("url") is String
		and not (Art.url_allowed(art["url"]) and _matches(ART_URL, art["url"]))
	):
		out.append("url must be an https URL on cdn2.steamgriddb.com or cdn.steamgriddb.com")
	if (
		art.get("source") is String
		and not (
			(art["source"] as String).begins_with(ART_SOURCE) and _matches(ART_PAGE, art["source"])
		)
	):
		out.append("source must be a page on steamgriddb.com")
	return out


static func is_sha1(value: Variant) -> bool:
	return value is String and _matches("^[0-9a-f]{40}$", value)


## PORT-22: an ASCII GitHub owner/name, neither part "." or "..".
static func is_repo(repo: String) -> bool:
	if not _matches(REPO, repo):
		return false
	for part in repo.split("/"):
		if part == "." or part == "..":
			return false
	return true


## True for text of at most `limit` characters without control characters (`lines` allows
## line breaks).
static func is_plain_text(text: String, limit: int, lines := false) -> bool:
	if text.length() > limit:
		return false
	return not _matches(CONTROL, text.replace("\n", "") if lines else text)


## A relative path whose parts are plain names (PATH_PART), at most PATH_MAX characters: no
## `..`, no leading slash, no hidden or option-like part, nothing a shell would read.
## `nested` false allows a single part only.
static func is_safe_path(path: String, nested := true) -> bool:
	var pattern := "^%s(/%s)*$" % [PATH_PART, PATH_PART] if nested else "^%s$" % PATH_PART
	return path.length() <= PATH_MAX and _matches(pattern, path)


## A launch argument: no spaces, quotes, slashes or shell characters, and no `..`.
static func is_safe_arg(arg: Variant) -> bool:
	return arg is String and _matches(ARG, arg) and not (arg as String).contains("..")


static func _check_launch(launch: Variant, out: PackedStringArray) -> void:
	if not launch is Dictionary:
		out.append("launch must be an object")
		return
	if not (launch.get("executable") is String and is_safe_path(launch["executable"])):
		out.append("launch.executable must be a relative path")
	if not launch.get("cwd") in CWD_VALUES:
		out.append("launch.cwd must be one of %s" % str(CWD_VALUES))
	if not launch.has("args"):
		return
	var args: Variant = launch["args"]
	if not (args is Array and args.size() <= ARGS_MAX):
		out.append("launch.args must be an array of at most %d" % ARGS_MAX)
		return
	for arg in args:
		if not is_safe_arg(arg):
			out.append("launch.args may only have letters, digits and . _ = : , + -")
			return


static func _check_string_list(
	raw: Dictionary, key: String, required: bool, out: PackedStringArray
) -> void:
	if not raw.has(key):
		if required:
			out.append("%s is required" % key)
		return
	var list: Variant = raw[key]
	if not list is Array or (required and (list as Array).is_empty()) or list.size() > PATH_MAX:
		out.append("%s must be an array of paths" % key)
		return
	for item in list:
		if not (item is String and is_safe_path(item)):
			out.append("%s must hold relative paths" % key)
			return


static func _normalise(raw: Dictionary) -> Dictionary:
	var port := raw.duplicate(true)
	port["asset_suffix"] = (port["asset_suffix"] as String).to_lower()
	if not port.has("first_run"):
		port["first_run"] = ""
	port["monogram"] = (port.get("monogram", "") as String).strip_edges()
	if not port.has("extra_files"):
		port["extra_files"] = []
	if not port["launch"].has("args"):
		port["launch"]["args"] = []
	return port


static func _refused(error: String) -> Dictionary:
	return {
		"ok": false,
		"ports": [],
		"errors": PackedStringArray([error]),
		"version": 0,
		"newer": [],
	}


## A JSON number that is a whole number, as an int; 0 for anything else.
static func _whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float and value == floorf(value) and absf(value) < 1e9:
		return int(value)
	return 0


static func _label(raw: Variant) -> String:
	if raw is Dictionary and raw.get("id") is String and _matches("^[a-z0-9_-]{1,32}$", raw["id"]):
		return raw["id"]
	return "?"


## `value` cut short and stripped of control characters, for a message.
static func _short(value: Variant) -> String:
	var text := RegEx.create_from_string(CONTROL).sub(str(value), "", true)
	return text if text.length() <= 32 else text.left(31) + "…"


## A `$` at the end of `pattern` means the very end: PCRE's `$` also matches before a final
## line break, which would let "name\n" through.
static func _matches(pattern: String, text: String) -> bool:
	var found := RegEx.create_from_string(pattern).search(text)
	if found == null:
		return false
	return not pattern.ends_with("$") or found.get_end() == text.length()

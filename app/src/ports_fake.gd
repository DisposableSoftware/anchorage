# gdlint: disable=max-public-methods
extends Node
## A stand-in for `Ports` (ports.gd) with fixed demo data, for UI tests and screenshots.
## Same interface as the contract in spec/ports.md. Actions are recorded in `calls`; with
## `simulate` on they also play out over time (downloads progress, a launched port exits).
##
## Scenarios (`--fake-ports SCENARIO`), each about the first card unless noted:
##   showcase     one card per state: ready, update available, installing 42 %, ROM missing
##   fresh        nothing installed yet
##   installing   the first port downloading, at 42 %
##   updating     the first port updating, progress unknown
##   rom-missing  the first port installed, no matching ROM in the folder
##   error        the first port's update failed
##   offline      the update check failed for every port
##   playing      the first port running
##   art-late     as showcase, but the cover art arrives 2 s in (or on `deliver_art`)
##   first-run    every port installed, none has made its game files yet: the first-launch
##                notes (PORT-17), with the first card focused
##   rom-config   as showcase, with two ROM folders set in config.ini (ROM-12)
##   rom-folders  as showcase, with two chosen ROM folders: ~/Emulation/roms/n64 and the
##                SD card's (ROM-17)
##   rom-unplugged as rom-folders, with the SD card out: its folder is not found
##   no-card      as showcase, with no SD card or drive (ROM-14)
##   new-ports    as showcase; 1 s in (or on `add_new_ports` when `simulate` is off) a
##                catalog fetch adds NEW_DEMO at the end, with its notice and `New` badge
##                (PORT-23)
##   self-*       Anchorage's own update (UPD), shown by `self_update_fake.gd`: self-update
##                (a newer version, no port busy), self-busy (the same over showcase, with
##                its install running), self-downloading, self-ready, self-unsupported
##
## The ROM folder chooser (ROM-11) browses a small made-up tree (TREE, ROM_COUNTS) under
## /home/deck and two drives; the SD card search (ROM-14) answers SEARCH_RESULTS after
## SEARCH_SECONDS, or on `finish_search` when `simulate` is off.
##
## A port that is not installed has no game files either, so it shows its note too.
##
## The first two ports have placeholder cover art, drawn in code (never a real image), and
## the others show their monogram, so a screenshot has both looks (ART-5, ART-6).

signal changed(id: String)
signal launched(id: String)
signal exited(id: String)
signal rom_folder_changed
signal folder_listed(path: String, listing: Dictionary)
signal search_changed
signal notice_changed

const SCENARIOS := [
	"showcase",
	"fresh",
	"installing",
	"updating",
	"rom-missing",
	"error",
	"offline",
	"playing",
	"art-late",
	"first-run",
	"rom-config",
	"no-card",
	"new-ports",
	"rom-folders",
	"rom-unplugged",
	"self-update",
	"self-busy",
	"self-downloading",
	"self-ready",
	"self-unsupported",
]
const NEW_DELAY := 1.0
## The port the `new-ports` scenario's catalog fetch adds.
const NEW_DEMO := {
	"id": "township",
	"name": "Township",
	"game": "Animal Forest",
	"description": "A PC port of Animal Forest with widescreen and high frame rates.",
	"latest": "1.0.0",
	"rom": "Animal Forest (Japan).z64",
	"first_run": "The first launch makes the game files from your ROM",
	"wanted": ["JP 1.0"],
}
const ART_PORTS := ["soh", "2ship"]
const ART_SIZE := Vector2i(920, 430)
const ART_DELAY := 2.0
const ROM_FOLDER := "~/Emulation/roms/n64"
const FAKE_HOME := "/home/deck"
const FOUND_FOLDER := FAKE_HOME + "/Emulation/roms/n64"
const SD_CARD := "/run/media/mmcblk0p1"
const USB_DRIVE := "/run/media/deck/Backup"
const TREE := {
	"/": ["home", "run"],
	"/home": ["deck"],
	"/home/deck": ["Desktop", "Documents", "Downloads", "Emulation", "Music", "Pictures", "Videos"],
	"/home/deck/Emulation": ["bios", "roms", "saves", "storage", "tools"],
	"/home/deck/Emulation/roms":
	["dreamcast", "gb", "gba", "gc", "n64", "n64dd", "nds", "nes", "psx", "snes"],
	SD_CARD: ["Emulation", "Music", "steamapps"],
	SD_CARD + "/Emulation": ["roms"],
	SD_CARD + "/Emulation/roms": ["n64", "snes"],
	USB_DRIVE: ["Photos", "Roms"],
	USB_DRIVE + "/Roms": ["N64"],
}
const ROM_COUNTS := {
	"/home/deck/Downloads": 1,
	"/home/deck/Emulation/roms/gba": 9,
	"/home/deck/Emulation/roms/n64": 6,
	"/home/deck/Emulation/roms/nes": 14,
	"/home/deck/Emulation/roms/snes": 21,
	SD_CARD + "/Emulation/roms/n64": 4,
	SD_CARD + "/Emulation/roms/snes": 12,
	USB_DRIVE + "/Roms/N64": 3,
}
const PLACES := [
	{"label": "Home", "path": FAKE_HOME, "sd": false},
	{"label": "SD card", "path": SD_CARD, "sd": true},
	{"label": "Backup", "path": USB_DRIVE, "sd": false},
]
const SEARCH_SECONDS := 1.5
## The `rom-folders` scenario's chosen folders, and how many demo ports each one serves.
const CHOSEN_DEMO := [FOUND_FOLDER, SD_CARD + "/Emulation/roms/n64"]
const FOLDER_PORTS := {FOUND_FOLDER: 5, SD_CARD + "/Emulation/roms/n64": 1}

## The catalog's notes (app/data/ports.json).
const SHIP_NOTE := (
	"The first launch makes the game files from your ROM\nIf it then asks to run, close it"
	+ " and press Play again"
)
const QUESTIONS_NOTE := "First launch only: answer its questions with the trackpad or a mouse"
const MOUSE_NOTE := "First launch only: use the trackpad or a mouse\n"

const DEMO := [
	{
		"id": "soh",
		"name": "Ship of Harkinian",
		"game": "The Legend of Zelda: Ocarina of Time",
		"description":
		(
			"A PC port of Ocarina of Time with widescreen, high frame rates, "
			+ "modern controls and a long list of optional enhancements."
		),
		"latest": "9.3.1",
		"rom": "Ocarina of Time (USA) (Rev 2).z64",
		"first_run": SHIP_NOTE,
		"wanted":
		[
			"NTSC-U 1.0",
			"NTSC-U 1.1",
			"NTSC-U 1.2",
			"NTSC-J 1.0",
			"PAL 1.0",
			"PAL 1.1",
			"GameCube",
			"Master Quest",
		],
	},
	{
		"id": "2ship",
		"name": "2 Ship 2 Harkinian",
		"game": "The Legend of Zelda: Majora's Mask",
		"description":
		(
			"A PC port of Majora's Mask from the team behind Ship of Harkinian, "
			+ "with widescreen, high frame rates and quality-of-life options."
		),
		"latest": "5.0.1",
		"rom": "Majora's Mask (USA).z64",
		"first_run": SHIP_NOTE,
		"wanted": ["NTSC-U 1.0", "NTSC-U GameCube"],
	},
	{
		"id": "starship",
		"name": "Starship",
		"game": "Star Fox 64",
		"description":
		"A PC port of Star Fox 64 with widescreen, high frame rates and mod support.",
		"latest": "v2.0.0",
		"rom": "Star Fox 64 (USA) (Rev 1).z64",
		"first_run": MOUSE_NOTE + "Answer Yes, then pick sf64.z64",
		"wanted": ["US 1.0", "US 1.1"],
	},
	{
		"id": "spaghettikart",
		"name": "SpaghettiKart",
		"game": "Mario Kart 64",
		"description":
		"A PC port of Mario Kart 64 with widescreen, high frame rates and custom tracks.",
		"latest": "1.0.0",
		"rom": "Mario Kart 64 (USA).z64",
		"first_run": QUESTIONS_NOTE,
		"wanted": ["US"],
	},
	{
		"id": "ghostship",
		"name": "Ghostship",
		"game": "Super Mario 64",
		"description": "A PC port of Super Mario 64 with widescreen, mods and alternate assets.",
		"latest": "3.0.0",
		"rom": "Super Mario 64 (USA).z64",
		"first_run": MOUSE_NOTE + "Answer Yes to both questions",
		"wanted": ["US", "JP"],
	},
	{
		"id": "paperboat",
		"name": "PaperBoat",
		"game": "Paper Mario",
		"monogram": "PM64",
		"description": "A PC port of Paper Mario built on the Paper Mario DX decompilation.",
		"latest": "1.0.3",
		"rom": "Paper Mario (USA).z64",
		"first_run": QUESTIONS_NOTE,
		"wanted": ["US"],
	},
	{
		"id": "lighthouse",
		"name": "Lighthouse",
		"game": "Banjo-Kazooie",
		"monogram": "BK",
		"description":
		"A PC port of Banjo-Kazooie with online multiplayer, romhacks and a randomizer.",
		"latest": "1.2.2",
		"rom": "Banjo-Kazooie (USA) (Rev 1).z64",
		"first_run": SHIP_NOTE,
		"wanted": ["US 1.0", "US 1.1", "PAL", "JP"],
	},
]

## Seconds a simulated download or update takes, and a launched port runs.
const BUSY_SECONDS := 6.0
const PLAY_SECONDS := 8.0

static var _art_cache := {}

var simulate := true
## Every action called, in order: ["install", "soh"], ["refresh"], ...
var calls: Array = []
var _info := {}
var _ids: Array[String] = []
var _play_left := {}
## Ports with a download started here; the scenarios' busy states stay as they are.
var _jobs := {}
var _art := {}
var _art_wait := -1.0
## Ports that have made their game files (PORT-17); a port that is not installed has not.
var _extracted := {}
## The ROM folders scanned (ROM-17), where they came from, and the ones chosen here.
var _folders: Array = [FOUND_FOLDER]
var _folder_source := "emudeck"
var _chosen: Array = []
var _locked := false
var _cards := true
var _search := {"status": "idle", "results": []}
var _search_left := -1.0
var _new_wait := -1.0
var _notice := ""


func _init(scenario := "showcase") -> void:
	for demo in DEMO:
		_add(demo)
	_apply_scenario(scenario if scenario in SCENARIOS else "showcase")
	if scenario == "new-ports":
		_new_wait = NEW_DELAY
	for id in _ids:
		_extracted[id] = _info[id].installed and scenario != "first-run"
	if scenario == "rom-config":
		_locked = true
		_folders = ["/mnt/games/n64", "/mnt/usb/n64"]
		_folder_source = "config"
	if scenario in ["rom-folders", "rom-unplugged"]:
		_chosen = CHOSEN_DEMO.duplicate()
		_folders = _chosen.duplicate()
		_folder_source = "chosen"
	_cards = not scenario in ["no-card", "rom-unplugged"]
	if scenario == "art-late":
		_art_wait = ART_DELAY
	else:
		deliver_art(false)


func _add(demo: Dictionary) -> void:
	_ids.append(demo.id)
	_info[demo.id] = {
		"id": demo.id,
		"name": demo.name,
		"game": demo.game,
		"monogram": demo.get("monogram", ""),
		"description": demo.description,
		"installed": false,
		"installed_version": "",
		"latest_version": demo.latest,
		"update_available": false,
		"offline": false,
		"rom":
		{
			"found": true,
			"label": demo.rom,
			"path": ROM_FOLDER.path_join(demo.rom),
			"wanted": demo.wanted
		},
		"busy": {"action": "", "progress": -1.0, "detail": ""},
		"running": false,
		"first_run": demo.first_run,
		"error": "",
		"is_new": false,
	}


## PORT-23: what a catalog fetch that adds NEW_DEMO does: the port goes at the end of
## `list()`, is new, and `notice_changed` fires.
func add_new_ports() -> void:
	_new_wait = -1.0
	if _info.has(NEW_DEMO.id):
		return
	_add(NEW_DEMO)
	_info[NEW_DEMO.id].is_new = true
	_notice = "1 new port: %s" % NEW_DEMO.name
	notice_changed.emit()


func notice() -> String:
	return _notice


func mark_seen(id: String) -> void:
	if _info.has(id) and _info[id].is_new:
		calls.append(["mark_seen", id])
		_info[id].is_new = false
		changed.emit(id)


## Gives the art ports their texture (and says so) at once instead of after ART_DELAY.
func deliver_art(announce := true) -> void:
	_art_wait = -1.0
	for id in ART_PORTS:
		_art[id] = _demo_art(ART_PORTS.find(id))
		if announce:
			changed.emit(id)


## A 920x430 stand-in for cover art: a sky, a sun and two ridges, in a hue per index.
static func _demo_art(index: int) -> Texture2D:
	if _art_cache.has(index):
		return _art_cache[index]
	var hue := 0.58 + 0.3 * index
	var image := Image.create(ART_SIZE.x, ART_SIZE.y, false, Image.FORMAT_RGB8)
	for y in ART_SIZE.y:
		var t := float(y) / ART_SIZE.y
		var sky := Color.from_hsv(fposmod(hue + 0.08 * t, 1.0), 0.55 - 0.25 * t, 0.35 + 0.6 * t)
		image.fill_rect(Rect2i(0, y, ART_SIZE.x, 1), sky)
	var sun := Color.from_hsv(fposmod(hue + 0.4, 1.0), 0.25, 1.0)
	var center := Vector2(ART_SIZE.x * (0.68 - 0.3 * index), ART_SIZE.y * 0.46)
	for y in range(int(center.y) - 90, int(center.y) + 91):
		var half := int(sqrt(maxf(90.0 * 90.0 - (y - center.y) * (y - center.y), 0.0)))
		image.fill_rect(Rect2i(int(center.x) - half, y, half * 2, 1), sun)
	for ridge in 2:
		var shade := Color.from_hsv(hue, 0.5, 0.42 - 0.2 * ridge)
		for x in ART_SIZE.x:
			var wave := sin(x * (0.011 + 0.006 * ridge) + index * 2.0 + ridge * 1.7)
			var top := int(ART_SIZE.y * (0.66 + 0.1 * ridge) - 40.0 * wave)
			image.fill_rect(Rect2i(x, top, 1, ART_SIZE.y - top), shade)
	image.generate_mipmaps()
	_art_cache[index] = ImageTexture.create_from_image(image)
	return _art_cache[index]


func _apply_scenario(scenario: String) -> void:
	var first: String = _ids[0]
	match scenario:
		"self-update", "self-downloading", "self-ready", "self-unsupported":
			_set_installed("soh", "9.3.1")
			_set_installed("2ship", "5.0.0")
			_set_installed("spaghettikart", "1.0.0")
		"showcase", "art-late", "rom-config", "no-card", "new-ports", "self-busy":
			_set_installed("soh", "9.3.1")
			_set_installed("2ship", "5.0.0")
			_set_busy("starship", "install", 0.42, "33.6 MB of 80 MB")
			_set_installed("spaghettikart", "1.0.0")
			_set_rom_missing("spaghettikart")
		"fresh":
			_set_rom_missing("spaghettikart")
		"installing":
			_set_busy(first, "install", 0.42, "13.5 MB of 32.1 MB")
		"updating":
			_set_installed(first, "9.3.0")
			_set_busy(first, "update", -1.0, "Unpacking")
		"rom-missing":
			_set_installed(first, "9.3.1")
			_set_rom_missing(first)
		"error":
			_set_installed(first, "9.3.0")
			_info[first].error = (
				"Could not update “Ship of Harkinian”\n"
				+ "The download stopped after 18.2 MB of 32.1 MB: connection reset by peer."
			)
		"offline":
			_set_installed(first, "9.3.0")
			_set_installed("2ship", "5.0.1")
			for id in _ids:
				_info[id].offline = true
				_info[id].latest_version = ""
				_info[id].update_available = false
		"first-run":
			for demo in DEMO:
				_set_installed(demo.id, demo.latest)
		"playing":
			_set_installed(first, "9.3.1")
			_info[first].running = true
			_play_left[first] = INF
	for id in _ids:
		if scenario != "offline":
			_info[id].update_available = (
				_info[id].installed and _info[id].installed_version != _info[id].latest_version
			)


func _set_installed(id: String, version: String) -> void:
	_info[id].installed = true
	_info[id].installed_version = version


func _set_busy(id: String, action: String, progress: float, detail: String) -> void:
	_info[id].busy = {"action": action, "progress": progress, "detail": detail}


func _set_rom_missing(id: String) -> void:
	_info[id].rom.found = false
	_info[id].rom.label = "No matching ROM"
	_info[id].rom.path = ROM_FOLDER


func list() -> Array:
	return _ids.duplicate()


func info(id: String) -> Dictionary:
	var out: Dictionary = _info[id].duplicate(true)
	out["art"] = _art.get(id)
	if _extracted.get(id, false):
		out["first_run"] = ""
	return out


func install(id: String) -> void:
	_start("install", id)


func update(id: String) -> void:
	_start("update", id)


func remove(id: String) -> void:
	calls.append(["remove", id])
	if simulate:
		_info[id].installed = false
		_info[id].installed_version = ""
		_info[id].update_available = false
		changed.emit(id)


func launch(id: String) -> void:
	calls.append(["launch", id])
	if simulate and _info[id].installed and not _info[id].running:
		_info[id].running = true
		_play_left[id] = PLAY_SECONDS
		changed.emit(id)
		launched.emit(id)


func cancel(id: String) -> void:
	calls.append(["cancel", id])
	if simulate and _info[id].busy.action != "":
		_jobs.erase(id)
		_set_busy(id, "", -1.0, "")
		changed.emit(id)


func refresh() -> void:
	calls.append(["refresh"])
	if not simulate:
		return
	for demo in DEMO:
		var port: Dictionary = _info[demo.id]
		port.offline = false
		port.latest_version = demo.latest
		port.update_available = port.installed and port.installed_version != demo.latest
		changed.emit(demo.id)


func dismiss_error(id: String) -> void:
	calls.append(["dismiss_error", id])
	if simulate:
		_info[id].error = ""
		changed.emit(id)


func rom_folder_info() -> Dictionary:
	var folders := []
	for dir: String in _folders:
		var missing := dir.begins_with("/run/media") and not _cards
		var folder := {"path": _display(dir), "full": dir, "source": _folder_source}
		folder["status"] = "missing" if missing else "ok"
		folder["ports"] = 0 if missing else FOLDER_PORTS.get(dir, 0)
		folders.append(folder)
	return {
		"path": _display(_folders[0]) if not _folders.is_empty() else "",
		"full": _folders[0] if not _folders.is_empty() else "",
		"source": _folder_source,
		"locked": _locked,
		"config_file": "~/.config/anchorage/config.ini",
		"folders": folders,
		"chosen": _chosen.duplicate(),
	}


## Records the choice; with the folders unlocked it is added to the chosen ones (after the
## found folder, on the first choice, as Ports does) and every port is "rescanned" (nothing
## changes in the demo data but the folders shown).
func set_rom_folder(path: String) -> void:
	calls.append(["set_rom_folder", path])
	if _locked or path in _chosen:
		return
	if _chosen.is_empty() and _folder_source != "fallback":
		_chosen = _folders.duplicate()
	if not path in _chosen:
		_chosen.append(path)
	_use_chosen()


## Records it; a chosen folder is removed, and with none left the found folder is back.
func remove_rom_folder(path: String) -> void:
	calls.append(["remove_rom_folder", path])
	if _locked or not path in _chosen:
		return
	_chosen.erase(path)
	_use_chosen()


func _use_chosen() -> void:
	_folders = _chosen.duplicate() if not _chosen.is_empty() else [FOUND_FOLDER]
	_folder_source = "chosen" if not _chosen.is_empty() else "emudeck"
	var shown := ", ".join(_folders.map(_display))
	for id in _ids:
		if not _info[id].rom.found:
			_info[id].rom.path = shown
	rom_folder_changed.emit()
	for id in _ids:
		changed.emit(id)


## Answers at once from TREE; a folder that is not in it lists its nearest parent that is.
func browse(path: String) -> void:
	calls.append(["browse", path])
	var dir: String = path if not path.is_empty() else _folders[0]
	while dir != "/" and not _exists(dir):
		dir = dir.get_base_dir()
	var folders := []
	for name in TREE.get(dir, []):
		var child := dir.path_join(name)
		folders.append({"name": name, "path": child, "roms": ROM_COUNTS.get(child, 0)})
	var places: Array = PLACES.duplicate(true) if _cards else [PLACES[0].duplicate()]
	(
		folder_listed
		. emit(
			path,
			{
				"ok": true,
				"path": dir,
				"roms": ROM_COUNTS.get(dir, 0),
				"folders": folders,
				"places": places,
			}
		)
	)


func search_sd_card() -> void:
	calls.append(["search_sd_card"])
	_search = {"status": "running", "results": []}
	_search_left = SEARCH_SECONDS if simulate else -1.0
	search_changed.emit()


func cancel_search() -> void:
	calls.append(["cancel_search"])
	if _search.status == "running":
		_search_left = -1.0
		_search = {"status": "cancelled", "results": []}
		search_changed.emit()


func search_info() -> Dictionary:
	return _search.duplicate(true)


## Ends a running search with the demo results (or "no_card" in that scenario).
func finish_search() -> void:
	if _search.status != "running":
		return
	_search_left = -1.0
	if not _cards:
		_search = {"status": "no_card", "results": []}
	else:
		var results := []
		for found in [
			[SD_CARD, "SD card", "Emulation/roms/n64"],
			[SD_CARD, "SD card", "Emulation/roms/snes"],
			[USB_DRIVE, "Backup", "Roms/N64"],
		]:
			var path: String = found[0].path_join(found[2])
			(
				results
				. append(
					{
						"path": path,
						"display": path,
						"label": found[1],
						"folder": found[2],
						"roms": ROM_COUNTS[path],
					}
				)
			)
		_search = {"status": "done", "results": results}
	search_changed.emit()


static func _exists(path: String) -> bool:
	return TREE.has(path) or path.get_file() in TREE.get(path.get_base_dir(), [])


static func _display(path: String) -> String:
	if path == FAKE_HOME:
		return "~"
	if path.begins_with(FAKE_HOME + "/"):
		return "~/" + path.substr(FAKE_HOME.length() + 1)
	return path


func _start(action: String, id: String) -> void:
	calls.append([action, id])
	if simulate and _info[id].busy.action == "":
		_set_busy(id, action, 0.0, "")
		_jobs[id] = true
		changed.emit(id)


func _process(delta: float) -> void:
	if not simulate:
		return
	if _art_wait > 0.0:
		_art_wait -= delta
		if _art_wait <= 0.0:
			deliver_art()
	if _search_left > 0.0:
		_search_left -= delta
		if _search_left <= 0.0:
			finish_search()
	if _new_wait > 0.0:
		_new_wait -= delta
		if _new_wait <= 0.0:
			add_new_ports()
	for id in _ids:
		var port: Dictionary = _info[id]
		if _jobs.has(id) and port.busy.action in ["install", "update"]:
			_advance(id, delta)
		if port.running:
			_play_left[id] -= delta
			if _play_left[id] <= 0.0:
				port.running = false
				_extracted[id] = true
				changed.emit(id)
				exited.emit(id)


func _advance(id: String, delta: float) -> void:
	var port: Dictionary = _info[id]
	port.busy.progress = minf(port.busy.progress + delta / BUSY_SECONDS, 1.0)
	port.busy.detail = "%.1f MB of 32.1 MB" % (32.1 * port.busy.progress)
	if port.busy.progress >= 1.0:
		_jobs.erase(id)
		_set_busy(id, "", -1.0, "")
		_set_installed(id, port.latest_version if port.latest_version != "" else "9.3.1")
		port.update_available = false
	changed.emit(id)

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
##   rom-config   as showcase, with the ROM folder set in config.ini (ROM-12)
##   no-card      as showcase, with no SD card or drive (ROM-14)
##
## The ROM folder chooser (ROM-11) browses a small made-up tree (TREE, ROM_COUNTS) under
## /home/deck and two drives; the SD card search (ROM-14) answers SEARCH_RESULTS after
## SEARCH_SECONDS, or on `finish_search` when `simulate` is off.
##
## A port that is not installed has no game files either, so it shows its note too.
##
## The first two ports have placeholder cover art, drawn in code (never a real image), and
## the other two show their monogram, so a screenshot has both looks (ART-5, ART-6).

signal changed(id: String)
signal launched(id: String)
signal exited(id: String)
signal rom_folder_changed
signal folder_listed(path: String, listing: Dictionary)
signal search_changed

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
]
const ART_PORTS := ["soh", "2ship"]
const ART_SIZE := Vector2i(920, 430)
const ART_DELAY := 2.0
const ROM_FOLDER := "~/Emulation/roms/n64"
const FAKE_HOME := "/home/deck"
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

const SHIP_NOTE := (
	"The first launch makes the game files from your ROM\nIf it"
	+ " then asks to run the game, close it and press Play again"
)

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
		"first_run":
		(
			"The first launch needs a mouse or keyboard once (the trackpad works): answer Yes"
			+ " and pick sf64.z64\nLater launches do not"
		),
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
		"first_run":
		(
			"The first launch needs a mouse or keyboard once (the trackpad works) to answer its"
			+ " questions\nLater launches do not"
		),
		"wanted": ["US"],
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
var _folder := FAKE_HOME.path_join("Emulation/roms/n64")
var _folder_source := "emudeck"
var _locked := false
var _cards := true
var _search := {"status": "idle", "results": []}
var _search_left := -1.0


func _init(scenario := "showcase") -> void:
	for demo in DEMO:
		_ids.append(demo.id)
		_info[demo.id] = {
			"id": demo.id,
			"name": demo.name,
			"game": demo.game,
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
		}
	_apply_scenario(scenario if scenario in SCENARIOS else "showcase")
	for id in _ids:
		_extracted[id] = _info[id].installed and scenario != "first-run"
	if scenario == "rom-config":
		_locked = true
		_folder = "/mnt/games/n64"
		_folder_source = "config"
	_cards = scenario != "no-card"
	if scenario == "art-late":
		_art_wait = ART_DELAY
	else:
		deliver_art(false)


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
		"showcase", "art-late", "rom-config", "no-card":
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
	return {
		"path": _display(_folder),
		"full": _folder,
		"source": _folder_source,
		"locked": _locked,
		"config_file": "~/.config/anchorage/config.ini",
	}


## Records the choice; with the folder unlocked it becomes the folder and every port is
## "rescanned" (nothing changes in the demo data but the folder shown).
func set_rom_folder(path: String) -> void:
	calls.append(["set_rom_folder", path])
	if _locked:
		return
	_folder = path
	_folder_source = "chosen"
	for id in _ids:
		if not _info[id].rom.found:
			_info[id].rom.path = _display(path)
	rom_folder_changed.emit()
	for id in _ids:
		changed.emit(id)


## Answers at once from TREE; a folder that is not in it lists its nearest parent that is.
func browse(path: String) -> void:
	calls.append(["browse", path])
	var dir := path if not path.is_empty() else _folder
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

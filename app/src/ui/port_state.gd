extends RefCounted
## What the home screen shows and does for one `Ports.info(id)` dictionary (HOME-2,
## HOME-4, HOME-9). Pure functions, so tests need no scene.

const BUSY_VERBS := {
	"install": "Installing",
	"update": "Updating",
	"remove": "Removing",
	"launch": "Starting",
}
const ACTION_LABELS := {"install": "Install", "update": "Update", "launch": "Play"}


## One of not_installed, ready, update, rom_missing, busy, playing. A port that is
## installed and short of a ROM is rom_missing, even with an update out.
static func state(info: Dictionary) -> String:
	if info.running:
		return "playing"
	if BUSY_VERBS.has(info.busy.action):
		return "busy"
	if not info.installed:
		return "not_installed"
	if not info.rom.found:
		return "rom_missing"
	if info.update_available:
		return "update"
	return "ready"


static func badge(info: Dictionary) -> String:
	match state(info):
		"playing":
			return "Playing"
		"busy":
			var verb: String = BUSY_VERBS[info.busy.action]
			var progress: float = info.busy.progress
			if info.busy.action in ["install", "update"] and progress >= 0.0:
				return "%s %d%%" % [verb, int(progress * 100.0)]
			return verb
		"not_installed":
			return "Not installed"
		"rom_missing":
			return "ROM missing"
		"update":
			return "Update available"
	return "Ready"


## What accept does: "install", "update", "launch", or "" when it only shows a hint
## (ROM missing) or the port is busy or running.
static func primary(info: Dictionary) -> String:
	match state(info):
		"not_installed":
			return "install"
		"update":
			return "update"
		"ready":
			return "launch"
	return ""


## True while a download can be cancelled with back (HOME-8).
static func cancellable(info: Dictionary) -> bool:
	return info.busy.action in ["install", "update"]


## "The Legend of Zelda: Ocarina of Time" -> ["The Legend of Zelda", "Ocarina of Time"];
## a title without a colon has no kicker.
static func split_title(game: String) -> Array[String]:
	var colon := game.find(":")
	if colon < 0:
		return ["", game]
	return [game.substr(0, colon).strip_edges(), game.substr(colon + 1).strip_edges()]


## The short name the community uses: "Ocarina of Time" -> "OoT", "Star Fox 64" -> "SF64".
static func monogram(game: String) -> String:
	var out := ""
	for word in split_title(game)[1].split(" ", false):
		var first := word.left(1)
		if word.is_valid_int():
			out += word
		elif first == first.to_lower() and first != first.to_upper():
			out += first
		else:
			out += first.to_upper()
	return out


## The card's short name: the catalog's `monogram` when it has one, else built from the title.
static func short_name(info: Dictionary) -> String:
	var given: String = info.get("monogram", "")
	return given if not given.is_empty() else monogram(info.game)


## `error` split into its title line and the detail below it.
static func error_parts(error: String) -> Array[String]:
	var newline := error.find("\n")
	if newline < 0:
		return [error, ""]
	return [error.left(newline), error.substr(newline + 1).strip_edges()]


## "NTSC-U 1.0, NTSC-U 1.1 and 6 more" for long lists.
static func wanted_text(wanted: Array) -> String:
	if wanted.is_empty():
		return ""
	if wanted.size() <= 3:
		if wanted.size() == 1:
			return wanted[0]
		return "%s or %s" % [", ".join(wanted.slice(0, -1)), wanted[-1]]
	return "%s and %d more" % [", ".join(wanted.slice(0, 2)), wanted.size() - 2]

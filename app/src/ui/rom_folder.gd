extends Control
## The ROM folder chooser (ROM-11, ROM-12, ROM-14, ROM-17). It starts in the first ROM
## folder, with the chosen folders (accept removes one) and then the home folder and every
## drive as starting points on the left. The D-pad moves, accept opens, back goes up (and
## leaves at a starting point), and `Use this folder` (or the `options` binding) adds the
## folder shown. The first entry searches the SD card. It talks only to `ports` (PORT-14),
## which lists folders and searches off the main loop.

signal closed

enum View { BROWSE, SEARCH, LOCKED }

const SOURCES := {
	"config": "set in config.ini",
	"chosen": "chosen here",
	"emudeck": "from EmuDeck's settings",
	"retrodeck": "from RetroDECK's settings",
	"default": "found in its usual place",
	"mount": "found on a drive",
	"search": "found by the SD card search",
	"fallback": "no ROMs found yet",
}

## A chosen folder's row holds two lines (ROM-17).
const CHOSEN_HEIGHT := 72
## Longer folder names are shortened in the chosen list; the status line shows them whole.
const SHORT_LIMIT := 24

var ports: Node
var view := View.BROWSE
## The folder shown, and the listing `ports` gave for it.
var _path := ""
var _listing := {}
## The folder asked for last; other answers are stale.
var _requested := ""
## A folder to focus once its parent is listed (after going up).
var _focus_path := ""
var _rows: Array[Button] = []
var _place_buttons: Array[Button] = []
## The chosen ROM folders (ROM-17), above the places.
var _chosen_buttons: Array[Button] = []
var _focused: Button
var _scroll_target: Button

@onready var _now: Label = %Now
@onready var _places_panel: Control = %PlacesPanel
@onready var _places: VBoxContainer = %Places
@onready var _chosen_title: Label = %ChosenTitle
@onready var _chosen_box: VBoxContainer = %Chosen
@onready var _chosen_gap: Control = %ChosenGap
@onready var _where: Label = %Where
@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows_box: VBoxContainer = %Rows
@onready var _message: Control = %Message
@onready var _message_title: Label = %MessageTitle
@onready var _message_body: Label = %MessageBody
@onready var _search_progress: ProgressBar = %SearchProgress
@onready var _status: Label = %Status
@onready var _hint_bar: PanelContainer = %HintBar


func _ready() -> void:
	ports.folder_listed.connect(_on_listed)
	ports.search_changed.connect(_on_search_changed)
	ports.rom_folder_changed.connect(_on_folders_changed)
	_show_now()
	var info: Dictionary = ports.rom_folder_info()
	if info.locked:
		_show_locked(info)
		return
	_focus_path = "search"
	_open(info.full)


func _exit_tree() -> void:
	ports.folder_listed.disconnect(_on_listed)
	ports.search_changed.disconnect(_on_search_changed)
	ports.rom_folder_changed.disconnect(_on_folders_changed)


## The text the screen shows, for tests: where, the chosen folders, the rows (with counts)
## and the status.
func shown_text() -> String:
	var lines: Array[String] = [_now.text, _where.text]
	lines.append_array(chosen_texts())
	if _message.visible:
		lines.append_array([_message_title.text, _message_body.text])
	for row in _rows:
		lines.append(row.text + (" · " + _count_of(row) if not _count_of(row).is_empty() else ""))
	lines.append(_status.text)
	return "\n".join(lines)


func hint_text() -> String:
	return _hint_bar.text()


## The row labels, in order.
func row_texts() -> Array:
	return _rows.map(func(row: Button) -> String: return row.text)


func place_texts() -> Array:
	return _place_buttons.map(func(b: Button) -> String: return b.text)


## The chosen folders as listed (in full), each with its second line: `1 port`, `Not found`.
func chosen_texts() -> Array:
	return _chosen_buttons.map(
		func(b: Button) -> String: return "%s · %s" % [b.get_meta("text"), _count_of(b)]
	)


func current_path() -> String:
	return _path


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	# Taken first: closing removes the screen from the tree.
	var viewport := get_viewport()
	if event.is_action_pressed("ui_cancel"):
		_back()
	elif event.is_action_pressed("options") and view == View.BROWSE and not _path.is_empty():
		_choose(_path)
	else:
		return
	viewport.set_input_as_handled()


func _back() -> void:
	match view:
		View.SEARCH:
			if ports.search_info().status == "running":
				ports.cancel_search()
			view = View.BROWSE
			_focus_path = "search"
			_show_listing()
		View.LOCKED:
			closed.emit()
		_:
			if _at_start():
				closed.emit()
			else:
				_focus_path = _path
				_open(_path.get_base_dir())


## At a starting point (home or a drive) or at `/`, back leaves the screen.
func _at_start() -> bool:
	if _path == "/" or _path.is_empty():
		return true
	for place in _listing.get("places", []):
		if place.path == _path:
			return true
	return false


func _open(path: String) -> void:
	_requested = path
	ports.browse(path)


func _on_listed(path: String, listing: Dictionary) -> void:
	if path != _requested or view == View.LOCKED:
		return
	_listing = listing
	_path = listing.path
	if view == View.BROWSE:
		_show_listing()


func _choose(path: String) -> void:
	ports.set_rom_folder(path)
	closed.emit()


## The folders changed, or a scan found one missing or back (ROM-17).
func _on_folders_changed() -> void:
	_show_now()
	if view == View.BROWSE and not _listing.is_empty():
		_rebuild_side()


func _show_now() -> void:
	var info: Dictionary = ports.rom_folder_info()
	var several: int = info.get("folders", []).size()
	if info.path.is_empty():
		_now.text = "Looking for the ROM folder"
	elif several > 1:
		_now.text = "Now %d folders, %s" % [several, SOURCES.get(info.source, "")]
	else:
		_now.text = "Now %s, %s" % [info.path, SOURCES.get(info.source, "")]


func _show_locked(info: Dictionary) -> void:
	view = View.LOCKED
	_places_panel.visible = false
	_scroll.visible = false
	_message.visible = true
	var shown: Array = info.get("folders", []).map(func(f: Dictionary) -> String: return f.path)
	_where.text = ", ".join(shown) if shown.size() > 1 else info.path
	var one := shown.size() <= 1
	_message_title.text = (
		"The ROM folder is set in config.ini" if one else "The ROM folders are set in config.ini"
	)
	var file: String = info.config_file if not info.config_file.is_empty() else "config.ini"
	_message_body.text = (
		(
			"[roms] directory in %s names %s, and Anchorage never changes that file\n"
			% [file, "it" if one else "them"]
		)
		+ "Remove that line to choose folders here"
	)
	_status.text = ""
	_hint_bar.show_hints([["ui_cancel", "Back"], ["quit", "Quit"]])


# Browsing -----------------------------------------------------------------------------


func _show_listing() -> void:
	_where.text = _shown(_path)
	_places_panel.visible = true
	_message.visible = false
	_build_side()
	_clear_rows()
	_add_row("Search the SD card", "", _start_search, "search")
	var here: int = _listing.get("roms", 0)
	_add_row("Use this folder", _count(here) if here > 0 else "", _choose.bind(_path), "use")
	for folder in _listing.get("folders", []):
		var count: String = _count(folder.roms) if folder.roms > 0 else ""
		_add_row(folder.name, count, _open.bind(folder.path), folder.path)
	_link_rows()
	var target := _rows[0]
	if not _focus_path.is_empty():
		for row in _rows:
			if row.get_meta("key") == _focus_path:
				target = row
	elif _rows.size() > 2:
		target = _rows[2]
	else:
		target = _rows[1]
	_focus_path = ""
	target.grab_focus()
	_refresh_hints()
	# Follow-focus scrolled before the new rows were laid out: scroll again a frame later.
	_scroll_target = target
	if not get_tree().process_frame.is_connected(_scroll_to):
		get_tree().process_frame.connect(_scroll_to, CONNECT_ONE_SHOT)


func _scroll_to() -> void:
	if is_instance_valid(_scroll_target) and _scroll_target.is_inside_tree():
		_scroll.ensure_control_visible(_scroll_target)
	_scroll_target = null


## The left side: the chosen folders (ROM-17), then the starting points.
func _build_side() -> void:
	for button in _place_buttons + _chosen_buttons:
		button.get_parent().remove_child(button)
		button.queue_free()
	_place_buttons.clear()
	_chosen_buttons.clear()
	var info: Dictionary = ports.rom_folder_info()
	var seen := {}
	for folder in info.get("folders", []):
		seen[folder.full] = folder
	for path: String in info.get("chosen", []):
		var button := _side_button("", "chosen", path)
		var mark := _chosen_mark(seen.get(path, {}))
		button.set_meta("text", _shown(path))
		button.set_meta("count", mark)
		button.custom_minimum_size.y = CHOSEN_HEIGHT
		button.add_child(_two_lines(_short(_shown(path)), mark))
		button.pressed.connect(_remove.bind(path))
		_chosen_box.add_child(button)
		_chosen_buttons.append(button)
	for node: Control in [_chosen_title, _chosen_box, _chosen_gap]:
		node.visible = not _chosen_buttons.is_empty()
	var current := _current_place()
	for place in _listing.get("places", []):
		var button := _side_button(place.label, "place", place.path)
		if place.path == current:
			button.theme_type_variation = "CurrentButton"
		button.pressed.connect(_go_to.bind(place.path))
		_places.add_child(button)
		_place_buttons.append(button)


## A chosen folder's row: the folder, and below it what the last scan found there.
func _two_lines(top: String, bottom: String) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_right = -24
	for line in [[top, "FieldValue"], [bottom, "Dim"]]:
		var label := Label.new()
		label.text = line[0]
		label.theme_type_variation = line[1]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 1
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
	return box


## How a chosen folder did in the last scan (ROM-17), for its row.
static func _chosen_mark(folder: Dictionary) -> String:
	match folder.get("status", ""):
		"missing":
			return "Not found"
		"ok":
			var n: int = folder.ports
			return "No port uses it" if n == 0 else "%d port%s" % [n, "" if n == 1 else "s"]
	return "Not scanned yet"


## A long folder name keeps its start (`~`, a drive) and its last two folders.
static func _short(text: String) -> String:
	if text.length() <= SHORT_LIMIT:
		return text
	var parts := text.split("/")
	var tail := "/".join(parts.slice(-2))
	if text.contains(" › "):
		return text.get_slice(" › ", 0) + " › …/" + tail
	if text.begins_with("/") and parts.size() > 4:
		return "/%s/%s/…/%s" % [parts[1], parts[2], tail]
	return ("~/…/" if text.begins_with("~/") else "…/") + tail


func _side_button(text: String, key: String, path: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.set_meta("key", key)
	button.set_meta("path", path)
	button.focus_entered.connect(_on_focus.bind(button))
	button.mouse_entered.connect(button.grab_focus)
	return button


## Builds the left side again, keeping the focus there: on the same place, or on the chosen
## folder that took the removed one's position.
func _rebuild_side() -> void:
	var was_chosen := _chosen_buttons.find(_focused)
	var was_place: String = (
		_focused.get_meta("path") if _focused != null and _focused in _place_buttons else ""
	)
	_build_side()
	_link_rows()
	var target: Button = null
	if was_chosen >= 0:
		if not _chosen_buttons.is_empty():
			target = _chosen_buttons[mini(was_chosen, _chosen_buttons.size() - 1)]
		elif not _place_buttons.is_empty():
			target = _place_buttons[0]
	elif not was_place.is_empty():
		for button in _place_buttons:
			if button.get_meta("path") == was_place:
				target = button
	if target != null:
		target.grab_focus()
	_refresh_hints()


## ROM-17: accept on a chosen folder removes it; `ports` rescans and says so.
func _remove(path: String) -> void:
	ports.remove_rom_folder(path)


## The starting point the shown folder is in (the longest matching one).
func _current_place() -> String:
	var best := ""
	for place in _listing.get("places", []):
		var p: String = place.path
		if (_path == p or _path.begins_with(p.path_join(""))) and p.length() > best.length():
			best = p
	return best


func _go_to(path: String) -> void:
	_focus_path = ""
	_open(path)


func _clear_rows() -> void:
	for row in _rows:
		_rows_box.remove_child(row)
		row.queue_free()
	_rows.clear()
	_focused = null


func _add_row(text: String, count: String, action: Callable, key: String) -> Button:
	var row := Button.new()
	row.text = text
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.set_meta("key", key)
	if not count.is_empty():
		_add_count(row, count)
	row.pressed.connect(func() -> void: action.call())
	row.focus_entered.connect(_on_focus.bind(row))
	row.mouse_entered.connect(row.grab_focus)
	_rows_box.add_child(row)
	_rows.append(row)
	return row


## A dim text at the right end of a row: a count, or `Not found`.
func _add_count(row: Button, count: String) -> void:
	var label := Label.new()
	label.theme_type_variation = "Dim"
	label.text = count
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_right = -24
	row.add_child(label)
	row.set_meta("count", count)


## Up and down along the rows and along the left side (chosen folders, then places); left
## goes to the current place, right back to the rows.
func _link_rows() -> void:
	var side := _side()
	for list: Array[Button] in [_rows, side]:
		for i in list.size():
			var control := list[i]
			control.focus_neighbor_top = control.get_path_to(list[maxi(i - 1, 0)])
			control.focus_neighbor_bottom = control.get_path_to(list[mini(i + 1, list.size() - 1)])
	var place: Button = null
	for button in _place_buttons:
		if button.theme_type_variation == "CurrentButton" or place == null:
			place = button
	if place == null and not side.is_empty():
		place = side[0]
	for row in _rows:
		var own := row.get_path_to(row)
		row.focus_neighbor_right = own
		row.focus_neighbor_left = row.get_path_to(place) if place != null else own
	for button in side:
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(_rows[0]) if not _rows.is_empty() else ""


func _side() -> Array[Button]:
	var side: Array[Button] = []
	side.append_array(_chosen_buttons)
	side.append_array(_place_buttons)
	return side


func _on_focus(control: Button) -> void:
	_focused = control
	if control in _rows:
		for button in _side():
			button.focus_neighbor_right = button.get_path_to(control)
	_status.text = _describe(control)
	_refresh_hints()


func _describe(control: Button) -> String:
	var key: String = control.get_meta("key")
	if view == View.SEARCH:
		return "" if _message.visible else _search_status()
	match key:
		"search":
			return "Finds the folders with ROM files on the SD card and other drives"
		"use":
			return _describe_use()
		"place", "chosen":
			return _describe_side(control)
	for folder in _listing.get("folders", []):
		if folder.path == key:
			var held: String = _count(folder.roms) if folder.roms > 0 else "no ROM files"
			return "“%s” holds %s" % [folder.name, held]
	return ""


func _describe_use() -> String:
	if _path in ports.rom_folder_info().get("chosen", []):
		return "%s is one of your ROM folders" % _shown(_path)
	var here: int = _listing.get("roms", 0)
	return "%s holds %s" % [_shown(_path), _count(here) if here > 0 else "no ROM files"]


## A place, or what a chosen folder gives from the last scan (ROM-17).
func _describe_side(control: Button) -> String:
	var path: String = control.get_meta("path")
	if control.get_meta("key") == "place":
		return "Starts in %s" % path
	var shown: String = control.get_meta("text")
	for folder in ports.rom_folder_info().get("folders", []):
		if folder.full != path:
			continue
		match folder.status:
			"missing":
				return "%s is not found, so it is skipped" % shown
			"ok":
				if folder.ports == 0:
					return "%s: no port takes its ROM from here" % shown
				var many: bool = folder.ports != 1
				return (
					"%s: %d port%s take%s the ROM from here"
					% [shown, folder.ports, "s" if many else "", "" if many else "s"]
				)
	return "%s: not scanned yet" % shown


func _refresh_hints() -> void:
	var hints := []
	if view == View.SEARCH:
		var running: bool = ports.search_info().status == "running"
		if not running and not _rows.is_empty():
			var key: String = _rows[0].get_meta("key")
			hints.append(["ui_accept", "Search again" if key == "again" else "Use this folder"])
		hints.append(["ui_cancel", "Cancel" if running else "Back"])
	else:
		var key: String = _focused.get_meta("key") if _focused != null else ""
		var accept := {
			"search": "Search", "use": "Use this folder", "place": "Go to", "chosen": "Remove"
		}
		hints.append(["ui_accept", accept.get(key, "Open")])
		hints.append(["options", "Use this folder"])
		hints.append(["ui_cancel", "Close" if _at_start() else "Up"])
	hints.append(["quit", "Quit"])
	_hint_bar.show_hints(hints)


# Searching the SD card (ROM-14) -------------------------------------------------------


func _start_search() -> void:
	view = View.SEARCH
	_render_search()
	ports.search_sd_card()


func _on_search_changed() -> void:
	if view == View.SEARCH:
		_render_search()


func _render_search() -> void:
	var info: Dictionary = ports.search_info()
	_where.text = "SD card search"
	_places_panel.visible = false
	_clear_rows()
	for result in info.results:
		var where: String = result.label
		if not result.get("folder", "").is_empty():
			where += " › " + result.folder
		_add_row(where, _count(result.roms), _choose.bind(result.path), result.path)
	if info.status in ["no_card", "cancelled"] or (info.status == "done" and _rows.is_empty()):
		_add_row("Search again", "", _start_search, "again")
	var message := _search_message(info)
	_message.visible = not message.is_empty()
	_search_progress.visible = info.status == "running"
	if not message.is_empty():
		_message_title.theme_type_variation = "FieldValue"
		_message_title.text = message[0]
		_message_body.text = message[1]
	_status.text = _search_status() if message.is_empty() else ""
	_link_rows()
	if _rows.is_empty():
		# Nothing to focus while it runs; back still cancels.
		get_viewport().gui_release_focus()
	else:
		_rows[0].grab_focus()
	_refresh_hints()


## [title, text] above the rows while the search runs or found nothing, else [].
static func _search_message(info: Dictionary) -> Array:
	match info.status:
		"running":
			return [
				"Searching",
				"Looking through the SD card and other drives, four folders deep",
			]
		"no_card":
			return ["No SD card or drive found", "Insert one, then search again"]
		"cancelled":
			return ["The search stopped", "Search again to look once more"]
	if info.results.is_empty():
		return [
			"No ROM files found",
			"No folder on the SD card or other drives holds ROM files, four folders deep",
		]
	return []


func _search_status() -> String:
	var found: int = ports.search_info().results.size()
	return "%d folder%s with ROM files. Choose one to add it" % [found, "" if found == 1 else "s"]


# Text --------------------------------------------------------------------------------


func _count_of(row: Button) -> String:
	return row.get_meta("count", "")


static func _count(n: int) -> String:
	return "%d ROM file%s" % [n, "" if n == 1 else "s"]


## `path` with the home folder shown as `~` and a drive by its name: `SD card › roms`.
func _shown(path: String) -> String:
	var places: Array = _listing.get("places", [])
	for i in places.size():
		var place: String = places[i].path
		var label: String = "~" if i == 0 else places[i].label
		var joiner := "/" if i == 0 else " › "
		if path == place:
			return label
		if path.begins_with(place + "/"):
			return label + joiner + path.substr(place.length() + 1)
	return path

extends "res://tests/case.gd"
## HOME-1 layout: the cards row at real screen sizes against ports_fake.gd (seven ports),
## driven with keys through the viewport as in test_home.gd.

const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const Catalog := preload("res://src/catalog.gd")
## 16:9 and 16:10 (LOOK-9). Under the stretch mode a 1920x1200 or 2560x1600 screen is
## 1280x800 in logical px; the larger sizes here are a window that big in logical px.
const SIZES := [Vector2(1280, 720), Vector2(1280, 800), Vector2(1920, 1080), Vector2(1920, 1200)]


## The home screen at `size` over the showcase fake; `count` keeps only its first ports.
func _make(size: Vector2, count := 0) -> Control:
	Keys.apply({})
	var ports := PortsFake.new("showcase")
	ports.simulate = false
	if count > 0:
		ports._ids.resize(count)
	var host := Control.new()
	host.size = size
	host.theme = Style.build("mocha", "mauve")
	host.add_child(ports)
	var home := HomeScene.instantiate()
	home.ports = ports
	host.add_child(home)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	return home


func _done(home: Control) -> void:
	var host := home.get_parent()
	host.get_parent().remove_child(host)
	host.free()


func _press(home: Control, keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		home.get_viewport().push_input(key)


func _focus(home: Control) -> Control:
	return home.get_viewport().gui_get_focus_owner()


## Layout and scrolling settle on the frames after a change.
func _frames(count := 2) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


## Seven cards in one row: four and part of the fifth in view, the row scrolls with focus
## both ways, and nothing below the row is pushed off the screen.
func test_seven_cards_scroll_with_focus_and_the_screen_still_fits() -> void:
	for size in SIZES:
		var home := _make(size)
		await _frames()
		var cards: Array = home.get_node("%Cards").get_children()
		eq(cards.size(), 7, "seven cards")
		var bar: Control = home.get_node("%HintBar")
		check(bar.get_global_rect().end.y <= size.y + 0.5, "%s: the hint bar is on screen" % size)
		check(home.get_combined_minimum_size().y <= size.y, "%s: no vertical overflow" % size)
		for i in 4:
			check(home.card_in_view(cards[i]), "%s: card %d in view at the start" % [size, i])
		var scroll: ScrollContainer = home.get_node("%CardsScroll")
		var view := Rect2(scroll.global_position, scroll.size)
		check(view.intersects(cards[4].get_global_rect()), "%s: part of the fifth shows" % size)
		check(not home.card_in_view(cards[4]), "%s: but not all of it" % size)
		for i in range(1, 7):
			_press(home, KEY_RIGHT)
			await _frames()
			eq(_focus(home), cards[i], "%s: right to card %d" % [size, i])
			check(home.card_in_view(cards[i]), "%s: card %d scrolled into view" % [size, i])
		_press(home, KEY_RIGHT)
		eq(_focus(home), cards[6], "%s: right stops at the last card" % size)
		check(not home.card_in_view(cards[0]), "%s: the first card scrolled away" % size)
		_press(home, KEY_DOWN)
		_press(home, KEY_UP)
		eq(_focus(home), cards[6], "%s: up and down stay in the row" % size)
		for i in range(5, -1, -1):
			_press(home, KEY_LEFT)
			await _frames()
			eq(_focus(home), cards[i], "%s: left to card %d" % [size, i])
			check(home.card_in_view(cards[i]), "%s: card %d scrolled back into view" % [size, i])
		eq(scroll.scroll_horizontal, 0, "%s: back at the start" % size)
		_done(home)


func test_four_cards_share_the_row_without_scrolling() -> void:
	var home := _make(Vector2(1280, 720), 4)
	await _frames()
	eq(home.get_node("%Cards").get_child_count(), 4, "a four-port catalog")
	for card in home.get_node("%Cards").get_children():
		eq(card.custom_minimum_size.x, 0.0, "no fixed width with four cards")
		check(home.card_in_view(card), "all four in view")
	var row: Control = home.get_node("%Cards")
	var scroll: ScrollContainer = home.get_node("%CardsScroll")
	check(absf(row.size.x - scroll.size.x) < 1.0, "the four fill the row's width")
	_done(home)


## Finding: the first-launch notes filled all three lines of the description at 1280x720
## and read as cut off ("...Later launches do not"). Every catalog note, and every demo
## one, fits the description's lines with the panel around it (PORT-17).
func test_every_first_run_note_fits_the_detail_panel() -> void:
	var notes := {"(too long, to prove the check)": "Far too long a note ".repeat(30)}
	for port in Catalog.load_default()["ports"]:
		notes["catalog " + port["id"]] = port["first_run"]
	for size in SIZES:
		var home := _make(size)
		for id in home.ports.list():
			notes["demo " + id] = home.ports.info(id).first_run
		var detail: Control = home.get_node("%Detail")
		var label: Label = detail.get_node("%Description")
		var clip: Control = detail.get_node("Clip")
		for name: String in notes:
			var info: Dictionary = home.ports.info("soh")
			info["first_run"] = notes[name]
			detail.show_port(info)
			# With max_lines_visible the label trims its lines, so count them without it.
			var budget := label.max_lines_visible
			label.max_lines_visible = -1
			await _frames()
			var lines := label.get_line_count()
			label.max_lines_visible = budget
			await _frames()
			var fits := lines <= budget
			if name.begins_with("("):
				check(not fits, "%s: a note of %d lines is caught" % [size, lines])
				continue
			check(fits, "%s: %s takes %d lines of %d" % [size, name, lines, budget])
			check(
				clip.get_global_rect().encloses(label.get_global_rect()),
				"%s: %s is inside the panel" % [size, name]
			)
		_done(home)


## LOOK-9: every tile has the cover's shape, so the whole 920x430 cover shows; the extra
## height of 16:10 goes to the detail panel, and the screen is filled to its bottom edge.
func test_the_whole_cover_shows_and_16_10_gives_the_detail_panel_the_height() -> void:
	var panel_height := {}
	var row_height := {}
	for size in SIZES:
		var home := _make(size)
		await _frames(3)
		for card in home.get_node("%Cards").get_children():
			var tile: Vector2 = card.tile_size()
			check(
				absf(tile.x / Style.ART_ASPECT - tile.y) <= 1.0,
				"%s: %s's tile %s has the cover's shape" % [size, card.port_id, tile]
			)
			check(tile.x >= card.size.x - 2 * Style.FOCUS_WIDTH - 0.5, "%s: full width" % size)
		var detail: Control = home.get_node("%Detail")
		var bar: Control = home.get_node("%HintBar")
		eq(bar.get_global_rect().end.y, size.y, "%s: the hint bar sits on the bottom edge" % size)
		check(
			detail.get_global_rect().end.y >= bar.global_position.y - 40.0,
			"%s: the detail panel reaches down to the hint bar" % size
		)
		panel_height[size] = detail.size.y
		row_height[size] = home.get_node("%CardsScroll").size.y
		_done(home)
	var wide := Vector2(1280, 720)
	var tall := Vector2(1280, 800)
	eq(row_height[tall], row_height[wide], "the cards keep their size at 1280x800")
	eq(panel_height[tall] - panel_height[wide], 80.0, "the detail panel gets the 80 px")


## The most the detail panel ever shows: a download of a port with no ROM (busy, the
## versions it takes and the folder), or with a ROM whose name takes two lines. All of it
## is inside the panel at every size, so nothing is cut off (HOME-3, HOME-8, LOOK-9).
func test_the_fullest_detail_panel_fits() -> void:
	for size in SIZES:
		var home := _make(size)
		var ports: Node = home.ports
		ports._set_busy("soh", "install", 0.42, "13.5 MB of 32.1 MB")
		ports._set_rom_missing("soh")
		ports._info["soh"].installed = false
		var long_rom: Dictionary = ports.info("starship").duplicate(true)
		long_rom.busy = ports.info("soh").busy
		long_rom.rom.label = "Star Fox 64 (USA) (Rev 1) (Lylat Wars, Rumble Pak, Expansion).z64"
		var detail: Control = home.get_node("%Detail")
		var clip: Control = detail.get_node("Clip")
		for info: Dictionary in [ports.info("soh"), long_rom]:
			detail.show_port(info)
			await _frames()
			for label: Label in detail.find_children("*", "Label", true, false):
				if label.is_visible_in_tree():
					check(
						clip.get_global_rect().encloses(label.get_global_rect()),
						"%s: %s %s inside the panel" % [size, info.id, label.name]
					)
			var bar: Control = detail.get_node("%DetailProgress")
			check(clip.get_global_rect().encloses(bar.get_global_rect()), "%s: progress" % size)
		_done(home)


## The hint bar keeps to the screen's width in every state of the home screen, including
## the longest: the ROM missing hint's "Choose ROM folder" (HOME-11).
func test_the_hint_bar_fits_in_every_state() -> void:
	for scenario in ["showcase", "rom-missing", "installing", "error", "playing"]:
		var home := _make(Vector2(1280, 720))
		await _frames()
		for i in home.ports.list().size():
			if scenario == "rom-missing" and i == 0:
				_press(home, KEY_ENTER)
			var bar: Control = home.get_node("%HintBar")
			check(
				bar.get_combined_minimum_size().x <= 1280.0,
				"%s, card %d: %s" % [scenario, i, home.hint_text()]
			)
			_press(home, KEY_RIGHT)
		_done(home)


## The menus and dialogs sit inside the screen at every size (LOOK-9).
func test_menus_and_dialogs_fit() -> void:
	for size in SIZES:
		var home := _make(size)
		var screen := Rect2(Vector2.ZERO, size)
		for open: Array in [[KEY_O, "%MenuLayer"], [KEY_F10, "%AppMenuLayer"]]:
			_press(home, open[0])
			await _frames()
			var panel: Control = home.get_node(open[1]).get_child(0)
			check(screen.encloses(panel.get_global_rect()), "%s: %s" % [size, open[1]])
			_press(home, KEY_ESCAPE)
		for steps: Array in [[KEY_ESCAPE], [KEY_O, KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_ENTER]]:
			for key: Key in steps:
				_press(home, key)
			await _frames()
			var dialog: Control = home.get_node("%ConfirmLayer").get_child(0)
			check(
				screen.encloses(dialog.get_global_rect()),
				"%s: %s" % [size, home.get_node("%ConfirmTitle").text]
			)
			_press(home, KEY_ESCAPE)
		_done(home)

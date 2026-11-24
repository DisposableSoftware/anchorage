extends "res://tests/case.gd"
## HOME-1 layout: the cards row at real screen sizes against ports_fake.gd (seven ports),
## driven with keys through the viewport as in test_home.gd.

const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const Catalog := preload("res://src/catalog.gd")


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
	for size in [Vector2(1280, 720), Vector2(1280, 800), Vector2(1920, 1080)]:
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
	var notes := {"(too long, to prove the check)": "Far too long a note ".repeat(12)}
	for port in Catalog.load_default()["ports"]:
		notes["catalog " + port["id"]] = port["first_run"]
	for size in [Vector2(1280, 720), Vector2(1280, 800)]:
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

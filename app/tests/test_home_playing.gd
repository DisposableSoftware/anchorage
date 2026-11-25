extends "res://tests/case.gd"
## HOME-16: the cover art on the Playing overlay, against ports_fake.gd.

const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const SIZES := [Vector2(1280, 720), Vector2(1280, 800), Vector2(1920, 1080), Vector2(1920, 1200)]


func _make(scenario: String, size := Vector2(1280, 720)) -> Control:
	Keys.apply({})
	var ports := PortsFake.new(scenario)
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


func _frames(count := 2) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


## The first port is installed and has its ROM: accept launches it.
func _play(home: Control) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	for pressed in [true, false]:
		key.pressed = pressed
		home.get_viewport().push_input(key)


func _tile(home: Control) -> Control:
	return home.get_node("%PlayingArtTile")


func _emblem(home: Control) -> Control:
	return home.get_node("%PlayingEmblem")


func test_the_running_ports_art_replaces_the_monogram() -> void:
	var home := _make("playing")
	await _frames()
	eq(home.mode, home.Mode.PLAYING, "the playing scenario starts on the overlay")
	check(_tile(home).visible, "the art shows (HOME-16)")
	check(not _emblem(home).visible, "in place of the monogram")
	check(
		_tile(home).clip_children != CanvasItem.CLIP_CHILDREN_DISABLED,
		"clipped to the rounded corners"
	)
	eq(
		home.get_node("%PlayingArt").stretch_mode,
		TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"scaled to cover the tile"
	)
	var card_tile: Vector2 = home.card_for("soh").tile_size()
	check(_tile(home).size.x > card_tile.x, "larger than on the card")
	var shape := _tile(home).size.x / _tile(home).size.y
	check(absf(shape - Style.ART_ASPECT) < 0.01, "in the cover's shape: nothing is cropped")
	var game: Control = home.get_node("%PlayingGame")
	check(_tile(home).global_position.y + _tile(home).size.y <= game.global_position.y, "above")
	eq(home.playing_text(), "Playing Ocarina of Time", "the game below it")
	_done(home)


func test_a_port_without_art_keeps_the_monogram_and_art_arriving_moves_nothing() -> void:
	var home := _make("art-late")
	await _frames()
	_play(home)
	await _frames()
	eq(home.mode, home.Mode.PLAYING, "Play launches the port")
	check(not _tile(home).visible, "no art yet (ART-6)")
	check(_emblem(home).visible, "the monogram shows")
	var game: Control = home.get_node("%PlayingGame")
	var note: Control = home.get_node("%PlayingNote")
	var before := [_emblem(home).size, game.global_position, note.global_position]
	home.ports.deliver_art()
	await _frames()
	eq(home.mode, home.Mode.PLAYING, "still playing")
	check(_tile(home).visible, "the art arrives in place (ART-6)")
	check(not _emblem(home).visible, "the monogram is gone")
	eq(_tile(home).size, before[0], "the same size as the monogram tile")
	eq(game.global_position, before[1], "the title did not move")
	eq(note.global_position, before[2], "nor the note")
	_done(home)


func test_it_fits_at_every_screen_size_with_and_without_art() -> void:
	for size: Vector2 in SIZES:
		for scenario in ["playing", "art-late"]:
			var home := _make(scenario, size)
			if scenario == "art-late":
				_play(home)
			await _frames(3)
			var visible_tile := _tile(home) if _tile(home).visible else _emblem(home)
			check(visible_tile.visible, "a tile shows (%s, %s)" % [size, scenario])
			var box: Control = home.get_node("%PlayingLayer/Center/Box")
			var screen := Rect2(Vector2.ZERO, size)
			var rect := Rect2(box.global_position, box.size)
			check(screen.encloses(rect), "nothing is clipped (%s, %s): %s" % [size, scenario, rect])
			check(
				visible_tile.size.x <= size.x * 0.6,
				"the cover leaves room at the sides (%s)" % size
			)
			_done(home)

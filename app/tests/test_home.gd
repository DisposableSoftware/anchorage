extends "res://tests/case.gd"
## HOME-1 .. HOME-12 against ports_fake.gd: the home scene is instanced in the test
## runner's tree and driven with input events through the viewport.

const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const PortState := preload("res://src/ui/port_state.gd")
const HomeScene := preload("res://scenes/home.tscn")
const Main := preload("res://src/main.gd")


## The home screen over a fake in `scenario`. Actions are only recorded unless
## `simulate` is set.
func _make(scenario := "showcase", simulate := false) -> Control:
	Keys.apply({})
	var ports := PortsFake.new(scenario)
	ports.simulate = simulate
	var host := Control.new()
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


## Presses and releases a key, as the keyboard would.
func _press(home: Control, keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		home.get_viewport().push_input(key)


func _focus(home: Control) -> Control:
	return home.get_viewport().gui_get_focus_owner()


func _calls(home: Control) -> Array:
	return home.ports.calls


func test_cards_in_catalog_order_with_focus_on_the_first() -> void:
	var home := _make()
	var ids := []
	for card in home.get_node("%Cards").get_children():
		ids.append(card.port_id)
	eq(ids, home.ports.list(), "one card per port, in catalog order (HOME-1)")
	eq(_focus(home), home.card_for("soh"), "focus starts on the first card")
	_done(home)


func test_dpad_moves_focus_along_the_row_only() -> void:
	var home := _make()
	_press(home, KEY_RIGHT)
	eq(_focus(home), home.card_for("2ship"), "right moves to the next card (HOME-1)")
	_press(home, KEY_DOWN)
	eq(_focus(home), home.card_for("2ship"), "down stays in the row")
	_press(home, KEY_LEFT)
	_press(home, KEY_LEFT)
	eq(_focus(home), home.card_for("soh"), "left stops at the first card")
	eq(home.focused_card(), home.card_for("soh"), "the screen follows focus")
	_done(home)


func test_badges_name_each_state() -> void:
	var expected := {
		"showcase":
		{
			"soh": "Ready",
			"2ship": "Update available",
			"starship": "Installing 42%",
			"spaghettikart": "ROM missing",
		},
		"fresh": {"soh": "Not installed"},
		"updating": {"soh": "Updating"},
		"playing": {"soh": "Playing"},
	}
	for scenario in expected:
		var home := _make(scenario)
		for id in expected[scenario]:
			eq(home.card_for(id).badge_text(), expected[scenario][id], "%s: %s" % [scenario, id])
		_done(home)


func test_installed_port_without_a_rom_shows_rom_missing_even_with_an_update() -> void:
	var ports := PortsFake.new("rom-missing")
	var info := ports.info("soh")
	ports.free()
	info.update_available = true
	eq(PortState.badge(info), "ROM missing", "HOME-2")
	info.installed = false
	eq(PortState.badge(info), "Not installed", "not installed wins over the ROM")
	eq(PortState.primary(info), "install", "and accept installs it")


func test_detail_shows_versions_and_rom_status() -> void:
	var home := _make("showcase")
	var detail: String = home.get_node("%Detail").shown_text()
	check(detail.contains("Ship of Harkinian"), "port name (HOME-3)")
	check(detail.contains("A PC port of Ocarina of Time"), "description")
	check(detail.contains("9.3.1"), "versions")
	check(detail.contains("Ocarina of Time (USA) (Rev 2).z64"), "matched ROM file")
	_done(home)
	home = _make("offline")
	check(
		home.get_node("%Detail").shown_text().contains("Offline"), "Offline when the check failed"
	)
	_done(home)
	home = _make("rom-missing")
	detail = home.get_node("%Detail").shown_text()
	check(detail.contains("NTSC-U 1.0, NTSC-U 1.1 and 6 more"), "versions it takes: " + detail)
	check(detail.contains("Looked in ~/Emulation/roms/n64"), "folder scanned (ROM-9)")
	_done(home)


func test_the_first_launch_note_shows_until_the_port_made_its_files() -> void:
	var home := _make("first-run")
	var detail: String = home.get_node("%Detail").shown_text()
	check(detail.contains("The first launch makes the game files"), "Shipwright's note (PORT-17)")
	check(detail.contains("press Play again"), "Play again if it asks to run: " + detail)
	home.card_for("starship").grab_focus()
	detail = home.get_node("%Detail").shown_text()
	check(detail.contains("needs a mouse or keyboard once (the trackpad works)"), "Starship's")
	check(detail.contains("Later launches do not"), "later launches need nothing")
	_done(home)
	home = _make("showcase")
	detail = home.get_node("%Detail").shown_text()
	check(not detail.contains("first launch"), "no note once the game files exist: " + detail)
	home.card_for("starship").grab_focus()
	check(
		home.get_node("%Detail").shown_text().contains("first launch"),
		"a port that is not installed yet has no game files either"
	)
	_done(home)


func test_accept_runs_the_primary_action() -> void:
	var cases := [
		["fresh", "soh", [["install", "soh"]]],
		["showcase", "soh", [["launch", "soh"]]],
		["showcase", "2ship", [["update", "2ship"]]],
		["showcase", "spaghettikart", []],
		["showcase", "starship", []],
	]
	for case in cases:
		var home := _make(case[0])
		home.card_for(case[1]).grab_focus()
		_press(home, KEY_ENTER)
		eq(_calls(home), case[2], "%s: accept on %s (HOME-4)" % [case[0], case[1]])
		if case[1] == "spaghettikart":
			var notice: String = home.get_node("%Detail").notice()
			check(
				notice.contains("~/Emulation/roms/n64") and notice.contains("X"),
				"ROM hint: " + notice
			)
		_done(home)


func test_options_menu_lists_what_the_port_allows() -> void:
	var home := _make("showcase")
	_press(home, KEY_O)
	eq(home.mode, home.Mode.MENU, "options opens the menu (HOME-5)")
	eq(_focus(home), home.get_node("%PlayButton"), "focus on Play")
	for button in ["%PlayButton", "%CheckButton", "%RemoveButton"]:
		check(home.get_node(button).visible, button + " shown for an installed port")
	eq(home.card_for("soh").theme_type_variation, "CardSelected", "the card shows the selection")
	_press(home, KEY_DOWN)
	eq(_focus(home), home.get_node("%CheckButton"), "down moves in the menu")
	_press(home, KEY_RIGHT)
	eq(_focus(home), home.get_node("%CheckButton"), "focus stays in the menu")
	_press(home, KEY_ESCAPE)
	eq(home.mode, home.Mode.HOME, "back closes it")
	eq(_focus(home), home.card_for("soh"), "focus back on the card")
	eq(home.card_for("soh").theme_type_variation, "CardFocus", "focus ring again (HOME-12)")
	_press(home, KEY_RIGHT)
	_press(home, KEY_RIGHT)
	_press(home, KEY_O)
	check(not home.get_node("%PlayButton").visible, "no Play while installing")
	check(not home.get_node("%RemoveButton").visible, "no Remove while installing")
	eq(_focus(home), home.get_node("%CheckButton"), "focus on Check for updates")
	_press(home, KEY_ENTER)
	eq(_calls(home), [["refresh"]], "Check for updates runs refresh")
	eq(home.mode, home.Mode.HOME, "and closes the menu")
	_done(home)


## A port short of its ROM shows ROM missing even with an update out, so accept only hints;
## the update is in the options (HOME-4, HOME-5).
func test_the_options_menu_offers_an_update_also_without_a_rom() -> void:
	var home := _make("rom-missing")
	home.ports._info["soh"].update_available = true
	home.ports._info["soh"].installed_version = "9.3.0"
	_press(home, KEY_O)
	var update: Button = home.get_node("%UpdateButton")
	check(update.visible, "Update in the menu")
	eq(_focus(home), home.get_node("%PlayButton"), "focus still starts on Play")
	_press(home, KEY_DOWN)
	eq(_focus(home), update, "Update comes after Play")
	_press(home, KEY_ENTER)
	eq(_calls(home), [["update", "soh"]], "it updates")
	eq(home.mode, home.Mode.HOME, "and closes the menu")
	_done(home)
	home = _make("showcase")
	_press(home, KEY_O)
	check(not home.get_node("%UpdateButton").visible, "no Update when there is none")
	_press(home, KEY_DOWN)
	eq(_focus(home), home.get_node("%CheckButton"), "the hidden button is skipped")
	_done(home)


func test_refresh_checks_and_rescans() -> void:
	var home := _make()
	_press(home, KEY_F5)
	eq(_calls(home), [["refresh"]], "HOME-6")
	_done(home)


func test_remove_asks_first_with_focus_on_cancel() -> void:
	var home := _make("showcase")
	_press(home, KEY_O)
	home.get_node("%RemoveButton").grab_focus()
	_press(home, KEY_ENTER)
	eq(home.mode, home.Mode.CONFIRM, "Remove opens the dialog (HOME-7)")
	eq(_focus(home), home.get_node("%CancelButton"), "focus starts on Cancel")
	eq(home.get_node("%ConfirmTitle").text, "Remove “Ship of Harkinian”?", "names the port")
	check(home.get_node("%ConfirmBody").text.contains("saves and settings"), "saves stay")
	_press(home, KEY_ENTER)
	eq(_calls(home), [], "accept on Cancel removes nothing")
	eq(home.mode, home.Mode.HOME, "and closes the dialog")
	_press(home, KEY_O)
	home.get_node("%RemoveButton").grab_focus()
	_press(home, KEY_ENTER)
	_press(home, KEY_ESCAPE)
	eq([_calls(home), home.mode], [[], home.Mode.HOME], "back cancels")
	_press(home, KEY_O)
	home.get_node("%RemoveButton").grab_focus()
	_press(home, KEY_ENTER)
	_press(home, KEY_RIGHT)
	eq(_focus(home), home.get_node("%ConfirmButton"), "right moves to Remove")
	_press(home, KEY_ENTER)
	eq(_calls(home), [["remove", "soh"]], "accept on Remove removes")
	eq(_focus(home), home.card_for("soh"), "focus back on the card")
	_done(home)


func test_a_download_shows_progress_and_back_cancels_it() -> void:
	var home := _make("installing")
	var card: Control = home.card_for("soh")
	check(card.get_node("%Progress").visible, "progress bar on the card (HOME-8)")
	eq(card.get_node("%Progress").value, 42.0, "at 42 %")
	check(home.get_node("%DetailProgress").is_visible_in_tree(), "and in the detail panel")
	check(home.hint_text().contains("Cancel"), "hint names Cancel: " + home.hint_text())
	_press(home, KEY_ESCAPE)
	eq(_calls(home), [["cancel", "soh"]], "one press of back cancels")
	_done(home)


func test_errors_show_in_the_panel_and_dismiss() -> void:
	for key in [KEY_ENTER, KEY_ESCAPE]:
		var home := _make("error")
		var detail: String = home.get_node("%Detail").shown_text()
		check(detail.begins_with("Could not update “Ship of Harkinian”\n"), "title (HOME-9)")
		check(detail.contains("connection reset by peer"), "detail below it")
		_press(home, key)
		eq(_calls(home), [["dismiss_error", "soh"]], "%s dismisses" % OS.get_keycode_string(key))
		_done(home)
	var home := _make("error", true)
	_press(home, KEY_ENTER)
	check(home.get_node("%Detail").shown_text().contains("9.3.0"), "the details come back")
	_done(home)


func test_playing_overlay_takes_over_until_the_port_exits() -> void:
	var home := _make("showcase", true)
	_press(home, KEY_RIGHT)
	_press(home, KEY_O)
	_press(home, KEY_ENTER)
	eq(home.mode, home.Mode.PLAYING, "Play from the menu launches (HOME-10)")
	eq(home.playing_text(), "Playing Majora's Mask", "overlay names the game")
	_press(home, KEY_F5)
	_press(home, KEY_LEFT)
	eq(_calls(home), [["launch", "2ship"]], "input other than quit is ignored")
	eq(home.hint_text(), "Ctrl+Q Quit Anchorage", "only quit in the hint bar")
	home.ports._process(PortsFake.PLAY_SECONDS + 1.0)
	eq(home.mode, home.Mode.HOME, "back to normal when the port exits")
	eq(_focus(home), home.card_for("2ship"), "with focus where it was")
	_done(home)


func test_hints_follow_the_live_bindings() -> void:
	var home := _make()
	eq(
		home.hint_text(),
		"A Enter Play · Y O Options · X F5 Refresh · Ctrl+Q Quit",
		"default hints (HOME-11)"
	)
	_done(home)
	home = _make()
	Keys.apply({"accept": ["Space", "Pad:RightShoulder"], "options": ["Pad:Start"]})
	home.get_node("%HintBar").show_hints([["ui_accept", "Play"], ["options", "Options"]])
	eq(home.hint_text(), "R1 Space Play · Menu Options", "remapped bindings show")
	# The same hints again (a download's progress) keep the bar as it is (HOME-13).
	var items: Array = home.get_node("%Hints").get_children()
	home.get_node("%HintBar").show_hints([["ui_accept", "Play"], ["options", "Options"]])
	eq(home.get_node("%Hints").get_children(), items, "not rebuilt when nothing changed")
	Keys.apply({})
	home.get_node("%HintBar").show_hints([["ui_accept", "Play"], ["options", "Options"]])
	eq(home.hint_text(), "A Enter Play · Y O Options", "a changed binding rebuilds it")
	_done(home)


func test_mouse_hover_focuses_and_click_accepts() -> void:
	var home := _make("fresh")
	var card: Control = home.card_for("starship")
	card.mouse_entered.emit()
	eq(_focus(home), card, "hover focuses the card (HOME-12)")
	eq(card.theme_type_variation, "CardFocus", "with the focus look")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._gui_input(click)
	eq(_calls(home), [["install", "starship"]], "a click does what accept does")
	_done(home)


func test_cards_with_art_show_it_and_the_others_keep_the_monogram() -> void:
	var home := _make()
	check(home.card_for("soh").has_art(), "a port with art shows it (ART-5)")
	check(home.card_for("2ship").has_art(), "the second too")
	check(not home.card_for("starship").has_art(), "a port without art shows its monogram (ART-6)")
	var soh: Control = home.card_for("soh")
	check(soh.get_node("%ArtTile").clip_children != CanvasItem.CLIP_CHILDREN_DISABLED, "clipped")
	eq(soh.get_node("%Art").stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "covers")
	check(not soh.get_node("%Emblem").visible, "the monogram tile is hidden behind it")
	check(home.card_for("starship").get_node("%Emblem").visible, "the monogram tile shows")
	_done(home)


func test_art_arriving_changes_the_tile_not_the_layout_or_the_focus() -> void:
	var home := _make("art-late")
	var soh: Control = home.card_for("soh")
	check(not soh.has_art(), "the monogram while the art is missing (ART-6)")
	_press(home, KEY_RIGHT)
	var focused := _focus(home)
	eq(focused, home.card_for("2ship"), "focus is on the second card")
	var size_before := soh.get_combined_minimum_size()
	var badge_before: String = soh.badge_text()
	home.ports.deliver_art()
	check(soh.has_art(), "the art shows once it arrives")
	check(home.card_for("2ship").has_art(), "on both cards")
	eq(_focus(home), focused, "focus did not move")
	eq(soh.get_combined_minimum_size(), size_before, "the card did not change size")
	eq(soh.badge_text(), badge_before, "the rest of the card is as it was")
	_done(home)


func test_monogram_and_title_split() -> void:
	eq(PortState.monogram("The Legend of Zelda: Ocarina of Time"), "OoT", "OoT")
	eq(PortState.monogram("The Legend of Zelda: Majora's Mask"), "MM", "MM")
	eq(PortState.monogram("Star Fox 64"), "SF64", "SF64")
	eq(PortState.monogram("Mario Kart 64"), "MK64", "MK64")
	eq(PortState.split_title("Star Fox 64"), ["", "Star Fox 64"] as Array[String], "no kicker")


func test_main_picks_the_fake_when_asked_or_when_there_is_no_service() -> void:
	var ports: Node = Main.make_ports(PackedStringArray(["--fake-ports", "error"]))
	check(ports.get_script() == PortsFake, "--fake-ports forces the fake")
	check(not ports.info("soh").error.is_empty(), "with the named scenario")
	ports.free()
	ports = Main.make_ports(PackedStringArray())
	if not ResourceLoader.exists(Main.PORTS):
		check(ports.get_script() == PortsFake, "the fake until ports.gd exists")
	ports.free()

extends "res://tests/case.gd"
## HOME-14, HOME-15, KEY-7: the app menu and the Quit question, against ports_fake.gd and
## driven through the viewport as in test_home.gd.

const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")


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


## Counts quit_requested, which main.gd answers by quitting.
func _quits(home: Control) -> Array:
	var heard := []
	home.quit_requested.connect(func() -> void: heard.append(true))
	return heard


func test_the_app_menu_opens_and_back_closes_it() -> void:
	var home := _make("showcase")
	var quits := _quits(home)
	_press(home, KEY_RIGHT)
	_press(home, KEY_F10)
	eq(home.mode, home.Mode.APP_MENU, "menu opens the app menu (HOME-14, KEY-7)")
	var entries := []
	for button in home.get_node("%AppMenuLayer").find_children("*", "Button", true, false):
		if button.visible:
			entries.append(button.text)
	eq(entries, ["Check for updates and new ports", "ROM folder", "Quit Anchorage"], "entries")
	eq(_focus(home), home.get_node("%CatalogButton"), "focus on the first entry")
	eq(home.card_for("2ship").theme_type_variation, "Card", "about no card: no selection look")
	eq(home.hint_text(), "A Enter Select · B Escape Close", "hints")
	_press(home, KEY_UP)
	eq(_focus(home), home.get_node("%CatalogButton"), "up stops at the first entry")
	_press(home, KEY_LEFT)
	eq(_focus(home), home.get_node("%CatalogButton"), "focus stays in the menu")
	_press(home, KEY_ESCAPE)
	eq(home.mode, home.Mode.HOME, "back closes it")
	eq(_focus(home), home.card_for("2ship"), "focus back on the card")
	_press(home, KEY_F10)
	_press(home, KEY_F10)
	eq(home.mode, home.Mode.HOME, "menu again closes it too")
	_press(home, KEY_F10)
	_press(home, KEY_ENTER)
	eq(_calls(home), [["refresh"]], "Check for updates and new ports runs refresh (PORT-18)")
	eq(home.mode, home.Mode.HOME, "and closes the menu")
	_press(home, KEY_F10)
	_press(home, KEY_DOWN)
	_press(home, KEY_ENTER)
	check(home.chooser() != null and home.mode == home.Mode.CHOOSER, "ROM folder (ROM-11)")
	home.chooser().closed.emit()
	eq(home.mode, home.Mode.HOME, "the chooser closes back to the cards")
	eq(quits, [], "nothing quit so far")
	_press(home, KEY_F10)
	_press(home, KEY_DOWN)
	_press(home, KEY_DOWN)
	eq(_focus(home), home.get_node("%QuitButton"), "Quit Anchorage is last")
	_press(home, KEY_ENTER)
	eq(quits, [true], "Quit Anchorage quits at once, with no confirmation")
	_done(home)


func test_the_app_menu_works_with_the_mouse() -> void:
	var home := _make("showcase")
	var quits := _quits(home)
	var bar: Control = home.get_node("%HintBar")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bar.item_for("menu").gui_input.emit(click)
	await (Engine.get_main_loop() as SceneTree).process_frame
	eq(home.mode, home.Mode.APP_MENU, "a click on the Menu hint opens the app menu (HOME-14)")
	var quit: Button = home.get_node("%QuitButton")
	quit.mouse_entered.emit()
	eq(_focus(home), quit, "pointing at an entry focuses it")
	quit.pressed.emit()
	eq(quits, [true], "and a click chooses it")
	_done(home)


func test_back_at_the_top_asks_to_quit() -> void:
	var home := _make("showcase")
	var quits := _quits(home)
	_press(home, KEY_ESCAPE)
	eq(home.mode, home.Mode.CONFIRM, "back with nothing open asks (HOME-15)")
	eq(home.get_node("%ConfirmTitle").text, "Quit Anchorage?", "title")
	check(not home.get_node("%ConfirmBody").visible, "no body")
	eq(home.get_node("%CancelButton").text, "Stay", "Stay")
	eq(home.get_node("%ConfirmButton").text, "Quit", "Quit")
	eq(_focus(home), home.get_node("%CancelButton"), "focus on Stay")
	eq(home.card_for("soh").theme_type_variation, "Card", "about no card")
	eq(home.hint_text(), "A Enter Select · B Escape Stay", "hints")
	_press(home, KEY_ENTER)
	eq([quits, home.mode], [[], home.Mode.HOME], "accept on Stay stays")
	eq(_focus(home), home.card_for("soh"), "focus back on the card")
	_press(home, KEY_ESCAPE)
	_press(home, KEY_ESCAPE)
	eq([quits, home.mode], [[], home.Mode.HOME], "back again stays")
	_press(home, KEY_ESCAPE)
	_press(home, KEY_RIGHT)
	eq(_focus(home), home.get_node("%ConfirmButton"), "right moves to Quit")
	_press(home, KEY_ENTER)
	eq(quits, [true], "accept on Quit quits")
	_done(home)
	# The Remove dialog after a Quit one still says Remove.
	home = _make("showcase")
	_press(home, KEY_ESCAPE)
	_press(home, KEY_ESCAPE)
	_press(home, KEY_O)
	home.get_node("%RemoveButton").grab_focus()
	_press(home, KEY_ENTER)
	eq(home.get_node("%ConfirmButton").text, "Remove", "Remove")
	eq(home.get_node("%CancelButton").text, "Cancel", "Cancel")
	check(home.get_node("%ConfirmBody").visible, "with its body")
	_done(home)

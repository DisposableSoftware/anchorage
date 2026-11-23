extends "res://tests/case.gd"
## KEY-1 .. KEY-4

const Keys := preload("res://src/keys.gd")


func test_every_default_token_parses() -> void:
	for binding in Keys.BINDINGS:
		for token in binding[3]:
			check(Keys.parse_token(token) != null, "%s: %s" % [binding[0], token])


func test_tokens() -> void:
	var key := Keys.parse_token("Ctrl+Shift+Q") as InputEventKey
	check(
		key != null and key.keycode == KEY_Q and key.ctrl_pressed and key.shift_pressed,
		"Ctrl+Shift+Q"
	)
	var button := Keys.parse_token("Pad:A") as InputEventJoypadButton
	check(button != null and button.button_index == JOY_BUTTON_A, "Pad:A")
	var motion := Keys.parse_token("Pad:LeftStickUp") as InputEventJoypadMotion
	check(
		motion != null and motion.axis == JOY_AXIS_LEFT_Y and motion.axis_value < 0.0,
		"Pad:LeftStickUp"
	)
	check(Keys.parse_token("nonsense+") == null, "bad token")
	check(Keys.parse_token("Hyper+Q") == null, "bad modifier")
	check(Keys.parse_token("Pad:Nope") == null, "bad pad input")


func test_overrides_replace_defaults_and_bad_ones_are_dropped() -> void:
	var resolved := Keys.resolve({"quit": ["Alt+F4", "nonsense+"], "back": [], "bogus": ["A"]})
	eq(resolved["quit"].size(), 1, "bad token dropped")
	eq(resolved["back"].size(), 0, "empty list unbinds")
	eq(resolved["accept"].size(), 2, "unlisted binding keeps its defaults")


func test_apply_drives_the_input_map() -> void:
	Keys.apply({"quit": ["Alt+F4"]})
	var press := InputEventKey.new()
	press.keycode = KEY_F4
	press.alt_pressed = true
	press.pressed = true
	check(InputMap.event_is_action(press, "quit"), "Alt+F4 quits")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	check(InputMap.event_is_action(pad, "ui_cancel"), "Pad:B goes back")
	var old := InputEventKey.new()
	old.keycode = KEY_Q
	old.ctrl_pressed = true
	old.pressed = true
	check(not InputMap.event_is_action(old, "quit"), "default Ctrl+Q replaced")

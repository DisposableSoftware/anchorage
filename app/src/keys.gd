extends RefCounted
## Key and gamepad bindings (KEY-1 .. KEY-4). A token is a keyboard key with optional
## modifiers (`Ctrl+Shift+Q`, `Enter`, `F4`) or a gamepad input (`Pad:A`, `Pad:DPadUp`,
## `Pad:LeftStickUp`). Key names are Godot's (OS.find_keycode_from_string).

## Config name, input action, description, default tokens. The config name is the key in
## the [keybindings] group of keybindings.ini. spec/keybindings.md lists the same rows.
const BINDINGS := [
	["up", "ui_up", "Move up", ["Up", "Pad:DPadUp", "Pad:LeftStickUp"]],
	["down", "ui_down", "Move down", ["Down", "Pad:DPadDown", "Pad:LeftStickDown"]],
	["left", "ui_left", "Move left", ["Left", "Pad:DPadLeft", "Pad:LeftStickLeft"]],
	["right", "ui_right", "Move right", ["Right", "Pad:DPadRight", "Pad:LeftStickRight"]],
	["accept", "ui_accept", "Accept", ["Enter", "Pad:A"]],
	["back", "ui_cancel", "Back", ["Escape", "Pad:B"]],
	["quit", "quit", "Quit", ["Ctrl+Q"]],
]

const PAD_BUTTONS := {
	"A": JOY_BUTTON_A,
	"B": JOY_BUTTON_B,
	"X": JOY_BUTTON_X,
	"Y": JOY_BUTTON_Y,
	"Back": JOY_BUTTON_BACK,
	"Guide": JOY_BUTTON_GUIDE,
	"Start": JOY_BUTTON_START,
	"LeftStick": JOY_BUTTON_LEFT_STICK,
	"RightStick": JOY_BUTTON_RIGHT_STICK,
	"LeftShoulder": JOY_BUTTON_LEFT_SHOULDER,
	"RightShoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"DPadUp": JOY_BUTTON_DPAD_UP,
	"DPadDown": JOY_BUTTON_DPAD_DOWN,
	"DPadLeft": JOY_BUTTON_DPAD_LEFT,
	"DPadRight": JOY_BUTTON_DPAD_RIGHT,
}

## name -> [axis, direction]
const PAD_AXES := {
	"LeftStickUp": [JOY_AXIS_LEFT_Y, -1.0],
	"LeftStickDown": [JOY_AXIS_LEFT_Y, 1.0],
	"LeftStickLeft": [JOY_AXIS_LEFT_X, -1.0],
	"LeftStickRight": [JOY_AXIS_LEFT_X, 1.0],
	"RightStickUp": [JOY_AXIS_RIGHT_Y, -1.0],
	"RightStickDown": [JOY_AXIS_RIGHT_Y, 1.0],
	"RightStickLeft": [JOY_AXIS_RIGHT_X, -1.0],
	"RightStickRight": [JOY_AXIS_RIGHT_X, 1.0],
	"LeftTrigger": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"RightTrigger": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}


## The input event for a token, or null (and a warning) when it can't be parsed.
static func parse_token(token: String) -> InputEvent:
	if token.begins_with("Pad:"):
		var pad := token.trim_prefix("Pad:")
		if PAD_BUTTONS.has(pad):
			var button := InputEventJoypadButton.new()
			button.button_index = PAD_BUTTONS[pad]
			return button
		if PAD_AXES.has(pad):
			var motion := InputEventJoypadMotion.new()
			motion.axis = PAD_AXES[pad][0]
			motion.axis_value = PAD_AXES[pad][1]
			return motion
		return null
	var parts := token.split("+")
	var key := InputEventKey.new()
	for modifier in parts.slice(0, -1):
		match modifier.to_lower():
			"ctrl":
				key.ctrl_pressed = true
			"shift":
				key.shift_pressed = true
			"alt":
				key.alt_pressed = true
			"super":
				key.meta_pressed = true
			_:
				return null
	var keycode := OS.find_keycode_from_string(parts[-1])
	if keycode == KEY_NONE:
		return null
	key.keycode = keycode
	return key


## name -> Array of InputEvent, for every binding in BINDINGS. `overrides` replaces the
## defaults per name; unknown names and bad tokens are warned about and skipped (KEY-3).
static func resolve(overrides: Dictionary) -> Dictionary:
	var names := BINDINGS.map(func(b): return b[0])
	for name in overrides:
		if not names.has(name):
			push_warning("keybindings.ini: unknown keybinding '%s'" % name)
	var out := {}
	for binding in BINDINGS:
		var tokens: Array = overrides.get(binding[0], binding[3])
		var events := []
		for token in tokens:
			var event := parse_token(token)
			if event == null:
				push_warning("keybindings.ini: bad key '%s' for %s" % [token, binding[0]])
			else:
				events.append(event)
		out[binding[0]] = events
	return out


## Replaces the events of every bound action in the InputMap.
static func apply(overrides: Dictionary) -> void:
	var resolved := resolve(overrides)
	for binding in BINDINGS:
		var action: String = binding[1]
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for event in resolved[binding[0]]:
			InputMap.action_add_event(action, event)

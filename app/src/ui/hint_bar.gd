extends PanelContainer
## The button hint bar (HOME-11): each action of the current screen with the first
## gamepad button and the first key bound to it, read from the live InputMap.

const Keys := preload("res://src/keys.gd")

@onready var _hints: HBoxContainer = %Hints


## `hints`: [[action, label], ...], in the order shown.
func show_hints(hints: Array) -> void:
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	for hint in hints:
		var inputs := Keys.hint(hint[0])
		if inputs[0].is_empty() and inputs[1].is_empty():
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		if not inputs[0].is_empty():
			item.add_child(_cap("PadGlyph", _pad_variation(inputs[0]), inputs[0]))
		if not inputs[1].is_empty():
			item.add_child(_cap("KeyCap", "KeyCapText", inputs[1]))
		var label := Label.new()
		label.theme_type_variation = "Hint"
		label.text = hint[1]
		item.add_child(label)
		_hints.add_child(item)


## The bar's text, e.g. "A Enter Install · Y O Options", for tests.
func text() -> String:
	var items := []
	for item in _hints.get_children():
		var parts := []
		for part in item.get_children():
			parts.append(part.text if part is Label else part.get_child(0).text)
		items.append(" ".join(parts))
	return " · ".join(items)


static func _pad_variation(label: String) -> String:
	return "PadText" + label if label in ["A", "B", "X", "Y"] else "PadText"


static func _cap(panel: String, text_variation: String, text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = panel
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.theme_type_variation = text_variation
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if panel == "PadGlyph":
		label.custom_minimum_size.x = 16
	cap.add_child(label)
	return cap

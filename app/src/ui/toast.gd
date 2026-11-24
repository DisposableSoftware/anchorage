extends PanelContainer
## A short message at the top of the screen that goes away by itself after SECONDS, such as
## the catalog's `2 new ports: Foo, Bar` (PORT-23). It never takes focus or input.

const SECONDS := 5.0
const TOP := 24

var _label := Label.new()
var _left := 0.0


func _ready() -> void:
	theme_type_variation = "Dialog"
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	visible = false
	_label.theme_type_variation = "FieldValue"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	set_process(false)


func show_text(message: String) -> void:
	_label.text = message
	visible = not message.is_empty()
	_left = SECONDS
	set_process(visible)
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE, TOP)


## What it shows, "" while hidden.
func text() -> String:
	return _label.text if visible else ""


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		visible = false
		set_process(false)

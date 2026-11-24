extends PanelContainer
## One port on the home screen: emblem, game title, port name, state badge and, while
## busy, a progress bar (HOME-1, HOME-2, HOME-8, HOME-12). The emblem is the cover art
## when `info.art` has a texture (ART-5), the monogram otherwise (ART-6).

signal activated(card: Control)

const PortState := preload("res://src/ui/port_state.gd")
const Style := preload("res://src/theme.gd")

var port_id := ""
## True while a menu or dialog about this port is open: the selection look.
var selected := false:
	set(value):
		selected = value
		z_index = 1 if value else 0
		_restyle()

@onready var _emblem: PanelContainer = %Emblem
@onready var _monogram: Label = %Monogram
@onready var _art_tile: PanelContainer = %ArtTile
@onready var _art: TextureRect = %Art
@onready var _kicker: Label = %Kicker
@onready var _title: Label = %Title
@onready var _port_name: Label = %PortName
@onready var _progress: ProgressBar = %Progress
@onready var _badge: PanelContainer = %Badge
@onready var _badge_text: Label = %BadgeText


func _ready() -> void:
	focus_entered.connect(_restyle)
	focus_exited.connect(_restyle)
	mouse_entered.connect(_on_mouse_entered)
	_restyle()


## `index` is the catalog position, which picks the emblem colour.
func show_port(info: Dictionary, index: int) -> void:
	port_id = info.id
	var title := PortState.split_title(info.game)
	var variant := index % Style.EMBLEM_COLORS.size()
	_emblem.theme_type_variation = "Emblem%d" % variant
	_monogram.theme_type_variation = "Monogram%d" % variant
	_monogram.text = PortState.monogram(info.game)
	_show_art(info.get("art"))
	# An empty kicker keeps its line, so titles and emblems line up across cards.
	_kicker.text = title[0] if not title[0].is_empty() else " "
	_title.text = title[1]
	_port_name.text = info.name
	var state := PortState.state(info)
	_badge.theme_type_variation = "Badge_" + state
	_badge_text.theme_type_variation = "BadgeText_" + state
	_badge_text.text = PortState.badge(info)
	_progress.visible = PortState.cancellable(info)
	_progress.indeterminate = info.busy.progress < 0.0
	_progress.value = maxf(info.busy.progress, 0.0) * 100.0


func has_art() -> bool:
	return _art_tile.visible


## Both tiles take the same space (the art tile borrows the monogram's minimum width), so
## the art arriving never moves anything.
func _show_art(texture: Variant) -> void:
	_art_tile.custom_minimum_size.x = _emblem.get_combined_minimum_size().x
	_art.texture = texture as Texture2D
	_art_tile.visible = _art.texture != null
	_emblem.visible = _art.texture == null


func badge_text() -> String:
	return _badge_text.text


func _restyle() -> void:
	if has_focus():
		theme_type_variation = "CardFocus"
	elif selected:
		theme_type_variation = "CardSelected"
	else:
		theme_type_variation = "Card"


func _on_mouse_entered() -> void:
	if focus_mode != FOCUS_NONE:
		grab_focus()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		grab_focus()
		accept_event()
		activated.emit(self)

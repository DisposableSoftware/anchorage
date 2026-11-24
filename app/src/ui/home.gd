extends Control
## The home screen (HOME-1 .. HOME-13): one card per port, the focused port's details,
## its options menu, the Remove confirmation, the Playing overlay and the hint bar.
## It talks only to `ports` (PORT-14), which must be set before the node enters the tree.

enum Mode { HOME, MENU, CONFIRM, PLAYING, CHOOSER }

const CardScene := preload("res://scenes/card.tscn")
const ChooserScene := preload("res://scenes/rom_folder.tscn")
const Keys := preload("res://src/keys.gd")
const PortState := preload("res://src/ui/port_state.gd")
const Style := preload("res://src/theme.gd")

var ports: Node
var mode := Mode.HOME
var _cards: Array[Control] = []
## The card the open menu, dialog or overlay is about, and gets focus back afterwards.
var _current: Control
## The ROM folder chooser while it is open (ROM-11).
var _chooser: Control

@onready var _cards_box: HBoxContainer = %Cards
@onready var _detail: PanelContainer = %Detail
@onready var _hint_bar: PanelContainer = %HintBar
@onready var _scrim: ColorRect = %Scrim
@onready var _menu_layer: Control = %MenuLayer
@onready var _menu_title: Label = %MenuTitle
@onready var _menu_game: Label = %MenuGame
@onready var _play_button: Button = %PlayButton
@onready var _update_button: Button = %UpdateButton
@onready var _check_button: Button = %CheckButton
@onready var _rom_folder_button: Button = %RomFolderButton
@onready var _remove_button: Button = %RemoveButton
@onready var _confirm_layer: Control = %ConfirmLayer
@onready var _confirm_title: Label = %ConfirmTitle
@onready var _confirm_body: Label = %ConfirmBody
@onready var _cancel_button: Button = %CancelButton
@onready var _confirm_button: Button = %ConfirmButton
@onready var _playing_layer: Control = %PlayingLayer
@onready var _playing_emblem: PanelContainer = %PlayingEmblem
@onready var _playing_monogram: Label = %PlayingMonogram
@onready var _playing_game: Label = %PlayingGame
@onready var _playing_note: Label = %PlayingNote


func _ready() -> void:
	_scrim.color = get_theme_color("scrim", "Palette")
	var ids: Array = ports.list()
	for i in ids.size():
		var card := CardScene.instantiate()
		_cards_box.add_child(card)
		card.show_port(ports.info(ids[i]), i)
		card.focus_entered.connect(_on_card_focused.bind(card))
		card.activated.connect(_on_card_activated)
		_cards.append(card)
	ports.changed.connect(_on_changed)
	ports.launched.connect(_on_launched)
	ports.exited.connect(_on_exited)
	_play_button.pressed.connect(_on_play)
	_update_button.pressed.connect(_on_update)
	_check_button.pressed.connect(_on_check)
	_rom_folder_button.pressed.connect(_on_rom_folder)
	_remove_button.pressed.connect(_on_remove)
	_cancel_button.pressed.connect(_close)
	_confirm_button.pressed.connect(_on_confirm_remove)
	var menu := [_play_button, _update_button, _check_button, _rom_folder_button, _remove_button]
	for button in menu + [_cancel_button, _confirm_button]:
		button.mouse_entered.connect(button.grab_focus)
	if _cards.is_empty():
		return
	_link_focus(_cards, SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM)
	_link_focus(menu, SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT)
	_link_focus([_cancel_button, _confirm_button], SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM)
	_current = _cards[0]
	_current.grab_focus()
	for card in _cards:
		if ports.info(card.port_id).running:
			_show_playing(card)
	_refresh_view()


## Chains `row` along `back`/`forward` and pins the cross sides to each control, so the
## D-pad moves along the row and never leaves it. A hidden control is skipped by Godot.
static func _link_focus(row: Array, back: Side, forward: Side, side_a: Side, side_b: Side) -> void:
	for i in row.size():
		var control: Control = row[i]
		var own := control.get_path_to(control)
		control.set_focus_neighbor(side_a, own)
		control.set_focus_neighbor(side_b, own)
		control.set_focus_neighbor(back, control.get_path_to(row[maxi(i - 1, 0)]))
		control.set_focus_neighbor(forward, control.get_path_to(row[mini(i + 1, row.size() - 1)]))


func focused_card() -> Control:
	return _current


func card_for(id: String) -> Control:
	for card in _cards:
		if card.port_id == id:
			return card
	return null


func hint_text() -> String:
	return _hint_bar.text()


func playing_text() -> String:
	return "Playing " + _playing_game.text if mode == Mode.PLAYING else ""


func chooser() -> Control:
	return _chooser


func _input(event: InputEvent) -> void:
	# While a port runs only `quit` gets through (HOME-10); main.gd handles it.
	if mode == Mode.PLAYING and not event.is_action("quit"):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _current == null or event.is_echo() or mode == Mode.CHOOSER:
		return
	var handled := true
	match mode:
		Mode.HOME:
			handled = _home_input(event)
		Mode.MENU, Mode.CONFIRM:
			handled = event.is_action_pressed("ui_cancel")
			if handled:
				_close()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _home_input(event: InputEvent) -> bool:
	var id: String = _current.port_id
	var info: Dictionary = ports.info(id)
	if event.is_action_pressed("ui_accept"):
		_accept(id)
	elif event.is_action_pressed("ui_cancel"):
		if not info.error.is_empty():
			ports.dismiss_error(id)
		elif PortState.cancellable(info):
			ports.cancel(id)
	elif event.is_action_pressed("options"):
		_open_menu()
	elif event.is_action_pressed("refresh"):
		ports.refresh()
	else:
		return false
	return true


## What accept does on a card (HOME-4, HOME-9).
func _accept(id: String) -> void:
	var info: Dictionary = ports.info(id)
	if not info.error.is_empty():
		ports.dismiss_error(id)
		return
	match PortState.primary(info):
		"install":
			ports.install(id)
		"update":
			ports.update(id)
		"launch":
			ports.launch(id)
		_:
			if PortState.state(info) != "rom_missing":
				return
			# The hint, then accept again opens the chooser (ROM-11).
			if not _detail.notice().is_empty():
				open_chooser()
				return
			_detail.show_notice(
				(
					(
						"Put a matching ROM in %s and press %s to look again, or press %s to"
						% [info.rom.path, _button("refresh"), _button("ui_accept")]
					)
					+ " choose the folder or search the SD card"
				)
			)
			_hint_bar.show_hints(_hints())


static func _button(action: String) -> String:
	var inputs := Keys.hint(action)
	return inputs[0] if not inputs[0].is_empty() else inputs[1]


## Opens the ROM folder chooser over the home screen (ROM-11).
func open_chooser() -> void:
	if mode != Mode.HOME:
		_close()
	_chooser = ChooserScene.instantiate()
	_chooser.ports = ports
	_chooser.closed.connect(_on_chooser_closed)
	mode = Mode.CHOOSER
	get_viewport().gui_release_focus()
	for card in _cards:
		card.focus_mode = Control.FOCUS_NONE
	add_child(_chooser)


func _on_chooser_closed() -> void:
	remove_child(_chooser)
	_chooser.queue_free()
	_chooser = null
	mode = Mode.HOME
	for card in _cards:
		card.focus_mode = Control.FOCUS_ALL
	_current.grab_focus()
	_refresh_view()


func _on_card_focused(card: Control) -> void:
	if mode != Mode.HOME:
		return
	_current = card
	_refresh_view()


func _on_card_activated(card: Control) -> void:
	if mode == Mode.HOME:
		_current = card
		_accept(card.port_id)


func _on_changed(id: String) -> void:
	var card := card_for(id)
	if card == null:
		return
	card.show_port(ports.info(id), _cards.find(card))
	if card == _current:
		_refresh_view()


func _refresh_view() -> void:
	if mode == Mode.HOME or mode == Mode.PLAYING:
		_detail.show_port(ports.info(_current.port_id))
	_hint_bar.show_hints(_hints())


func _hints() -> Array:
	match mode:
		Mode.MENU:
			return [["ui_accept", "Select"], ["ui_cancel", "Close"]]
		Mode.CONFIRM:
			return [["ui_accept", "Select"], ["ui_cancel", "Cancel"]]
		Mode.PLAYING:
			return [["quit", "Quit Anchorage"]]
	var info: Dictionary = ports.info(_current.port_id)
	if not info.error.is_empty():
		return [["ui_accept", "Dismiss"], ["ui_cancel", "Dismiss"], ["quit", "Quit"]]
	var hints := []
	var primary := PortState.primary(info)
	if not primary.is_empty():
		hints.append(["ui_accept", PortState.ACTION_LABELS[primary]])
	elif PortState.state(info) == "rom_missing" and not _detail.notice().is_empty():
		hints.append(["ui_accept", "Choose ROM folder"])
	if PortState.cancellable(info):
		hints.append(["ui_cancel", "Cancel"])
	hints.append_array([["options", "Options"], ["refresh", "Refresh"], ["quit", "Quit"]])
	return hints


func _open_menu() -> void:
	var info: Dictionary = ports.info(_current.port_id)
	var idle := PortState.state(info) != "busy"
	_menu_title.text = info.name
	_menu_game.text = info.game
	_play_button.visible = info.installed and idle
	_update_button.visible = info.installed and idle and info.update_available
	_remove_button.visible = info.installed and idle
	_set_modal(Mode.MENU, _menu_layer)
	(_play_button if _play_button.visible else _check_button).grab_focus()


func _on_play() -> void:
	var id: String = _current.port_id
	_close()
	ports.launch(id)


func _on_update() -> void:
	var id: String = _current.port_id
	_close()
	ports.update(id)


func _on_check() -> void:
	_close()
	ports.refresh()


func _on_rom_folder() -> void:
	_close()
	open_chooser()


func _on_remove() -> void:
	var info: Dictionary = ports.info(_current.port_id)
	_confirm_title.text = "Remove “%s”?" % info.name
	_confirm_body.text = (
		"Anchorage deletes the installed port. Your saves and settings for %s stay." % info.name
	)
	_menu_layer.visible = false
	_set_modal(Mode.CONFIRM, _confirm_layer)
	_cancel_button.grab_focus()


func _on_confirm_remove() -> void:
	var id: String = _current.port_id
	_close()
	ports.remove(id)


## Opens `layer` over the scrim. Cards can't take focus meanwhile, so the D-pad stays
## inside the menu, and the card shows the selection look instead of the focus ring.
func _set_modal(new_mode: Mode, layer: Control) -> void:
	mode = new_mode
	for card in _cards:
		card.focus_mode = Control.FOCUS_NONE
	_current.selected = true
	_scrim.visible = true
	layer.visible = true
	_hint_bar.show_hints(_hints())


func _close() -> void:
	mode = Mode.HOME
	_scrim.visible = false
	_menu_layer.visible = false
	_confirm_layer.visible = false
	_playing_layer.visible = false
	for card in _cards:
		card.focus_mode = Control.FOCUS_ALL
	_current.selected = false
	_current.grab_focus()
	_refresh_view()


func _on_launched(id: String) -> void:
	var card := card_for(id)
	if card != null:
		_show_playing(card)


func _show_playing(card: Control) -> void:
	if _chooser != null:
		_on_chooser_closed()
	if mode != Mode.HOME:
		_close()
	var info: Dictionary = ports.info(card.port_id)
	var variant := _cards.find(card) % Style.EMBLEM_COLORS.size()
	_playing_emblem.theme_type_variation = "Emblem%d" % variant
	_playing_monogram.theme_type_variation = "Monogram%d" % variant
	_playing_monogram.text = PortState.monogram(info.game)
	_playing_game.text = PortState.split_title(info.game)[1]
	_playing_note.text = "%s is running. Anchorage comes back when it closes." % info.name
	_current = card
	mode = Mode.PLAYING
	_playing_layer.visible = true
	get_viewport().gui_release_focus()
	_hint_bar.show_hints(_hints())


func _on_exited(id: String) -> void:
	if mode == Mode.PLAYING and _current.port_id == id:
		_close()

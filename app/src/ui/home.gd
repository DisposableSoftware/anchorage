extends Control
## The home screen (HOME-1 .. HOME-15): one card per port, the focused port's details,
## its options menu, the app menu, the Remove and Quit confirmations, the Playing overlay
## and the hint bar. It talks only to `ports` (PORT-14), which must be set before the node
## enters the tree.

## The user chose to quit (HOME-14, HOME-15); main.gd quits as it does for `quit`.
signal quit_requested

enum Mode { HOME, MENU, APP_MENU, CONFIRM, PLAYING, CHOOSER }

const CardScene := preload("res://scenes/card.tscn")
const ChooserScene := preload("res://scenes/rom_folder.tscn")
const Keys := preload("res://src/keys.gd")
const PortState := preload("res://src/ui/port_state.gd")
const Style := preload("res://src/theme.gd")
const Toast := preload("res://src/ui/toast.gd")
## Cards that share the row's width; a longer row scrolls sideways (HOME-1).
const FULL_ROW := 4
## How much of a longer row is in view, in cards: four and part of the fifth.
const CARDS_IN_VIEW := 4.3
## The part of a neighbour card kept in view beside the focused one.
const PEEK := 0.3

var ports: Node
var mode := Mode.HOME
var _cards: Array[Control] = []
## The card the open menu, dialog or overlay is about, and gets focus back afterwards.
var _current: Control
## The ROM folder chooser while it is open (ROM-11).
var _chooser: Control
## What the open confirmation does when confirmed: remove the port or quit.
var _on_confirmed: Callable
var _toast: Control

@onready var _cards_scroll: ScrollContainer = %CardsScroll
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
@onready var _app_menu_layer: Control = %AppMenuLayer
@onready var _catalog_button: Button = %CatalogButton
@onready var _app_rom_folder_button: Button = %AppRomFolderButton
@onready var _quit_button: Button = %QuitButton
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
	for id in ports.list():
		_add_card(id)
	_toast = Toast.new()
	add_child(_toast)
	ports.notice_changed.connect(_on_notice)
	ports.changed.connect(_on_changed)
	ports.launched.connect(_on_launched)
	ports.exited.connect(_on_exited)
	_play_button.pressed.connect(_on_play)
	_update_button.pressed.connect(_on_update)
	_check_button.pressed.connect(_on_check)
	_rom_folder_button.pressed.connect(_on_rom_folder)
	_remove_button.pressed.connect(_on_remove)
	_catalog_button.pressed.connect(_on_check)
	_app_rom_folder_button.pressed.connect(_on_rom_folder)
	_quit_button.pressed.connect(quit_requested.emit)
	_cancel_button.pressed.connect(_close)
	_confirm_button.pressed.connect(func() -> void: _on_confirmed.call())
	_hint_bar.hint_clicked.connect(_on_hint_clicked)
	var menu := [_play_button, _update_button, _check_button, _rom_folder_button, _remove_button]
	var app_menu := [_catalog_button, _app_rom_folder_button, _quit_button]
	for button in menu + app_menu + [_cancel_button, _confirm_button]:
		button.mouse_entered.connect(button.grab_focus)
	if _cards.is_empty():
		return
	_cards_scroll.resized.connect(_size_cards)
	_size_cards()
	_link_focus(_cards, SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM)
	_link_focus(menu, SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT)
	_link_focus(app_menu, SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT)
	_link_focus([_cancel_button, _confirm_button], SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM)
	_current = _cards[0]
	_current.grab_focus()
	for card in _cards:
		if ports.info(card.port_id).running:
			_show_playing(card)
	_refresh_view()


func _add_card(id: String) -> Control:
	var card := CardScene.instantiate()
	_cards_box.add_child(card)
	card.show_port(ports.info(id), _cards.size())
	card.focus_entered.connect(_on_card_focused.bind(card))
	card.activated.connect(_on_card_activated)
	_cards.append(card)
	return card


## PORT-23: a catalog fetch appended ports. Their cards go at the end of the row, and the
## notice shows for a few seconds.
func _on_notice() -> void:
	var added := false
	for id in ports.list():
		if card_for(id) == null:
			var card := _add_card(id)
			if not _cards.is_empty() and _cards[0].focus_mode == Control.FOCUS_NONE:
				card.focus_mode = Control.FOCUS_NONE
			added = true
	if added:
		_size_cards()
		_link_focus(_cards, SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM)
	_toast.show_text(ports.notice())


func toast_text() -> String:
	return _toast.text()


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


## Up to FULL_ROW cards share the width. A longer row gets cards a little narrower than a
## four-card row, so part of the next one shows and says the row goes on.
func _size_cards() -> void:
	var width := 0.0
	if _cards.size() > FULL_ROW and _cards_scroll.size.x > 0.0:
		var gaps := _separation() * FULL_ROW
		width = floorf((_cards_scroll.size.x - gaps) / CARDS_IN_VIEW)
	for card in _cards:
		card.custom_minimum_size.x = width
	# The scroll range follows the new sizes only after the container sorts its children.
	_scroll_to_current.call_deferred()


func _separation() -> float:
	return float(_cards_box.get_theme_constant("separation"))


func _scroll_to_current() -> void:
	if _current != null:
		_scroll_to(_current)


## Scrolls the row so `card` is in full view, with PEEK of a card beside it on each side
## that has more cards (HOME-1). Positions come from the index, not the layout, which may
## not have caught up with a resize yet.
func _scroll_to(card: Control) -> void:
	var view := _cards_scroll.size.x
	var width := card.custom_minimum_size.x
	if width <= 0.0 or view <= 0.0:
		_cards_scroll.scroll_horizontal = 0
		return
	var gap := _separation()
	var index := _cards.find(card)
	var left := index * (width + gap)
	var right := left + width
	if index > 0:
		left -= gap + width * PEEK
	if index < _cards.size() - 1:
		right += gap + width * PEEK
	var scroll := float(_cards_scroll.scroll_horizontal)
	if left < scroll:
		scroll = left
	elif right > scroll + view:
		scroll = right - view
	var total := _cards.size() * (width + gap) - gap
	_cards_scroll.scroll_horizontal = int(roundf(clampf(scroll, 0.0, maxf(total - view, 0.0))))


## True when `card` lies wholly inside the visible part of the row.
func card_in_view(card: Control) -> bool:
	var view := Rect2(_cards_scroll.global_position, _cards_scroll.size).grow(0.5)
	return view.encloses(card.get_global_rect())


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
		Mode.APP_MENU:
			handled = event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")
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
		else:
			_ask_to_quit()
	elif event.is_action_pressed("options"):
		_open_menu()
	elif event.is_action_pressed("refresh"):
		ports.refresh()
	elif event.is_action_pressed("menu"):
		open_app_menu()
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
					+ " add a ROM folder or search the SD card"
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
	_scroll_to(card)
	ports.mark_seen(card.port_id)
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
		Mode.MENU, Mode.APP_MENU:
			return [["ui_accept", "Select"], ["ui_cancel", "Close"]]
		Mode.CONFIRM:
			return [["ui_accept", "Select"], ["ui_cancel", _cancel_button.text]]
		Mode.PLAYING:
			return [["quit", "Quit Anchorage"]]
	var info: Dictionary = ports.info(_current.port_id)
	if not info.error.is_empty():
		return [["ui_accept", "Dismiss"], ["ui_cancel", "Dismiss"], ["menu", "Menu"]]
	var hints := []
	var primary := PortState.primary(info)
	if not primary.is_empty():
		hints.append(["ui_accept", PortState.ACTION_LABELS[primary]])
	elif PortState.state(info) == "rom_missing" and not _detail.notice().is_empty():
		hints.append(["ui_accept", "Choose ROM folder"])
	# Back at the top asks to quit (HOME-15), but that stays off the bar: Quit is in the
	# app menu, and with it the bar would not fit 1280 px beside "Choose ROM folder".
	if PortState.cancellable(info):
		hints.append(["ui_cancel", "Cancel"])
	hints.append_array([["options", "Options"], ["refresh", "Refresh"], ["menu", "Menu"]])
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
	_menu_layer.visible = false
	_confirm(
		"Remove “%s”?" % info.name,
		"Anchorage deletes the installed port. Your saves and settings for %s stay." % info.name,
		["Cancel", "Remove", "DangerButton"],
		_on_confirm_remove
	)


func _on_confirm_remove() -> void:
	var id: String = _current.port_id
	_close()
	ports.remove(id)


## The app menu (HOME-14): catalog check, ROM folder, Quit.
func open_app_menu() -> void:
	_set_modal(Mode.APP_MENU, _app_menu_layer, false)
	_catalog_button.grab_focus()


## Back with nothing to cancel or dismiss (HOME-15). Focus starts on Stay, so a stray
## press of accept doesn't quit.
func _ask_to_quit() -> void:
	_confirm("Quit Anchorage?", "", ["Stay", "Quit", ""], quit_requested.emit, false)


## Opens the confirmation dialog; `buttons` is [cancel text, confirm text, confirm style].
func _confirm(
	title: String, body: String, buttons: Array, on_confirmed: Callable, about_card := true
) -> void:
	_confirm_title.text = title
	_confirm_body.text = body
	_confirm_body.visible = not body.is_empty()
	_cancel_button.text = buttons[0]
	_confirm_button.text = buttons[1]
	_confirm_button.theme_type_variation = buttons[2]
	_on_confirmed = on_confirmed
	_set_modal(Mode.CONFIRM, _confirm_layer, about_card)
	_cancel_button.grab_focus()


## A click on a hint does what its input does (HOME-14: the mouse reaches the app menu).
func _on_hint_clicked(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input.call_deferred(event)


## Opens `layer` over the scrim. Cards can't take focus meanwhile, so the D-pad stays
## inside the menu, and the card it is about shows the selection look instead of the focus
## ring; the app menu and Quit are about no card.
func _set_modal(new_mode: Mode, layer: Control, about_card := true) -> void:
	mode = new_mode
	for card in _cards:
		card.focus_mode = Control.FOCUS_NONE
	_current.selected = about_card
	_scrim.visible = true
	layer.visible = true
	_hint_bar.show_hints(_hints())


func _close() -> void:
	mode = Mode.HOME
	_scrim.visible = false
	_menu_layer.visible = false
	_app_menu_layer.visible = false
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
	_playing_monogram.text = PortState.short_name(info)
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

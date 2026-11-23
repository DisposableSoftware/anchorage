extends PanelContainer
## The focused port's details (HOME-3): description, versions, ROM status, progress
## while busy (HOME-8) and errors from `Ports` (HOME-9).

const PortState := preload("res://src/ui/port_state.gd")

@onready var _info_box: Control = %InfoBox
@onready var _name: Label = %Name
@onready var _game: Label = %Game
@onready var _description: Label = %Description
@onready var _notice: Label = %Notice
@onready var _installed: Label = %Installed
@onready var _latest: Label = %Latest
@onready var _rom: Label = %Rom
@onready var _rom_hint: Label = %RomHint
@onready var _busy_box: Control = %BusyBox
@onready var _busy_label: Label = %BusyLabel
@onready var _busy_detail: Label = %BusyDetail
@onready var _progress: ProgressBar = %DetailProgress
@onready var _error_box: Control = %ErrorBox
@onready var _error_title: Label = %ErrorTitle
@onready var _error_detail: Label = %ErrorDetail


func show_port(info: Dictionary) -> void:
	var has_error: bool = not info.error.is_empty()
	_error_box.visible = has_error
	_info_box.visible = not has_error
	if has_error:
		var parts := PortState.error_parts(info.error)
		_error_title.text = parts[0]
		_error_detail.text = parts[1]
		_error_detail.visible = not parts[1].is_empty()
	_name.text = info.name
	_game.text = info.game
	_description.text = info.description
	_installed.text = info.installed_version if info.installed else "Not installed"
	if info.offline:
		_latest.text = "Offline"
	elif info.latest_version.is_empty():
		_latest.text = "Unknown"
	else:
		_latest.text = info.latest_version
	var rom: Dictionary = info.rom
	_rom.text = rom.label
	_rom_hint.visible = not rom.found
	_rom_hint.text = (
		"Takes %s\nLooked in %s" % [PortState.wanted_text(rom.wanted), rom.path]
		if not rom.found
		else ""
	)
	_busy_box.visible = PortState.cancellable(info)
	if _busy_box.visible:
		_busy_label.text = PortState.badge(info)
		_busy_detail.text = info.busy.detail
		_progress.indeterminate = info.busy.progress < 0.0
		_progress.value = maxf(info.busy.progress, 0.0) * 100.0
	_notice.visible = false
	_description.visible = true


## A one-off hint in place of the description, e.g. why accept did nothing (HOME-4).
## It goes when the port changes or focus moves.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
	_description.visible = false


func notice() -> String:
	return _notice.text if _notice.visible else ""


func shown_text() -> String:
	var labels := (
		[_error_title, _error_detail]
		if _error_box.visible
		else [_name, _description, _installed, _latest, _rom, _rom_hint, _busy_label]
	)
	return "\n".join(
		(
			labels
			. filter(func(l: Label) -> bool: return l.is_visible_in_tree())
			. map(func(l: Label) -> String: return l.text)
		)
	)

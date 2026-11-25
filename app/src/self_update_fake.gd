extends Node
## A stand-in for `self_update.gd` with fixed states, for UI tests and screenshots (the
## `self-*` scenarios of `ports_fake.gd`). Same interface. Calls are recorded in `calls`;
## with `simulate` a started update downloads over BUSY_SECONDS and is then ready.

signal changed

const BUSY_SECONDS := 6.0

var simulate := true
## Every call, in order: "check", "start", "cancel", "restart".
var calls: Array = []
## The ports service whose busy and running ports block the update (UPD-8).
var ports: Object = null
var _info := {
	"state": "none",
	"version": "",
	"current": "",
	"progress": -1.0,
	"detail": "",
	"error": "",
	"blocked": false,
}
## Only an update started here plays out; a scenario's own state stays still for screenshots.
var _started := false


## `scenario`: one of `ports_fake.gd`'s; any but the self-* ones means nothing newer.
func _init(scenario := "") -> void:
	var current := str(ProjectSettings.get_setting("application/config/version", "0.2.0"))
	var parts := current.split(".")
	_info.current = current
	var next := "%d.%d.0" % [int(parts[0]), int(parts[1]) + 1] if parts.size() == 3 else "1.0.0"
	match scenario:
		"self-update", "self-busy":
			_to("available", next, -1.0, "")
		"self-downloading":
			_to("downloading", next, 0.42, "20.2 MB of 48.1 MB")
		"self-ready":
			_to("ready", next, -1.0, "")
		"self-unsupported":
			_to("unsupported", "", -1.0, "")


func info() -> Dictionary:
	var out := _info.duplicate()
	out.blocked = _busy()
	return out


func check(_manual := false) -> void:
	calls.append("check")


func start() -> void:
	calls.append("start")
	if not simulate or not _info.state in ["available", "failed"]:
		return
	_started = true
	if _busy():
		_to("waiting", _info.version, -1.0, "Finish what is running first")
	else:
		_to("downloading", _info.version, 0.0, "")


func cancel() -> void:
	calls.append("cancel")
	if simulate and _info.state in ["waiting", "downloading", "verifying"]:
		_to("available", _info.version, -1.0, "")


func restart() -> String:
	calls.append("restart")
	return ""


## Moves a simulated update on by `delta` seconds; `_process` calls it every frame.
func advance(delta: float) -> void:
	if not simulate or not _started:
		return
	if _info.state == "waiting" and not _busy():
		_to("downloading", _info.version, 0.0, "")
	elif _info.state == "downloading" and _info.progress >= 0.0:
		var progress := minf(_info.progress + delta / BUSY_SECONDS, 1.0)
		if progress >= 1.0:
			_to("ready", _info.version, -1.0, "")
		else:
			_to("downloading", _info.version, progress, "%.1f MB of 48.1 MB" % (48.1 * progress))


func _process(delta: float) -> void:
	advance(delta)


func _busy() -> bool:
	if ports == null:
		return false
	for id in ports.list():
		var port: Dictionary = ports.info(id)
		if port.running or port.busy.action != "":
			return true
	return false


func _to(next: String, version: String, progress: float, detail: String) -> void:
	_info.state = next
	_info.version = version
	_info.progress = progress
	_info.detail = detail
	changed.emit()

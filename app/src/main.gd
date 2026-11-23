extends Control
## The main screen (WIN-1).

const Config := preload("res://src/config.gd")
const Keys := preload("res://src/keys.gd")


func _ready() -> void:
	var cfg := Config.load_from(Config.dir())
	Keys.apply(cfg.keybindings)
	$Greeting.text = cfg.greeting
	var window := get_window()
	window.title = "Anchorage"
	window.min_size = Vector2i(1280, 720)
	if window.mode == Window.MODE_WINDOWED:
		window.size = Vector2i(cfg.width, cfg.height)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()

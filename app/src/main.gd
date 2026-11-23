extends Control
## Startup (WIN-1, WIN-4): config, bindings, the theme, the `Ports` service and the home
## screen.

const Config := preload("res://src/config.gd")
const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const HomeScene := preload("res://scenes/home.tscn")
const PORTS := "res://src/ports.gd"


func _ready() -> void:
	var cfg := Config.load_from(Config.dir())
	Keys.apply(cfg.keybindings)
	theme = Style.build(cfg.flavor, cfg.accent)
	# Also paints what the window shows before the first frame and during a resize.
	RenderingServer.set_default_clear_color(theme.get_color("base", "Palette"))
	var window := get_window()
	window.title = "Anchorage"
	window.min_size = Vector2i(1280, 720)
	if window.mode == Window.MODE_WINDOWED:
		window.size = Vector2i(cfg.width, cfg.height)
	var ports := make_ports(OS.get_cmdline_user_args())
	add_child(ports)
	var home := HomeScene.instantiate()
	home.ports = ports
	add_child(home)


## The real service when it exists, else (or with `--fake-ports [SCENARIO]`) the fake.
static func make_ports(args: PackedStringArray) -> Node:
	var at := args.find("--fake-ports")
	if at < 0 and ResourceLoader.exists(PORTS):
		return load(PORTS).new()
	var scenario := "showcase"
	if at >= 0 and at + 1 < args.size() and not args[at + 1].begins_with("--"):
		scenario = args[at + 1]
	return PortsFake.new(scenario)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()

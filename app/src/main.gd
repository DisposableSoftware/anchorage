extends Control
## Startup (WIN-1, WIN-4): config, bindings, the theme, the `Ports` service and the home
## screen.

const Config := preload("res://src/config.gd")
const Keys := preload("res://src/keys.gd")
const Style := preload("res://src/theme.gd")
const PortsFake := preload("res://src/ports_fake.gd")
const SelfUpdate := preload("res://src/self_update.gd")
const SelfUpdateFake := preload("res://src/self_update_fake.gd")
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
	var ports := make_ports(OS.get_cmdline_user_args(), cfg)
	add_child(ports)
	var self_update := make_self_update(OS.get_cmdline_user_args(), ports, cfg)
	add_child(self_update)
	var home := HomeScene.instantiate()
	home.ports = ports
	home.self_update = self_update
	home.quit_requested.connect(quit)
	add_child(home)


## The real service when it exists, else (or with `--fake-ports [SCENARIO]`) the fake.
## `cfg` gives the real one its ROM folder (CONF-8) and update-check setting (CONF-9).
static func make_ports(args: PackedStringArray, cfg: RefCounted = null) -> Node:
	var at := args.find("--fake-ports")
	if at < 0 and ResourceLoader.exists(PORTS):
		var ports: Node = load(PORTS).new()
		if cfg != null:
			ports.roms_dir = cfg.roms_directory if cfg.roms_directory_set else ""
			ports.config_file = Config.dir().path_join("config.ini")
			ports.check_updates = cfg.check_updates
		return ports
	var scenario := "showcase"
	if at >= 0 and at + 1 < args.size() and not args[at + 1].begins_with("--"):
		scenario = args[at + 1]
	return PortsFake.new(scenario)


## UPD: Anchorage's own update next to the ports it waits for (UPD-8); the fake's
## stand-in with the fake ports, in that scenario's state.
static func make_self_update(args: PackedStringArray, ports: Node, cfg: RefCounted = null) -> Node:
	var at := args.find("--fake-ports")
	if at < 0 and not ports is PortsFake:
		var real: Node = SelfUpdate.new()
		real.ports = ports
		if cfg != null:
			real.check_updates = cfg.check_updates
		return real
	var fake: Node = SelfUpdateFake.new(args[at + 1] if at >= 0 and at + 1 < args.size() else "")
	fake.ports = ports
	return fake


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		quit()


## `quit`, the app menu's Quit Anchorage and the Quit confirmation all end here. As the
## tree goes, Ports' _exit_tree stops its scan and search and joins their threads.
func quit() -> void:
	get_tree().quit()

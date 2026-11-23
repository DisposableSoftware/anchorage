extends "res://tests/case.gd"
## Checks the machine-readable tables in spec/ against the code and the example files,
## so the spec can't silently drift. See spec/README.md.

const Config := preload("res://src/config.gd")
const Ini := preload("res://src/ini.gd")
const Keys := preload("res://src/keys.gd")

## Every key the config reads; adding one means adding it to the spec table too.
const CONFIG_KEY_COUNT := 6


## Body rows of the table between `<!-- spec:NAME:begin -->` and `...:end -->`, each as
## an array of cells with the backticks removed.
func table(doc: String, name: String) -> Array:
	var begin := "<!-- spec:%s:begin -->" % name
	var start := doc.find(begin)
	var stop := doc.find("<!-- spec:%s:end -->" % name)
	check(start >= 0 and stop > start, "spec table '%s' is missing its markers" % name)
	var rows := []
	for line in doc.substr(start + begin.length(), stop - start - begin.length()).split("\n"):
		line = line.strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := []
		for cell in line.trim_prefix("|").trim_suffix("|").split("|"):
			cells.append(cell.strip_edges().replace("`", ""))
		rows.append(cells)
	return rows.slice(2)


func config_value(cfg: RefCounted, section: String, key: String) -> Variant:
	var values := {
		"window width": str(cfg.width),
		"window height": str(cfg.height),
		"appearance flavor": cfg.flavor,
		"appearance accent": cfg.accent,
		"roms directory": cfg.roms_directory,
		"ports check_updates": str(cfg.check_updates).to_lower(),
	}
	return values.get("%s %s" % [section, key])


func config_rows() -> Array:
	return table(repo_file("spec/configuration.md"), "config")


func test_keybindings_match_spec() -> void:
	var spec := []
	for row in table(repo_file("spec/keybindings.md"), "keybindings"):
		var keys := []
		for key in row[2].split(","):
			if not key.strip_edges().is_empty():
				keys.append(key.strip_edges())
		spec.append([row[0], row[1], keys])
	var code := []
	for binding in Keys.BINDINGS:
		code.append([binding[0], binding[1], Array(binding[3])])
	eq(spec, code, "spec/keybindings.md and Keys.BINDINGS differ")


func test_config_defaults_match_spec() -> void:
	var cfg := Config.new()
	var rows := config_rows()
	eq(rows.size(), CONFIG_KEY_COUNT, "spec/configuration.md must list every config key")
	for row in rows:
		var value: Variant = config_value(cfg, row[0], row[1])
		check(value != null, "spec lists unknown key [%s] %s" % [row[0], row[1]])
		eq(value, row[2], "[%s] %s: Config defaults vs spec" % [row[0], row[1]])


func test_example_config_matches_spec() -> void:
	var example := Ini.parse(FileAccess.get_file_as_string(Config.CONFIG_EXAMPLE))
	for row in config_rows():
		eq(
			example.get(row[0], {}).get(row[1]),
			row[2],
			"[%s] %s: example vs spec" % [row[0], row[1]]
		)
	check(not example.has("keybindings"), "bindings belong in keybindings.example.ini (KEY-2)")
	var keys: Dictionary = Ini.parse(FileAccess.get_file_as_string(Config.KEYBINDINGS_EXAMPLE)).get(
		"keybindings", {}
	)
	eq(keys.size(), Keys.BINDINGS.size(), "keybindings.example.ini must list every binding")
	for binding in Keys.BINDINGS:
		eq(
			keys.get(binding[0]),
			";".join(binding[3]),
			"[keybindings] %s: example vs code" % binding[0]
		)


func test_version_is_the_same_everywhere() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version")
	check(
		repo_file("data/io.github.DisposableSoftware.Anchorage.metainfo.xml").contains(
			'<release version="%s"' % version
		),
		"metainfo lacks release %s" % version
	)

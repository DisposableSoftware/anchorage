extends RefCounted
## Minimal INI reader for config.ini and keybindings.ini: `[section]`, `key = value`,
## `#` or `;` comment lines. Values stay plain text, so files written by home-manager
## (unquoted) parse the same as hand-written ones. Godot's ConfigFile expects quoted
## strings, so it cannot read them.


## Returns {section: {key: value}}. Lines that are neither a section nor `key = value`
## are skipped.
static func parse(text: String) -> Dictionary:
	var out := {}
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		var eq := line.find("=")
		if eq < 1:
			continue
		if not out.has(section):
			out[section] = {}
		out[section][line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out


## "a;b;;c" -> ["a", "b", "c"]
static func split_list(value: String) -> PackedStringArray:
	var out := PackedStringArray()
	for item in value.split(";"):
		item = item.strip_edges()
		if not item.is_empty():
			out.append(item)
	return out

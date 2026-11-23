extends "res://tests/case.gd"
## LOOK-2, LOOK-5, LOOK-6, LOOK-8: the theme built from a flavour and an accent.

const Palette := preload("res://src/palette.gd")
const Style := preload("res://src/theme.gd")

const HEX := "#[0-9a-fA-F]{6}\\b"


func test_focus_ring_has_3_to_1_against_base_everywhere() -> void:
	for flavor in Palette.FLAVORS:
		var colors := Palette.colors(flavor)
		for accent in Palette.ACCENTS:
			var focus := Style.focus_color(colors, accent)
			var ratio := Style.contrast(focus, colors.base)
			check(ratio >= 3.0, "%s/%s: %.2f (LOOK-8)" % [flavor, accent, ratio])


func test_focus_ring_is_the_accent_where_it_already_contrasts() -> void:
	var mocha := Palette.colors("mocha")
	eq(Style.focus_color(mocha, "mauve"), mocha.mauve, "mocha mauve unchanged")
	var latte := Palette.colors("latte")
	check(Style.focus_color(latte, "yellow") != latte.yellow, "latte yellow is darkened")


func test_text_on_badges_and_buttons_is_readable() -> void:
	for flavor in Palette.FLAVORS:
		for accent in ["mauve", "yellow", "sky"]:
			var t := Style.build(flavor, accent)
			for state in Style.STATE_COLORS:
				var bg: Color = t.get_stylebox("panel", "Badge_" + state).bg_color
				var fg := t.get_color("font_color", "BadgeText_" + state)
				var ratio := Style.contrast(fg, bg)
				check(ratio >= 4.5, "%s/%s %s badge: %.2f" % [flavor, accent, state, ratio])
			var surface := t.get_color("surface0", "Palette")
			var danger := t.get_color("font_color", "DangerButton")
			check(Style.contrast(danger, surface) >= 4.5, "%s: Remove button text" % flavor)


func test_theme_uses_the_flavour_and_accent() -> void:
	var t := Style.build("latte", "blue")
	var latte := Palette.colors("latte")
	eq(t.get_color("base", "Palette"), latte.base, "palette colours by name (LOOK-2)")
	eq(t.get_color("accent", "Palette"), latte.blue, "accent")
	var focus := t.get_stylebox("panel", "CardFocus") as StyleBoxFlat
	eq(focus.border_color, Style.focus_color(latte, "blue"), "focused card ring")
	check(focus.border_width_left >= 4, "a ring readable from a couch (LOOK-5)")
	check(focus.shadow_size == 0, "flat: no shadow")
	var card := t.get_stylebox("panel", "Card") as StyleBoxFlat
	var selected := t.get_stylebox("panel", "CardSelected") as StyleBoxFlat
	check(selected.bg_color != card.bg_color, "selection is a fill")
	check(selected.border_color != focus.border_color, "and not the focus ring")
	eq(t.get_stylebox("panel", "Background").bg_color.a, 1.0, "opaque window (LOOK-6)")
	eq(
		Style.build("nope", "nope").get_color("accent", "Palette"),
		Palette.colors("mocha").mauve,
		"unknown values fall back"
	)


func test_bundled_font_and_no_text_under_20px() -> void:
	var t := Style.build("mocha", "mauve")
	check(t.default_font is FontVariation, "bundled font (LOOK-6)")
	var base: Font = (t.default_font as FontVariation).base_font
	check(
		base != null and base.get_font_name().begins_with("Inter"), "Inter: " + base.get_font_name()
	)
	check(t.default_font_size >= 20, "default size")
	for type in t.get_font_size_type_list():
		for name in t.get_font_size_list(type):
			var size := t.get_font_size(name, type)
			check(size >= 20, "%s %s is %d px" % [type, name, size])


func test_no_colour_literals_outside_the_palette() -> void:
	var hex := RegEx.create_from_string(HEX)
	var number_color := RegEx.create_from_string("Color\\(\\s*[0-9.]")
	for path in _files("res://src") + _files("res://scenes"):
		if path == "res://src/palette.gd":
			continue
		var text := FileAccess.get_file_as_string(path)
		check(hex.search(text) == null, "hex colour in %s (LOOK-2)" % path)
		check(number_color.search(text) == null, "numeric Color() in %s" % path)


func _files(dir: String) -> Array:
	var out := []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	return out

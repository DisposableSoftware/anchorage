extends "res://tests/case.gd"
## The Steam library artwork in data/steam/ (INT-27) and the app icons (INT-42), all drawn
## by tools/steam-art/generate.py and rendered by scripts/render-steam-art.sh.

const Palette := preload("res://src/palette.gd")
const ID := "io.github.DisposableSoftware.Anchorage"
## Steam's library asset sizes.
const SIZES := {
	"portrait": Vector2i(600, 900),
	"wide": Vector2i(920, 430),
	"hero": Vector2i(1920, 620),
	"icon": Vector2i(256, 256),
}


func _image(path: String) -> Image:
	var image := Image.load_from_file(
		ProjectSettings.globalize_path("res://").path_join("..").path_join(path)
	)
	check(image != null, "%s loads" % path)
	return image


func _colours(svg: String) -> Array:
	var found := []
	for m in RegEx.create_from_string("#[0-9a-fA-F]{6}\\b").search_all(svg):
		if not found.has(m.get_string().to_lower()):
			found.append(m.get_string().to_lower())
	return found


func test_capsules_hero_and_icon_have_steam_sizes() -> void:
	for name in SIZES:
		var image := _image("data/steam/%s.png" % name)
		if image != null:
			eq(image.get_size(), SIZES[name], "%s.png size" % name)


func test_capsules_and_hero_are_opaque() -> void:
	for name in ["portrait", "wide", "hero"]:
		var image := _image("data/steam/%s.png" % name)
		if image != null:
			eq(image.detect_alpha(), Image.ALPHA_NONE, "%s.png is opaque" % name)


func test_logo_is_transparent_and_fits_steam_limits() -> void:
	var image := _image("data/steam/logo.png")
	if image == null:
		return
	var size := image.get_size()
	check(size.x <= 1280 and size.y <= 720, "logo is at most 1280x720: %s" % size)
	check(size.x == 1280 or size.y == 720, "logo is 1280 wide or 720 tall: %s" % size)
	check(image.detect_alpha() != Image.ALPHA_NONE, "logo has an alpha channel in use")
	eq(image.get_pixel(0, 0).a, 0.0, "logo corner is transparent")


func test_every_png_has_its_svg_source() -> void:
	for name in ["portrait", "wide", "hero", "logo"]:
		check(repo_file("data/steam/%s.svg" % name).begins_with("<svg"), "%s.svg" % name)


func test_art_and_app_icon_use_only_mocha_colours() -> void:
	var mocha: Array = Palette.colors("mocha").values()
	var paths := ["data/%s.svg" % ID]
	for name in ["portrait", "wide", "hero", "logo"]:
		paths.append("data/steam/%s.svg" % name)
	for path in paths:
		for hex in _colours(repo_file(path)):
			check(mocha.has(Color.html(hex)), "%s: %s is not a mocha colour" % [path, hex])


func test_app_icon_is_flat_128_with_no_text() -> void:
	var svg := repo_file("data/%s.svg" % ID)
	check(svg.contains('viewBox="0 0 128 128"'), "128x128 viewBox")
	for banned in ["<text", "Gradient", "filter"]:
		check(not svg.contains(banned), "app icon has no %s" % banned)


func test_project_icon_is_the_app_icon() -> void:
	eq(repo_file("app/icon.svg"), repo_file("data/%s.svg" % ID), "app/icon.svg")
	eq(ProjectSettings.get_setting("application/config/icon"), "res://icon.svg", "config/icon")


func test_symbolic_icon_is_one_colour_at_16() -> void:
	var svg := repo_file("data/%s-symbolic.svg" % ID)
	check(svg.contains('viewBox="0 0 16 16"'), "16x16 viewBox")
	eq(_colours(svg), ["#2e3436"], "only the symbolic colour")
	check(not svg.contains("<text"), "no text")

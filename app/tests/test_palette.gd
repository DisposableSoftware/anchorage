extends "res://tests/case.gd"
## LOOK-3: the four Catppuccin palettes, as data, equal to the style guide's files.

const Palette := preload("res://src/palette.gd")

## sha256 of the style guide's reference/themes/<flavour>.css, so the copies in
## data/themes/ stay unmodified.
const STYLE_GUIDE_SHA256 := {
	"frappe": "93efb2835772d8be314b94daa830614fb89f1b274b496c87a508c8f256cd1360",
	"latte": "7312a254980d7b8033861a975fec2fae73741703060919ee1dece6d5aff5f526",
	"macchiato": "f9ff80aafd389a2831e8b17a8d558669ecb8e9afae728833b4bfdab4d2a070d6",
	"mocha": "e247b58f4bd2bfec9b1113ea82245705ad81fd7bd75c3b1648fa34845a475638",
}


func test_every_flavour_has_the_26_names() -> void:
	eq(Palette.FLAVORS.keys().size(), 4, "four flavours")
	var names := Palette.ACCENTS + Palette.NEUTRALS
	eq(names.size(), 26, "14 accents and 12 neutrals")
	for flavor in ["latte", "frappe", "macchiato", "mocha"]:
		var keys: Array = Palette.FLAVORS[flavor].keys()
		keys.sort()
		var want := names.duplicate()
		want.sort()
		eq(keys, want, flavor)


func test_values_match_the_style_guide_files() -> void:
	var line := RegEx.create_from_string("^@define-color ([a-z0-9]+) (#[0-9a-f]{6});$")
	for flavor in STYLE_GUIDE_SHA256:
		var css := repo_file("data/themes/%s.css" % flavor)
		eq(css.sha256_text(), STYLE_GUIDE_SHA256[flavor], "%s.css is the style guide's" % flavor)
		var parsed := {}
		for row in css.split("\n"):
			var found := line.search(row)
			if found:
				parsed[found.get_string(1)] = found.get_string(2)
		eq(parsed, Palette.FLAVORS[flavor], "%s: palette.gd vs data/themes" % flavor)


func test_unknown_flavour_is_mocha() -> void:
	eq(Palette.colors("gtk"), Palette.colors("mocha"), "fallback")
	eq(Palette.colors("latte").base, Color(Palette.FLAVORS.latte.base), "Color values")

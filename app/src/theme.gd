extends RefCounted
## Builds the one Theme every screen uses from a flavour and an accent (LOOK-2, LOOK-5,
## LOOK-6, LOOK-8). Colours come from palette.gd only. Screens pick styles through type
## variations (`theme_type_variation`) and read named colours from the "Palette" type.

const Palette := preload("res://src/palette.gd")
const FONT_PATH := "res://fonts/InterVariable.ttf"

## Sizes in logical px at the 1280x720 base size. Nothing is under 20 px, so text stays
## readable on a 7-inch 800p screen.
const FONT_SIZE := 22
const SMALL := 20
const TITLE := 26
const HEADING := 34
const MONOGRAM := 60
const FOCUS_WIDTH := 4
const RADIUS := 16
const FOCUS_CONTRAST := 3.0
const TEXT_CONTRAST := 4.5

## Badge colour per card state (HOME-2). "accent" is the configured accent.
const STATE_COLORS := {
	"not_installed": "overlay2",
	"ready": "green",
	"update": "blue",
	"rom_missing": "peach",
	"busy": "accent",
	"playing": "teal",
}
## Emblem colours, by catalog position.
const EMBLEM_COLORS := ["green", "peach", "sapphire", "red", "teal", "yellow", "pink", "lavender"]


## WCAG contrast ratio between two opaque colours.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var channels := [c.r, c.g, c.b].map(
		func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	)
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


## `color`, darkened on a light `bg` (lightened on a dark one) in steps of 5 % until it
## has `ratio` against `bg`. Keeps the hue, so a badge stays green in latte.
static func readable(color: Color, bg: Color, ratio: float) -> Color:
	var darken := contrast(Color.BLACK, bg) > contrast(Color.WHITE, bg)
	var out := color
	for step in range(1, 21):
		if contrast(out, bg) >= ratio:
			break
		out = color.darkened(step / 20.0) if darken else color.lightened(step / 20.0)
	return out


## The focus ring colour: the accent, made readable against base (LOOK-8).
static func focus_color(colors: Dictionary, accent: String) -> Color:
	var name := accent if colors.has(accent) else Palette.DEFAULT_ACCENT
	return readable(colors[name], colors.base, FOCUS_CONTRAST)


static func font(weight: int) -> Font:
	var file: Font
	if ResourceLoader.exists(FONT_PATH):
		file = load(FONT_PATH)
	else:
		# Not imported yet (tests run without the editor's import step).
		var dynamic := FontFile.new()
		dynamic.load_dynamic_font(FONT_PATH)
		file = dynamic
	var variation := FontVariation.new()
	variation.base_font = file
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {wght: weight}
	return variation


static func build(flavor: String, accent: String) -> Theme:
	var c := Palette.colors(flavor)
	if not Palette.ACCENTS.has(accent):
		accent = Palette.DEFAULT_ACCENT
	c.accent = c[accent]
	c.focus = focus_color(c, accent)
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = FONT_SIZE
	var bold := font(700)
	for name in c:
		t.set_color(name, "Palette", c[name])
	t.set_color("scrim", "Palette", Color(c.crust, 0.72))

	_labels(t, c, bold)
	_panels(t, c)
	_buttons(t, c, bold)
	_progress(t, c)
	_badges(t, c, bold)
	_emblems(t, c, bold)
	return t


static func _label(t: Theme, name: String, color: Color, size: int, face: Font = null) -> void:
	t.set_type_variation(name, "Label")
	t.set_color("font_color", name, color)
	t.set_font_size("font_size", name, size)
	if face:
		t.set_font("font", name, face)


static func _labels(t: Theme, c: Dictionary, bold: Font) -> void:
	t.set_color("font_color", "Label", c.text)
	t.set_font_size("font_size", "Label", FONT_SIZE)
	t.set_constant("line_spacing", "Label", 4)
	_label(t, "Brand", c.text, TITLE, bold)
	_label(t, "Kicker", c.subtext0, SMALL)
	_label(t, "CardTitle", c.text, TITLE, bold)
	_label(t, "PortName", c.subtext1, SMALL)
	_label(t, "Heading", c.text, HEADING, bold)
	_label(t, "Dim", c.subtext0, SMALL)
	_label(t, "FieldName", c.subtext0, SMALL)
	_label(t, "FieldValue", c.text, FONT_SIZE, bold)
	_label(t, "Hint", c.subtext1, SMALL)
	_label(t, "KeyCapText", c.text, SMALL, bold)
	_label(t, "ErrorTitle", readable(c.red, c.mantle, TEXT_CONTRAST), TITLE, bold)
	_label(t, "Notice", readable(c.peach, c.mantle, TEXT_CONTRAST), FONT_SIZE, bold)
	_label(t, "DialogTitle", c.text, TITLE, bold)
	_label(t, "PlayingTitle", c.text, 48, bold)
	_label(t, "PlayingDim", c.subtext0, FONT_SIZE)
	for pad in [["A", "green"], ["B", "red"], ["X", "blue"], ["Y", "yellow"]]:
		var color := readable(c[pad[1]], c.surface1, TEXT_CONTRAST)
		_label(t, "PadText" + pad[0], color, SMALL, bold)
	_label(t, "PadText", c.text, SMALL, bold)


static func flat(bg: Color, radius: int, margin_h: int, margin_v: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing = true
	return box


static func _panel(t: Theme, name: String, box: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, box)


static func _panels(t: Theme, c: Dictionary) -> void:
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	_panel(t, "Background", flat(c.base, 0, 0, 0))
	var card := flat(c.surface0, RADIUS, 20, 20)
	card.set_border_width_all(FOCUS_WIDTH)
	card.border_color = c.surface0
	_panel(t, "Card", card)
	var focused := card.duplicate() as StyleBoxFlat
	focused.border_color = c.focus
	focused.bg_color = c.surface0.lerp(c.surface1, 0.5)
	_panel(t, "CardFocus", focused)
	var selected := card.duplicate() as StyleBoxFlat
	selected.bg_color = c.surface0.lerp(c.accent, 0.25)
	selected.border_color = selected.bg_color
	_panel(t, "CardSelected", selected)
	_panel(t, "DetailPanel", flat(c.mantle, RADIUS, 32, 24))
	_panel(t, "HintBar", flat(c.mantle, 0, 40, 14))
	var dialog := flat(c.mantle, RADIUS, 36, 32)
	dialog.set_border_width_all(2)
	dialog.border_color = c.surface1
	_panel(t, "Dialog", dialog)
	_panel(t, "PadGlyph", flat(c.surface1, 18, 10, 2))
	var keycap := flat(c.surface0, 8, 10, 2)
	keycap.set_border_width_all(2)
	keycap.border_color = c.surface2
	_panel(t, "KeyCap", keycap)
	_panel(t, "Playing", flat(c.crust, 0, 0, 0))


static func _buttons(t: Theme, c: Dictionary, bold: Font) -> void:
	var normal := flat(c.surface0, 12, 24, 14)
	normal.set_border_width_all(FOCUS_WIDTH)
	normal.border_color = c.surface0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = c.surface1
	hover.border_color = c.surface1
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = c.surface0.lerp(c.accent, 0.2)
	focus.border_color = c.focus
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = c.surface0.lerp(c.accent, 0.35)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", normal)
	# Drawn over `normal`: so the focused button gets the tinted fill and the ring.
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", bold)
	t.set_font_size("font_size", "Button", FONT_SIZE)
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(state, "Button", c.text)
		t.set_color(state, "DangerButton", readable(c.red, c.surface0, TEXT_CONTRAST))
	t.set_color("font_disabled_color", "Button", c.overlay0)
	t.set_type_variation("DangerButton", "Button")


static func _progress(t: Theme, c: Dictionary) -> void:
	var track := flat(c.surface1, 6, 0, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := flat(c.accent, 6, 0, 0)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", c.text)
	t.set_font_size("font_size", "ProgressBar", SMALL)


static func _badges(t: Theme, c: Dictionary, bold: Font) -> void:
	for state in STATE_COLORS:
		var color: Color = c[STATE_COLORS[state]]
		var bg := c.surface0.lerp(color, 0.22) as Color
		_panel(t, "Badge_" + state, flat(bg, 18, 14, 4))
		_label(t, "BadgeText_" + state, readable(color, bg, TEXT_CONTRAST), SMALL, bold)


static func _emblems(t: Theme, c: Dictionary, bold: Font) -> void:
	for i in EMBLEM_COLORS.size():
		var color: Color = c[EMBLEM_COLORS[i]]
		var bg := c.surface0.lerp(color, 0.18) as Color
		var box := flat(bg, 12, 0, 0)
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		_panel(t, "Emblem%d" % i, box)
		_label(t, "Monogram%d" % i, readable(color, bg, FOCUS_CONTRAST), MONOGRAM, bold)

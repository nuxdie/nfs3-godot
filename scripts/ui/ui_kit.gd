class_name UiKit
## Shared look for the front end (and later the HUD): palette, fonts and a few
## drawing helpers for the slanted, flat "motorsport broadcast" style.

const ACCENT := Color(1.0, 0.72, 0.1)
const ACCENT_HOT := Color(1.0, 0.42, 0.12)
const COP_RED := Color(1.0, 0.18, 0.25)
const COP_BLUE := Color(0.2, 0.45, 1.0)
const INK := Color(0.96, 0.96, 0.98)
const INK_DIM := Color(0.96, 0.96, 0.98, 0.55)
const INK_FAINT := Color(0.96, 0.96, 0.98, 0.28)
const PANEL := Color(0.05, 0.055, 0.07, 0.72)
const PANEL_HI := Color(1, 1, 1, 0.07)
const BG := Color(0.035, 0.038, 0.05)

## Horizontal lean of slanted shapes, in px per px of height.
const SLANT := 0.22

static var _fonts := {}


## "display" (bold italic condensed), "cond" (semibold condensed), "cond_med",
## "body", "body_bold". `tracking` adds letter spacing in px; `tabular` gives
## fixed-width digits, so changing numbers (speed, timers) don't jiggle.
static func font(kind: String, tracking := 0, tabular := false) -> Font:
	var key := "%s/%d/%s" % [kind, tracking, tabular]
	if not _fonts.has(key):
		var base: Font
		match kind:
			"display": base = preload("res://fonts/BarlowCondensed-BoldItalic.ttf")
			"cond": base = preload("res://fonts/BarlowCondensed-SemiBold.ttf")
			"cond_med": base = preload("res://fonts/BarlowCondensed-Medium.ttf")
			"body_bold": base = preload("res://fonts/Barlow-SemiBold.ttf")
			_: base = preload("res://fonts/Barlow-Regular.ttf")
		if tracking == 0 and not tabular:
			_fonts[key] = base
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.spacing_glyph = tracking
			if tabular:
				fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
			_fonts[key] = fv
	return _fonts[key]


static func label(text: String, kind := "body", size := 16, color := INK, tracking := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind, tracking))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Theme for the few stock controls still used (scroll bars etc.).
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 16
	return t


## A parallelogram leaning right, filling `r`.
static func slant_points(r: Rect2, slant := SLANT) -> PackedVector2Array:
	var s := r.size.y * slant
	return PackedVector2Array([
		Vector2(r.position.x + s, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - s, r.end.y), Vector2(r.position.x, r.end.y)])


static func draw_slant(ci: CanvasItem, r: Rect2, color: Color, slant := SLANT) -> void:
	ci.draw_colored_polygon(slant_points(r, slant), color)


## A key-cap chip ("ENTER", "TAB", "←→"); returns its width so callers can lay out rows.
## "↑↓" and "←→" are drawn as arrow pairs (the text fonts have no arrow glyphs).
static func draw_key(ci: CanvasItem, pos: Vector2, key: String, size := 13, color := INK) -> float:
	var f := font("cond", 1)
	var arrows := key == "↑↓" or key == "←→"
	var w := (size * 1.9 if arrows else f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) + 12.0
	var h := size + 9.0
	var r := Rect2(pos - Vector2(0, h * 0.5), Vector2(w, h))
	ci.draw_rect(r, Color(color, 0.12))
	ci.draw_rect(r, Color(color, 0.45), false, 1.0)
	if arrows:
		var s := size * 0.3
		for i in 2:
			var c := r.get_center() + Vector2((i - 0.5) * size * 0.85, 0)
			var d := Vector2(0, -1 if i == 0 else 1) if key == "↑↓" else Vector2(-1 if i == 0 else 1, 0)
			var n := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([c + d * s * 1.2, c - d * s + n * s, c - d * s - n * s]), color)
	else:
		ci.draw_string(f, Vector2(r.position.x + 6, pos.y + size * 0.36), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## Row of "[KEY] action" hints starting at `pos` (vertically centred on it).
static func draw_hints(ci: CanvasItem, pos: Vector2, hints: Array, size := 13, alpha := 1.0) -> float:
	var x := pos.x
	var f := font("cond", 2)
	for h in hints:
		x += draw_key(ci, Vector2(x, pos.y), h[0], size, Color(INK, alpha)) + 7.0
		ci.draw_string(f, Vector2(x, pos.y + size * 0.36), h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK_DIM, INK_DIM.a * alpha))
		x += f.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 22.0
	return x - pos.x


static func text_width(kind: String, text: String, size: int, tracking := 0, tabular := false) -> float:
	return font(kind, tracking, tabular).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Exponential smoothing that doesn't depend on frame rate.
static func damp(from: float, to: float, rate: float, dt: float) -> float:
	return lerpf(from, to, 1.0 - exp(-rate * dt))

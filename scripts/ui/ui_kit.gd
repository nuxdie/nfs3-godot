class_name UiKit
## Shared look for the front end and the HUD: palette, fonts and drawing helpers. The menus are
## typographic, set straight on the picture behind them (darkened where text sits): big
## condensed italic titles, small amber kickers over each group, and choices as words, the
## picked one lit and underlined. What has focus gets a wash of the accent fading to the
## right; the slant is kept for the one main action on a screen and for the HUD.

const ACCENT := Color(1.0, 0.72, 0.1)
const ACCENT_HOT := Color(1.0, 0.42, 0.12)
const COP_RED := Color(1.0, 0.3, 0.33)
const COP_BLUE := Color(0.3, 0.52, 1.0)
const GOOD := Color(0.42, 0.86, 0.5)
const INK := Color(0.96, 0.96, 0.98)
## Secondary text: still comfortably readable over the dark surfaces (about 9:1).
const INK_DIM := Color(0.96, 0.96, 0.98, 0.7)
## Only for what can't be used (locked, unavailable) and placeholders.
const INK_FAINT := Color(0.96, 0.96, 0.98, 0.42)
const LINE := Color(1, 1, 1, 0.1)
const PANEL := Color(0.05, 0.055, 0.07, 0.72)
const PANEL_HI := Color(1, 1, 1, 0.07)
## Solid surfaces the menus' panels and cards sit on.
const SURFACE := Color(0.055, 0.06, 0.078, 0.9)
const SURFACE_HI := Color(1, 1, 1, 0.055)
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
	var arrows := key == "↑↓" or key == "←→"
	var w := key_width(key, size)
	var h := size + 9.0
	var r := Rect2(pos - Vector2(0, h * 0.5), Vector2(w, h))
	box(ci, r, Color(color, 0.1), 3, Color(color, 0.4))
	if arrows:
		var s := size * 0.3
		for i in 2:
			var c := r.get_center() + Vector2((i - 0.5) * size * 0.85, 0)
			var d := Vector2(0, -1 if i == 0 else 1) if key == "↑↓" else Vector2(-1 if i == 0 else 1, 0)
			var n := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([c + d * s * 1.2, c - d * s + n * s, c - d * s - n * s]), color)
	else:
		ci.draw_string(font("cond", 1), Vector2(r.position.x + 6, pos.y + size * 0.36), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## How wide draw_key() draws `key`.
static func key_width(key: String, size := 13) -> float:
	if key == "↑↓" or key == "←→":
		return size * 1.9 + 12.0
	return font("cond", 1).get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0


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


static var _boxes := {}


## A rounded rectangle: `fill`, and a `border` of `bw` px if it's visible.
static func box(ci: CanvasItem, r: Rect2, fill: Color, radius := 4, border := Color(0, 0, 0, 0), bw := 1) -> void:
	var key := "%s/%s/%d/%d" % [fill, border, radius, bw]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		sb.anti_aliasing_size = 0.8
		if border.a > 0.0:
			sb.border_color = border
			sb.set_border_width_all(bw)
		if _boxes.size() > 400:
			_boxes.clear()
		_boxes[key] = sb
	ci.draw_style_box(sb, r)


## The biggest size from `size` down to `min_size` at which `text` fits in `max_w`.
static func fit(kind: String, text: String, max_w: float, size: int, min_size := 12, tracking := 0) -> int:
	var f := font(kind, tracking)
	while size > min_size and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	return size


## What has focus (or, fainter, the pointer): a wash of `color` fading out to the right over
## `r`, and a thin bar down its left edge. `t` fades it in.
static func glow(ci: CanvasItem, r: Rect2, t := 1.0, color := ACCENT, bar := true) -> void:
	if t <= 0.01:
		return
	var a := Color(color, 0.17 * t)
	var b := Color(color, 0.0)
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([a, b, b, a]))
	if bar:
		ci.draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(color, t))


## Where a route starts and ends on a map: a bar across the road at `a` heading `dir`, and
## for a point-to-point run a small chequered flag at its finish `b`. `s` scales both.
static func route_ends(ci: CanvasItem, a: Vector2, dir: Vector2, b := Vector2.INF, s := 1.0, col := INK) -> void:
	var n := dir.normalized().orthogonal() * 6.0 * s
	ci.draw_line(a - n, a + n, Color(0, 0, 0, 0.6), 5.0 * s)
	ci.draw_line(a - n, a + n, col, 2.5 * s)
	if b == Vector2.INF:
		return
	var q := 3.2 * s
	var o := b - Vector2(q, q)
	ci.draw_rect(Rect2(o - Vector2(1, 1), Vector2(q * 2 + 2, q * 2 + 2)), Color(0, 0, 0, 0.7))
	for k in 4:
		var cell := Vector2(k % 2, k / 2)
		ci.draw_rect(Rect2(o + cell * q, Vector2(q, q)), Color.WHITE if (k % 2) == (k / 2) else Color(0.1, 0.1, 0.1))


static var _shade_tex: GradientTexture2D


## A soft dark pool behind `r` (an ellipse filling it, fading out to its edge), so type laid
## straight over a picture or the race reads without a box round it.
static func shade(ci: CanvasItem, r: Rect2, alpha := 0.55) -> void:
	if _shade_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.45, Color(0, 0, 0, 0.7))
		_shade_tex = GradientTexture2D.new()
		_shade_tex.gradient = g
		_shade_tex.fill = GradientTexture2D.FILL_RADIAL
		_shade_tex.fill_from = Vector2(0.5, 0.5)
		_shade_tex.fill_to = Vector2(1.0, 0.5)
		_shade_tex.width = 128
		_shade_tex.height = 128
	ci.draw_texture_rect(_shade_tex, r, false, Color(1, 1, 1, alpha))


## A kicker: the small amber caps over a title or a group ("TRACK", "CLASS C · HIGH STAKES").
static func kicker(ci: CanvasItem, pos: Vector2, text: String, w := -1.0, color := ACCENT) -> void:
	var up := text.to_upper()
	ci.draw_string(font("cond", 2), pos, up, HORIZONTAL_ALIGNMENT_LEFT, w, fit("cond", up, w, 13, 10, 2) if w > 0 else 13, color)


## A section's heading: small caps in the accent with a hairline running to `w`.
static func heading(ci: CanvasItem, pos: Vector2, text: String, w: float, color := ACCENT) -> void:
	var f := font("cond", 2)
	ci.draw_string(f, pos, text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	var tw := f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if tw + 12 < w:
		ci.draw_line(pos + Vector2(tw + 12, -4.5), pos + Vector2(w, -4.5), LINE, 1.0)


## A chevron pointing `dir` (1 right, -1 left, 2 down, -2 up) centred on `c`.
static func chevron(ci: CanvasItem, c: Vector2, dir: int, color: Color, s := 4.0, width := 2.0) -> void:
	var pts: PackedVector2Array
	match dir:
		1: pts = [c + Vector2(-s * 0.5, -s), c + Vector2(s * 0.5, 0), c + Vector2(-s * 0.5, s)]
		-1: pts = [c + Vector2(s * 0.5, -s), c + Vector2(-s * 0.5, 0), c + Vector2(s * 0.5, s)]
		-2: pts = [c + Vector2(-s, s * 0.5), c + Vector2(0, -s * 0.5), c + Vector2(s, s * 0.5)]
		_: pts = [c + Vector2(-s, -s * 0.5), c + Vector2(0, s * 0.5), c + Vector2(s, -s * 0.5)]
	ci.draw_polyline(pts, color, width, true)


## A small padlock centred on `c`.
static func lock(ci: CanvasItem, c: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 9)), col)
	ci.draw_arc(c + Vector2(0, -3), 4.0, PI, TAU, 10, col, 2.0, true)


## "$27,000".
static func money(v: float) -> String:
	var s := str(int(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-$" if v < 0.0 else "$") + s + out


## A distance in the player's units, "5.7 km" / "3.5 mi".
static func dist(km: float) -> String:
	return "%.1f km" % km if Game.units_kmh else "%.1f mi" % (km / 1.609)


## The trophies' metals: gold, silver, bronze for 1st..3rd.
const TROPHY_COLOURS := [Color(1.0, 0.78, 0.22), Color(0.8, 0.84, 0.9), Color(0.82, 0.5, 0.26)]
const TROPHY_NAMES := ["GOLD", "SILVER", "BRONZE"]


## Frames of the trophies turning, by "tournament/place" ([] none to be had).
static var _trophy_art := {}


static func trophy_colour(place: int) -> Color:
	return TROPHY_COLOURS[clampi(place - 1, 0, 2)]


## High Stakes' own trophy of tournament `tour` (its tierdef id, 1..11) in the metal for
## `place` (1..3): FeArt/<tour>go.qfs, si, br, sixteen 120 px frames of it turning half way
## round (the design is near enough symmetric for them to loop). [] without the files.
static func trophy_frames(tour: int, place: int) -> Array[Texture2D]:
	var key := "%d/%d" % [tour, place]
	if not _trophy_art.has(key):
		var out: Array[Texture2D] = []
		if Game.hs_root != "" and tour > 0:
			var f := Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "feart"),
				"%d%s.qfs" % [tour, ["go", "si", "br"][clampi(place - 1, 0, 2)]]))
			if f:
				for img in f.images:
					out.append(ImageTexture.create_from_image(img))
		_trophy_art[key] = out
	return _trophy_art[key]


## A trophy `h` tall standing on `base` (the middle of its foot) in the metal for `place`
## (1..3): tournament `tour`'s own (trophy_frames), `turn` frames round (a float: the frame
## is its whole part), or without that art a drawn cup. `alpha` fades it in.
static func draw_trophy(ci: CanvasItem, base: Vector2, h: float, place: int, alpha := 1.0, tour := 0, turn := 0.0) -> void:
	var frames := trophy_frames(tour, place)
	if not frames.is_empty():
		var tex := frames[posmod(int(turn), frames.size())]
		ci.draw_texture_rect(tex, Rect2(base.x - h * 0.5, base.y - h, h, h), false, Color(1, 1, 1, alpha))
		return
	_draw_cup(ci, base, h, place, alpha)


## The drawn stand-in: bowl, handles, stem, plinth, a lighter side for its shine.
static func _draw_cup(ci: CanvasItem, base: Vector2, h: float, place: int, alpha: float) -> void:
	var col := Color(trophy_colour(place), alpha)
	var lit := Color(col.lightened(0.45), alpha)
	var dark := Color(col.darkened(0.35), alpha)
	var u := h / 100.0
	var p := func(x: float, y: float) -> Vector2: return base + Vector2(x, -y) * u
	# Plinth and foot.
	ci.draw_colored_polygon(PackedVector2Array([p.call(-30, 0), p.call(30, 0), p.call(27, 12), p.call(-27, 12)]), dark)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-19, 12), p.call(19, 12), p.call(12, 20), p.call(-12, 20)]), col)
	# Stem, with a knot.
	ci.draw_colored_polygon(PackedVector2Array([p.call(-5, 20), p.call(5, 20), p.call(4, 40), p.call(-4, 40)]), col)
	ci.draw_colored_polygon(PackedVector2Array([p.call(-9, 32), p.call(9, 32), p.call(7, 37), p.call(-7, 37)]), lit)
	# Handles: rings either side of the bowl.
	for s in [-1.0, 1.0]:
		ci.draw_arc(p.call(s * 34, 74), 13.0 * u, 0.0, TAU, 20, col, 5.0 * u, true)
	# The bowl: wide at the rim, round at the bottom.
	var bowl := PackedVector2Array()
	var shine := PackedVector2Array()
	for k in 13:
		var a := PI * k / 12.0
		bowl.append(p.call(-38 * cos(a), 62 - 22 * sin(a)))
	bowl.append(p.call(40, 100))
	bowl.append(p.call(-40, 100))
	ci.draw_colored_polygon(bowl, col)
	for k in 7:
		var a := PI * k / 12.0
		shine.append(p.call(-30 * cos(a), 64 - 16 * sin(a)))
	shine.append(p.call(-12, 94))
	shine.append(p.call(-32, 94))
	ci.draw_colored_polygon(shine, lit)
	# Rim.
	ci.draw_colored_polygon(PackedVector2Array([p.call(-43, 100), p.call(43, 100), p.call(41, 94), p.call(-41, 94)]), lit)
	# The place on the bowl.
	ci.draw_string(font("display"), p.call(-20, 60) + Vector2(0, 0), str(place), HORIZONTAL_ALIGNMENT_CENTER, 40 * u,
		int(34 * u), Color(dark, alpha))

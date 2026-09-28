class_name SignArt
extends RefCounted
## Road sign faces painted into one texture atlas, and the boards, posts and barricades that
## show them built into a few meshes: all the procedural track's traffic signs in a handful
## of draw calls (a Label3D is a draw call each). Lettering is set from the font's own glyph
## cache.

const SIZE := 2048
const PPM := 160.0           # atlas pixels per metre of sign
const CELL := 160.0          # m: the meshes are split into squares this big to be culled

const WHITE := Color(0.95, 0.95, 0.93)
const BLACK := Color(0.06, 0.06, 0.06)
const YELLOW := Color(0.98, 0.78, 0.1)
const GREEN := Color(0.05, 0.36, 0.18)
const RED := Color(0.75, 0.08, 0.07)
const BROWN := Color(0.46, 0.28, 0.13)
const ORANGE := Color(0.98, 0.45, 0.05)
const METAL := Color(0.62, 0.63, 0.65)

var atlas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
var font: FontFile
var _faces := {}             # name -> Rect2 in UV
var _shelf := Vector3i.ZERO  # x, y and height of the shelf being filled
var _glyphs := {}            # "px|glyph|colour" -> [Image, offset, advance]
var _chunks := {}            # Vector2i cell -> {v, n, uv[, ch]}
var _knockable: Array = []   # [chunk, from, count, frame, reach]
var metal: Rect2             # plain galvanised steel: posts and the backs of signs
var wood: Rect2
var body: StaticBody3D


func _init(p_body: StaticBody3D) -> void:
	body = p_body
	font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	metal = face("metal", Vector2(0.1, 0.1), func(img: Image) -> void: img.fill(METAL))
	wood = face("wood", Vector2(0.1, 0.1), func(img: Image) -> void: img.fill(Color(0.45, 0.34, 0.24)))


# --- Painting --------------------------------------------------------------------------------

## The UV rect of face `key`, `size` m, painted by `paint` (given a blank image) the first
## time it's asked for.
func face(key: String, size: Vector2, paint: Callable) -> Rect2:
	if _faces.has(key):
		return _faces[key]
	var w := maxi(int(size.x * PPM), 4)
	var h := maxi(int(size.y * PPM), 4)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	paint.call(img)
	const PAD := 3
	if _shelf.x + w + PAD * 2 > SIZE:
		_shelf = Vector3i(0, _shelf.y + _shelf.z, 0)
	if _shelf.y + h + PAD * 2 > SIZE:
		push_warning("SignArt: atlas full")
		return Rect2()
	var at := Vector2i(_shelf.x + PAD, _shelf.y + PAD)
	# Its edge pixels smeared into the padding, so mipmaps don't bleed the neighbours in.
	for d in range(PAD, 0, -1):
		atlas.blit_rect(img, Rect2i(0, 0, w, h), at + Vector2i(-d, 0))
		atlas.blit_rect(img, Rect2i(0, 0, w, h), at + Vector2i(d, 0))
		atlas.blit_rect(img, Rect2i(0, 0, w, h), at + Vector2i(0, -d))
		atlas.blit_rect(img, Rect2i(0, 0, w, h), at + Vector2i(0, d))
	atlas.blit_rect(img, Rect2i(0, 0, w, h), at)
	_shelf.x += w + PAD * 2
	_shelf.z = maxi(_shelf.z, h + PAD * 2)
	var r := Rect2(Vector2(at) / SIZE, Vector2(w, h) / SIZE)
	_faces[key] = r
	return r


## Fills polygon `pts` (pixels) in `c`, scanline by scanline.
static func poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size()
	for y in img.get_height():
		var fy := y + 0.5
		var xs := PackedFloat32Array()
		for k in n:
			var a := pts[k]
			var b := pts[(k + 1) % n]
			if (a.y <= fy) != (b.y <= fy):
				xs.append(a.x + (fy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := clampi(roundi(xs[k]), 0, img.get_width())
			var x1 := clampi(roundi(xs[k + 1]), 0, img.get_width())
			if x1 > x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0, 1), c)


## A regular shape inset `inset` px from the image's edge: "rect", "diamond", "octagon".
static func shape(img: Image, kind: String, inset: float, c: Color) -> void:
	var w := img.get_width() - inset * 2.0
	var h := img.get_height() - inset * 2.0
	var o := Vector2(inset, inset)
	var pts: PackedVector2Array
	match kind:
		"diamond":
			pts = [o + Vector2(w * 0.5, 0), o + Vector2(w, h * 0.5), o + Vector2(w * 0.5, h), o + Vector2(0, h * 0.5)]
		"octagon":
			var k := 0.2929
			pts = [o + Vector2(w * k, 0), o + Vector2(w * (1 - k), 0), o + Vector2(w, h * k), o + Vector2(w, h * (1 - k)),
				o + Vector2(w * (1 - k), h), o + Vector2(w * k, h), o + Vector2(0, h * (1 - k)), o + Vector2(0, h * k)]
		"pennant":
			pts = [o, o + Vector2(w, h * 0.5), o + Vector2(0, h)]
		"shield":
			pts = [o + Vector2(w * 0.08, 0), o + Vector2(w * 0.92, 0), o + Vector2(w, h * 0.35), o + Vector2(w * 0.85, h * 0.8),
				o + Vector2(w * 0.5, h), o + Vector2(w * 0.15, h * 0.8), o + Vector2(0, h * 0.35)]
		_:
			pts = [o, o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(0, h)]
	poly(img, pts, c)


## `t` centred on `centre` (pixels), capitals `cap` px tall, squeezed to fit `max_w` px.
func text(img: Image, t: String, centre: Vector2, cap: float, c: Color, max_w := 0.0) -> void:
	var px := int(cap / 0.7)
	var width := _measure(t, px)
	if max_w > 0.0 and width > max_w:
		px = maxi(int(px * max_w / width), 6)
		width = _measure(t, px)
	var x := centre.x - width * 0.5
	var base := centre.y + px * 0.7 * 0.5
	for ch in t:
		var g := _glyph(ch, px, c)
		if g[0] != null:
			var gi: Image = g[0]
			img.blend_rect(gi, Rect2i(Vector2i.ZERO, gi.get_size()), Vector2i(int(x + g[1].x), int(base + g[1].y)))
		x += g[2]


func _measure(t: String, px: int) -> float:
	var w := 0.0
	for ch in t:
		w += font.get_glyph_advance(0, px, font.get_glyph_index(px, ch.unicode_at(0), 0)).x
	return w


## [the glyph in colour `c` (null for a space), its offset from the pen, its advance].
func _glyph(ch: String, px: int, c: Color) -> Array:
	var key := "%d|%s|%s" % [px, ch, c.to_html()]
	if _glyphs.has(key):
		return _glyphs[key]
	var size := Vector2i(px, 0)
	var g := font.get_glyph_index(px, ch.unicode_at(0), 0)
	font.render_glyph(0, size, g)
	var ti := font.get_glyph_texture_idx(0, size, g)
	var uv := font.get_glyph_uv_rect(0, size, g)
	var out: Array = [null, font.get_glyph_offset(0, size, g), font.get_glyph_advance(0, px, g).x]
	if ti >= 0 and uv.size.x >= 1.0:
		var src: Image = font.get_texture_image(0, size, ti).get_region(Rect2i(uv.position, uv.size))
		src.convert(Image.FORMAT_RGBA8)
		var gi := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
		for y in src.get_height():
			for x in src.get_width():
				gi.set_pixel(x, y, Color(c, src.get_pixel(x, y).a))
		out[0] = gi
	_glyphs[key] = out
	return out


# --- Building --------------------------------------------------------------------------------

## The chunk of geometry for the square `at` is in: {v, n, uv} (non-indexed triangles).
func _st(at: Vector3) -> Dictionary:
	var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _chunks.has(cell):
		_chunks[cell] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}
	return _chunks[cell]


func _vert(st: Dictionary, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.v.append(p)
	st.n.append(n)
	st.uv.append(uv)


## A board `size` m centred at `c` in frame `xf`, facing its +Z, showing `uv`; its back plain
## metal unless `back` is false.
func board(xf: Transform3D, c: Vector3, size: Vector2, uv: Rect2, back := true) -> void:
	var st := _st(xf.origin)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var corners := [Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)]
	var uvs := [uv.position + Vector2(0, uv.size.y), uv.end, uv.position + Vector2(uv.size.x, 0), uv.position]
	var n := (xf.basis * Vector3.BACK).normalized()
	for k in [0, 2, 1, 0, 3, 2]:
		_vert(st, xf * (c + corners[k] + Vector3(0, 0, 0.01)), n, uvs[k])
	if back:
		var m := metal.get_center()
		for k in [0, 1, 2, 0, 2, 3]:
			_vert(st, xf * (c + corners[k] - Vector3(0, 0, 0.01)), -n, m)


## A box `size` m centred at `c` in frame `xf`, all over `uv` (a plain colour).
func box(xf: Transform3D, c: Vector3, size: Vector3, uv := Rect2(), solid := false) -> void:
	var st := _st(xf.origin)
	var m := (uv if uv.size != Vector2.ZERO else metal).get_center()
	var h := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var f := c + n * h[axis]
			var q := [f - u - v, f + u - v, f + u + v, f - u + v]
			var order := [0, 1, 2, 0, 2, 3] if sgn < 0.0 else [0, 2, 1, 0, 3, 2]
			var wn := (xf.basis * n).normalized()
			for k in order:
				_vert(st, xf * q[k], wn, m)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var o := body.create_shape_owner(body)
		body.shape_owner_add_shape(o, shape)
		body.shape_owner_set_transform(o, xf.orthonormalized() * Transform3D(Basis(), c))


## A post from the ground up `h` m at `c` (its foot) in frame `xf`; solid unless it's part
## of something a car knocks over (see knockable()).
func post(xf: Transform3D, c: Vector3, h: float, w := 0.08, solid := true) -> void:
	box(xf, c + Vector3(0, h * 0.5 - 0.3, 0), Vector3(w, h + 0.3, w), metal, solid)


## Where the next piece built at `at` starts: pass it to knockable() once the piece is built.
func mark(at: Vector3) -> Array:
	var st := _st(at)
	return [st, st.v.size()]


## Everything built since `m` (at `xf`, its foot) is knocked over by a car touching it within
## `reach` (in its frame): taken out of its chunk, and flying off as a piece of its own.
func knockable(m: Array, xf: Transform3D, reach: AABB) -> void:
	var st: Dictionary = m[0]
	_knockable.append([st, m[1], st.v.size() - m[1], xf, reach])


func flush(root: Node3D, breakables: Breakables = null) -> void:
	if _chunks.is_empty():
		return
	atlas.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(atlas)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.alpha_scissor_threshold = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.roughness = 0.5
	# Retro-reflective: lit up by headlights at night more than paint would be.
	mat.rim_enabled = true
	mat.rim = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # a loose sign tumbles
	for cell: Vector2i in _chunks:
		var st: Dictionary = _chunks[cell]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = st.v
		arrays[Mesh.ARRAY_NORMAL] = st.n
		arrays[Mesh.ARRAY_TEX_UV] = st.uv
		var ch := Breakables.chunk(arrays, mat)
		st["ch"] = ch
		var mi := MeshInstance3D.new()
		mi.mesh = ch.mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # thin: not worth the draw calls
		mi.visibility_range_end = 500.0
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	if breakables:
		for k: Array in _knockable:
			var st: Dictionary = k[0]
			var from: int = k[1]
			var count: int = k[2]
			var xf: Transform3D = k[3]
			breakables.add(xf, k[4], func() -> Array:
				return [Breakables.take_piece(st.ch, from, count, xf), null])

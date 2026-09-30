class_name Plates
## Licence plates from High Stakes' GameArt/plate.fsh: a blank US plate ("back") and a
## yellow European one ("euro"), and 8x20 glyphs named by character code, lettered onto
## them. A car's FCE4 dummy ":LICENSE" (":LICENSE EURO" on the European cars) marks where
## its rear plate goes.

const SIZE := Vector2(0.31, 0.155)   # m, a US plate (the texture is 2:1 either way)
const GLYPH := Vector2i(8, 20)

static var _fsh: Fsh
static var _tried := false
static var _pu_glyphs := {}      # Porsche Unleashed's, by character ("a".."z", "0".."9")
static var _pu_tried := false


static func available() -> bool:
	return _sheet() != null


## A random registration in the style of the plate: "4ABC123" or "AB51CDE".
static func random_text(euro: bool) -> String:
	var L := "ABCDEFGHJKLMNPRSTVWXYZ"
	var D := "0123456789"
	var pattern := "LLDDLLL" if euro else "DLLLDDD"
	var s := ""
	for ch in pattern:
		var pool := L if ch == "L" else D
		s += pool[randi() % pool.length()]
	return s


## The plate lettered with `text` (characters the sheet has no glyph for are left blank).
## The glyphs are stencils, light letters on black: each texel's lightness is how much of
## the plate's own darkest colour (its frame) goes on there.
static func texture(text: String, euro: bool) -> Texture2D:
	var f := _sheet()
	if f == null:
		return null
	var base: Image = f.by_name.get("euro" if euro else "back")
	if base == null:
		return null
	var img := base.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var all := Rect2i(Vector2i.ZERO, img.get_size())
	var ink := _darkest(img, all)
	var x0 := (img.get_width() - text.length() * GLYPH.x) / 2
	var y0 := img.get_height() - GLYPH.y - 3
	for i in text.length():
		var g: Image = f.by_name.get("%04x" % text.unicode_at(i))
		if g != null:
			_stamp(img, all, g, Vector2i(x0 + i * GLYPH.x, y0), ink, false)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The darkest texel in `at`, opaque.
static func _darkest(img: Image, at: Rect2i) -> Color:
	var ink := Color.WHITE
	for y in range(at.position.y, at.end.y):
		for x in range(at.position.x, at.end.x):
			var c := img.get_pixel(x, y)
			if c.get_luminance() < ink.get_luminance():
				ink = c
	ink.a = 1.0
	return ink


## Inks glyph `g` onto `page` at `pos` (clipped to `at`) in `ink`, by coverage: its
## lightness from its darkest to its lightest texel, or the reverse for `dark_letters`.
static func _stamp(page: Image, at: Rect2i, g: Image, pos: Vector2i, ink: Color, dark_letters: bool) -> void:
	var lo := 1.0
	var hi := 0.0
	for gy in g.get_height():
		for gx in g.get_width():
			var l := g.get_pixel(gx, gy).get_luminance()
			lo = minf(lo, l)
			hi = maxf(hi, l)
	if dark_letters:
		# The letters' own grey round them is the plate: anything lighter (the bevel) is too.
		hi = g.get_pixel(0, 0).get_luminance()
	if hi - lo < 0.01:
		return
	for gy in g.get_height():
		for gx in g.get_width():
			var p := pos + Vector2i(gx, gy)
			if not at.has_point(p):
				continue
			var t := clampf((g.get_pixel(gx, gy).get_luminance() - lo) / (hi - lo), 0.0, 1.0)
			page.set_pixelv(p, page.get_pixelv(p).lerp(ink, 1.0 - t if dark_letters else t))


## A plate to mount at a ":LICENSE" dummy: facing back (-Z), a touch proud of the bodywork.
static func make(text: String, euro: bool) -> MeshInstance3D:
	var tex := texture(text, euro)
	if tex == null:
		return null
	var quad := QuadMesh.new()
	quad.size = SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.6
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	# A QuadMesh faces +Z: turn it round.
	mi.rotation.y = PI
	return mi


## A random registration for a Porsche Unleashed plate: "ABC 123".
static func random_text_pu() -> String:
	var L := "ABCDEFGHJKLMNPRSTUVWXYZ"
	var s := ""
	for i in 3:
		s += L[randi() % L.length()]
	return s + " %03d" % (randi() % 1000)


## Letters `text` onto the blank plate at `at` in `page`, in Porsche Unleashed's glyphs
## (Render/license.psh under `pu_root`), centred, in the plate's own darkest colour. The
## glyphs are dark letters on a grey of their own. The plate comes out opaque: its edge
## texels' alpha 235 would take the paint.
static func letter_pu(page: Image, at: Rect2i, text: String, pu_root: String) -> void:
	var glyphs := _pu_sheet(pu_root)
	if glyphs.is_empty():
		return
	var ink := _darkest(page, at)
	for y in range(at.position.y, at.end.y):
		for x in range(at.position.x, at.end.x):
			var c := page.get_pixel(x, y)
			c.a = 1.0
			page.set_pixel(x, y, c)
	const ADVANCE := 8
	const SPACE := 4
	var width := 0
	for ch in text:
		width += SPACE if ch == " " else ADVANCE
	var gh: int = (glyphs.values()[0] as Image).get_height()
	var x := at.position.x + (at.size.x - width + 1) / 2
	var y := at.position.y + (at.size.y - gh) / 2
	for ch in text.to_lower():
		var g: Image = glyphs.get(ch)
		if g == null:
			x += SPACE
			continue
		_stamp(page, at, g, Vector2i(x, y), ink, true)
		x += ADVANCE


## Render/license.psh: a PS2-style "SHPP" archive of 4-bit images (code 0x40, rows padded
## to a byte, low nibble first), each followed by its 16-colour 1555 palette (code 0x23,
## at the image's next-block offset): a blank plate "blnk" and 7x12 glyphs named by letter.
static func _pu_sheet(pu_root: String) -> Dictionary:
	if _pu_tried:
		return _pu_glyphs
	_pu_tried = true
	var d := FileAccess.get_file_as_bytes(DataPath.find_ci(pu_root, "Render/license.psh"))
	if d.size() < 16 or d.slice(0, 4).get_string_from_ascii() != "SHPP":
		return _pu_glyphs
	for i in d.decode_s32(8):
		var name := d.slice(16 + i * 8, 20 + i * 8).get_string_from_ascii().strip_edges()
		var o := d.decode_s32(20 + i * 8)
		if name.length() != 1 or o + 16 > d.size() or d[o] != 0x40:
			continue
		var w := d.decode_u16(o + 4)
		var h := d.decode_u16(o + 6)
		var stride := (w + 1) / 2
		var po := o + (d[o + 1] | d[o + 2] << 8 | d[o + 3] << 16)
		if po + 16 + 32 > d.size() or o + 16 + stride * h > d.size():
			continue
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var b := d[o + 16 + y * stride + x / 2]
				var v := d.decode_u16(po + 16 + 2 * ((b & 15) if x % 2 == 0 else b >> 4))
				img.set_pixel(x, y, Color((v & 31) / 31.0, (v >> 5 & 31) / 31.0, (v >> 10 & 31) / 31.0))
		_pu_glyphs[name] = img
	return _pu_glyphs


static func _sheet() -> Fsh:
	if not _tried:
		_tried = true
		if Game.hs_root != "":
			_fsh = Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "gameart"), "plate.fsh"))
	return _fsh

class_name Plates
## Licence plates from High Stakes' GameArt/plate.fsh: a blank US plate ("back") and a
## yellow European one ("euro"), and 8x20 glyphs named by character code, lettered onto
## them. A car's FCE4 dummy ":LICENSE" (":LICENSE EURO" on the European cars) marks where
## its rear plate goes.

const SIZE := Vector2(0.31, 0.155)   # m, a US plate (the texture is 2:1 either way)
const GLYPH := Vector2i(8, 20)

static var _fsh: Fsh
static var _tried := false


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
static func texture(text: String, euro: bool) -> Texture2D:
	var f := _sheet()
	if f == null:
		return null
	var base: Image = f.by_name.get("euro" if euro else "back")
	if base == null:
		return null
	var img := base.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var x0 := (img.get_width() - text.length() * GLYPH.x) / 2
	var y0 := img.get_height() - GLYPH.y - 3
	for i in text.length():
		var g: Image = f.by_name.get("%04x" % text.unicode_at(i))
		if g == null:
			continue
		var gi := g.duplicate() as Image
		gi.convert(Image.FORMAT_RGBA8)
		img.blend_rect(gi, Rect2i(Vector2i.ZERO, gi.get_size()), Vector2i(x0 + i * GLYPH.x, y0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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


static func _sheet() -> Fsh:
	if not _tried:
		_tried = true
		if Game.hs_root != "":
			_fsh = Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "gameart"), "plate.fsh"))
	return _fsh

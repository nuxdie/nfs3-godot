class_name Nfs3Sfx
## The game's shared effect sprites, gamedata/render/pc/sfx.fsh. Used here:
##   skd0-skd3  skid marks: 0/1 dense tread (hard slides), 2/3 streaky (light ones)
##   SP10       pale puff: tyre smoke and, tinted, dust off loose ground
## Also in the file, not used yet: SP06/SP09 dark smoke (reads as a black blob on a young,
## opaque particle), SP02 dust, SP03 (an opaque 8x8 yellow square: square
## sparks close up, so sparks stay procedural), SP07/SP08 fire, SP01/SP04/SP05 debris,
## SN* (snow versions of SP*), glw* lamp glows, lin* light bars, spk8/spkb (spike strip),
## shad (car shadow; the track shader draws the same rounded rectangle itself).

## Four skid textures side by side (128x32), or null.
var skid_atlas: ImageTexture
## SP10 brightened to near white, so the particle colour sets its shade: grey-white smoke,
## ground-coloured dust (vertex colours above 1 are clamped, so it can't be brightened
## there). Null without game data.
var puff: ImageTexture

static var _cached: Nfs3Sfx
static var _cached_root := "-"


## Loaded once per data folder; null with no game data (effects fall back to procedural).
static func shared(data_root: String) -> Nfs3Sfx:
	if data_root == _cached_root:
		return _cached
	_cached_root = data_root
	_cached = null
	var fsh := Fsh.load_file(DataPath.find_ci(data_root, "gamedata/render/pc/sfx.fsh"))
	if fsh == null:
		return null
	var s := Nfs3Sfx.new()
	s.skid_atlas = _strip(fsh, ["skd0", "skd1", "skd2", "skd3"])
	if fsh.by_name.has("SP10"):
		s.puff = _whitened(fsh.by_name["SP10"])
	_cached = s
	return s


## `img` with its colour scaled so its brightest texel is white; alpha and speckle kept.
static func _whitened(img: Image) -> ImageTexture:
	var out := img.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	var peak := 0.01
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				peak = maxf(peak, maxf(c.r, maxf(c.g, c.b)))
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(minf(c.r / peak, 1.0), minf(c.g / peak, 1.0), minf(c.b / peak, 1.0), c.a))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


## Same-size images placed left to right in one mipmapped texture, or null if any is missing.
static func _strip(fsh: Fsh, names: Array) -> ImageTexture:
	var parts: Array[Image] = []
	for n: String in names:
		if not fsh.by_name.has(n):
			return null
		var img: Image = fsh.by_name[n].duplicate()
		img.convert(Image.FORMAT_RGBA8)
		parts.append(img)
	var sz := parts[0].get_size()
	var out := Image.create_empty(sz.x * parts.size(), sz.y, false, Image.FORMAT_RGBA8)
	for i in parts.size():
		if parts[i].get_size() != sz:
			parts[i].resize(sz.x, sz.y)
		out.blit_rect(parts[i], Rect2i(Vector2i.ZERO, sz), Vector2i(sz.x * i, 0))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)

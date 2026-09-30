class_name SkinHD
## Sharper car skins: an upscale of each skin made once, offline, by Real-ESRGAN (its anime
## model draws the skins' lines and panel edges thin and clean where filtering blurs or
## stair-steps them), cached under user:// per car and driver and swapped in when a car
## loads. `godot --path . -- --enhanceskins` (tools/enhance_skins.gd) makes them.
##
## The alpha channel is no picture but a set of marks the shaders test for exact values (the
## paint 117, a window pane 128, the cabin 224, cut-outs 0): it's upscaled as well, for smooth
## contours, then each texel snapped to the nearest of the values its source texels held.
## The texture carries its scale as the meta "skin_lod" (log2), which car.gdshader offsets
## its mip-based tests by.

const DIR := "user://skins_hd/"
const MODEL := "realesrgan-x4plus-anime"
const MAX_SIZE := 2048      # the upscale's longer side at most (a PU skin 2x, HS / NFS3 4x)

static var enabled := true


## The cached upscale of `name`'s skin, the one in `tex` now, or null. The skin the upscale
## was made from is kept beside it: the rows that differ (a Porsche Unleashed plate, lettered
## afresh at random each load) are patched in, scaled plainly; a skin that differs in more
## than a few places the loader has since built differently, and its upscale is stale.
static func find(tex: Texture2D, name: String) -> Texture2D:
	if tex == null or not FileAccess.file_exists(DIR + name + ".png"):
		return null
	var cur := _rgba8(tex.get_image())
	var was := Image.load_from_file(DIR + name + "_src.png")
	var img := Image.load_from_file(DIR + name + ".png")
	if cur == null or was == null or img == null or was.get_size() != cur.get_size() \
			or img.get_width() % cur.get_width() != 0:
		return null
	was.convert(Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	var s := img.get_width() / cur.get_width()
	var patches := _changes(cur, was)
	var area := 0
	for r: Rect2i in patches:
		area += r.get_area()
	if area * 50 > cur.get_width() * cur.get_height():
		return null
	for r: Rect2i in patches:
		var part := cur.get_region(r)
		part.resize(r.size.x * s, r.size.y * s, Image.INTERPOLATE_CUBIC)
		img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), r.position * s)
	img.generate_mipmaps()
	var hd := ImageTexture.create_from_image(img)
	hd.set_meta("skin_lod", int(round(log(s) / log(2.0))))
	return hd


## Swaps a loaded car's skin (car `path`, driver `who`) for its upscale, where there is one.
static func apply(car: Object, path: String, who: int) -> void:
	if not enabled or not ("texture" in car):
		return
	var hd := find(car.texture, key(path, who))
	if hd:
		car.texture = hd


## The cache name of car `path`'s skin with driver `who`.
static func key(path: String, who: int) -> String:
	return "%s_%s_d%d" % [path.replace(":", "_").get_file().validate_filename(), path.md5_text().left(8), who]


static func _rgba8(img: Image) -> Image:
	if img == null:
		return null
	img = img.duplicate() as Image
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Where `a` and `b` (the same size) differ: a rectangle per run of differing rows, 1 texel
## wider all round (the filtering's reach).
static func _changes(a: Image, b: Image) -> Array[Rect2i]:
	var w := a.get_width()
	var h := a.get_height()
	var da := a.get_data()
	var db := b.get_data()
	var out: Array[Rect2i] = []
	var run := Rect2i()
	var in_run := false
	for y in h + 1:
		var lo := -1
		var hi := -1
		if y < h:
			var row := y * w * 4
			if da.slice(row, row + w * 4) != db.slice(row, row + w * 4):
				for x in w:
					var i := row + x * 4
					if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2] or da[i + 3] != db[i + 3]:
						hi = x
						if lo < 0:
							lo = x
		if lo >= 0:
			var r := Rect2i(lo, y, hi - lo + 1, 1)
			run = run.merge(r) if in_run else r
			in_run = true
		elif in_run:
			out.append(run.grow(1).intersection(Rect2i(0, 0, w, h)))
			in_run = false
	return out


## Upscales the skin in `tex` (cache name `name`) with the Real-ESRGAN (ncnn-vulkan) at `exe` into the cache.
## Returns "" or what went wrong.
static func make(tex: Texture2D, name: String, exe: String, models: String, tmp: String) -> String:
	var src := _rgba8(tex.get_image())
	if src == null:
		return "no image"
	var w := src.get_width()
	var h := src.get_height()
	var s := 4
	while s > 1 and maxi(w, h) * s > MAX_SIZE:
		s /= 2
	if s == 1:
		return "already %dx%d" % [w, h]
	# The colour, and the alpha as a grey picture, each through the model (always 4x).
	var rgb := src.duplicate() as Image
	rgb.convert(Image.FORMAT_RGB8)
	var a_src := PackedByteArray()
	a_src.resize(w * h)
	var px := src.get_data()
	for i in w * h:
		a_src[i] = px[i * 4 + 3]
	var alpha := Image.create_from_data(w, h, false, Image.FORMAT_L8, a_src)
	alpha.convert(Image.FORMAT_RGB8)
	var out := []
	for pair in [[rgb, "rgb"], [alpha, "alpha"]]:
		var i_path := tmp.path_join("skin_%s.png" % pair[1])
		var o_path := tmp.path_join("skin_%s_x4.png" % pair[1])
		(pair[0] as Image).save_png(i_path)
		var said := []
		var code := OS.execute(exe, ["-i", i_path, "-o", o_path, "-n", MODEL, "-m", models], said, true)
		var up := Image.load_from_file(o_path)
		if code != 0 or up == null:
			return "Real-ESRGAN failed (%d): %s" % [code, "".join(PackedStringArray(said)).strip_edges().right(300)]
		if s != 4:
			up.resize(w * s, h * s, Image.INTERPOLATE_LANCZOS)
		out.append(up)
	var hd: Image = out[0]
	hd.convert(Image.FORMAT_RGBA8)
	var smooth: Image = out[1]
	smooth.convert(Image.FORMAT_L8)
	_snap_alpha(hd, a_src, w, h, smooth.get_data(), s)
	DirAccess.make_dir_recursive_absolute(DIR)
	var err := hd.save_png(DIR + name + ".png")
	if err == OK:
		err = src.save_png(DIR + name + "_src.png")
	return "" if err == OK else "save failed (%d)" % err


## Writes into `hd`'s alpha the upscaled alpha `smooth` snapped, texel by texel, to the
## nearest of the values held by the 2x2 source texels round it (`a_src`, w x h).
static func _snap_alpha(hd: Image, a_src: PackedByteArray, w: int, h: int, smooth: PackedByteArray, s: int) -> void:
	var W := hd.get_width()
	var H := hd.get_height()
	var data := hd.get_data()
	var x0s := PackedInt32Array()
	var x1s := PackedInt32Array()
	x0s.resize(W)
	x1s.resize(W)
	for x in W:
		var f := (x + 0.5) / s - 0.5
		x0s[x] = clampi(floori(f), 0, w - 1)
		x1s[x] = mini(maxi(floori(f), 0) + 1, w - 1) if f >= 0.0 else 0
	for y in H:
		var f := (y + 0.5) / s - 0.5
		var r0 := clampi(floori(f), 0, h - 1) * w
		var r1 := (mini(maxi(floori(f), 0) + 1, h - 1) if f >= 0.0 else 0) * w
		for x in W:
			var a := a_src[r0 + x0s[x]]
			var b := a_src[r0 + x1s[x]]
			var c := a_src[r1 + x0s[x]]
			var d := a_src[r1 + x1s[x]]
			var v := a
			if a != b or a != c or a != d:
				var t := smooth[y * W + x]
				var best := absi(t - a)
				for cand in [b, c, d]:
					var e := absi(t - cand)
					if e < best:
						best = e
						v = cand
			data[(y * W + x) * 4 + 3] = v
	hd.set_data(W, H, false, Image.FORMAT_RGBA8, data)

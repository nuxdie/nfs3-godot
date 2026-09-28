extends SceneTree
func _init() -> void:
	var font: FontFile = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	var px := 64
	var size := Vector2i(px, 0)
	var img := Image.create(400, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var x := 10.0
	for ch in "SPEED LIMIT 55":
		var g := font.get_glyph_index(px, ch.unicode_at(0), 0)
		font.render_glyph(0, size, g)
		var ti := font.get_glyph_texture_idx(0, size, g)
		var uv := font.get_glyph_uv_rect(0, size, g)
		var off := font.get_glyph_offset(0, size, g)
		var adv := font.get_glyph_advance(0, px, g)
		var atlas: Image = font.get_texture_image(0, size, ti).duplicate() if ti >= 0 else null
		if atlas and uv.size.x > 0:
			atlas.convert(Image.FORMAT_RGBA8)
			for yy in int(uv.size.y):
				for xx in int(uv.size.x):
					var c := atlas.get_pixel(int(uv.position.x) + xx, int(uv.position.y) + yy)
					var dx := int(x + off.x) + xx
					var dy := 80 + int(off.y) + yy
					if dx >= 0 and dx < 400 and dy >= 0 and dy < 100:
						img.set_pixel(dx, dy, img.get_pixel(dx, dy).lerp(Color.BLACK, c.a))
		x += adv.x
	img.save_png("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f96133d1-6062-41d5-9cfa-7f6f01e499de/scratchpad/t.png")
	quit()

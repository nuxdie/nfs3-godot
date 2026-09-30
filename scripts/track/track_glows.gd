class_name TrackGlows
## High Stakes' track glows: at each of the track's light sources (street lamps, beacons,
## windows), the glow its type picks from the .ini's [track glows] table, drawn day and
## night as the game does. Each is two additive sprites, sfx.fsh's glw0 at a fixed size on
## screen and glw3 as a halo in the world, dimmed with distance and blinking or cycling on
## and off where the table says (see track_glow.gdshader). Types past the table (100 and
## up on some tracks) have no glow.

const SHADER := preload("res://shaders/track_glow.gdshader")


## The glows for track `t` with the horizon's glow table, or null when there are none.
static func build(t: Nfs3Track, glows: Array[Dictionary]) -> Node3D:
	if t.glow_sprites.size() < 2 or glows.is_empty():
		return null
	var mm_data := []   # [position, color, custom] per glow
	for b in t.blocks:
		for i in mini(b.lights.size(), b.light_types.size()):
			var type := b.light_types[i]
			if type >= glows.size() or glows[type].is_empty():
				continue
			var g: Dictionary = glows[type]
			var color: Color = g["color"]
			var size: float = g["size"]
			if size <= 0.0 or color.a <= 0.0:
				continue
			var blink: float = g["blink"] * 256.0 + g["phase"] if g["blink"] >= 0 else -1.0
			mm_data.append([b.lights[i], color, Color(size, blink, g["on"], g["off"])])
	if mm_data.is_empty():
		return null
	var root := Node3D.new()
	root.name = "TrackGlows"
	var box := AABB(mm_data[0][0], Vector3.ZERO)
	for e in mm_data:
		box = box.expand(e[0])
	for k in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		mm.mesh = quad
		mm.instance_count = mm_data.size()
		for i in mm_data.size():
			mm.set_instance_transform(i, Transform3D(Basis(), mm_data[i][0]))
			mm.set_instance_color(i, mm_data[i][1])
			mm.set_instance_custom_data(i, mm_data[i][2])
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var img: Image = t.glow_sprites[k].duplicate()
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		mat.set_shader_parameter("sprite", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("screen_sized", k == 0)
		mat.set_shader_parameter("ticks_per_second", t.ticks_per_second)
		mat.set_shader_parameter("scale", Nfs4Track.SCALE)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flares" if k == 0 else "Halos"
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The sprites reach far past their points (the flares keep their size on screen).
		mmi.custom_aabb = box.grow(60.0)
		root.add_child(mmi)
	return root

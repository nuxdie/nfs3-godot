class_name Nfs6TrackBuilder
## Builds a Hot Pursuit 2 track (Nfs6Track) as Nfs5TrackBuilder does a Porsche Unleashed
## one (a mesh per chunk and pass, road and terrain bodies, solid scenery, the AI's walls;
## none for the player), but with HP2's layered surfaces: the track shader's `layered`
## mode blends each triangle's overlay over its base by the mask and multiplies in its
## shadow layer (Nfs6Track.LayerPiece).

## Its baked colours are full range.
const BRIGHTNESS := 1.0
## The sky dome's texture layers (its panorama is 1024 wide).
const SKY_TEX_SIZE := 1024


static func build(t: Nfs6Track, root: Node3D) -> TrackPath:
	var see_through := Nfs5TrackBuilder._see_through(t)
	var textures := Nfs5TrackBuilder._texture_array(t, see_through)
	var mats: Array[ShaderMaterial] = []
	for sh in [Nfs3TrackBuilder._shader, Nfs3TrackBuilder._additive_shader, Nfs3TrackBuilder._glass_shader]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("textures", textures)
		m.set_shader_parameter("textures_clamped", textures)
		m.set_shader_parameter("ticks_per_second", t.ticks_per_second)
		m.set_shader_parameter("brightness", BRIGHTNESS)
		mats.append(m)
	mats[Nfs5TrackBuilder.PASS_OPAQUE].set_shader_parameter("layered", true)
	root.set_meta("track_material", mats[0])
	root.set_meta("flybys", t.flybys)
	var night_mats: Array = root.get_meta("night_materials", [])
	night_mats.append(mats[2])
	root.set_meta("night_materials", night_mats)

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var road := Nfs5TrackBuilder._body("Road", 1)
	var terrain := Nfs5TrackBuilder._body("Terrain", 1)
	var scenery := Nfs5TrackBuilder._body("Scenery", Nfs3TrackBuilder.SCENERY_LAYER)
	var cam_block := Nfs5TrackBuilder._body("CameraBlockers", Nfs3TrackBuilder.CAMERA_LAYER)
	for bd in [road, terrain, scenery, cam_block]:
		root.add_child(bd)
	for bd in [road, terrain]:
		TrackSurface.set_images(bd, t.images)
	# Its images are numbered, not named: every cut-out (trees, bushes, fences) and
	# see-through image is passable.
	var passable := PackedByteArray()
	passable.resize(t.images.size())
	for i in passable.size():
		passable[i] = int(see_through[i] != 0)

	for ci in t.chunks.size():
		var pieces: Array = t.chunks[ci].pieces
		_add_meshes(geo, "Chunk%03d" % ci, pieces, see_through, mats, Nfs3TrackBuilder.DRAW_DISTANCE)
		Nfs5TrackBuilder._add_ground(road, pieces[Nfs5Track.Kind.ROAD], Nfs5TrackBuilder.SURFACE_ROAD)
		var ground := Nfs5TrackBuilder._split_steep(pieces[Nfs5Track.Kind.GROUND], see_through, passable)
		Nfs5TrackBuilder._add_ground(terrain, ground[0], Nfs5TrackBuilder.SURFACE_GROUND)
		Nfs5TrackBuilder._add_faces(scenery, ground[1])
		Nfs5TrackBuilder._add_solid(scenery, cam_block, pieces[Nfs5Track.Kind.SCENERY], passable)
	_add_meshes(geo, "Backdrop", t.backdrop, see_through, mats, 0.0)
	_add_sky(root, t)
	_add_smackables(root, t, see_through, mats)
	Nfs5TrackBuilder._add_ground(terrain, t.backdrop[Nfs5Track.Kind.GROUND], Nfs5TrackBuilder.SURFACE_GROUND)

	var path := Nfs3TrackBuilder._make_path(t)
	if not t.closed and t.sprint.size() == 4:
		path.set_open(t.sprint)
	if t.fences.size() == 2:
		path.wall_left = t.fences[0]
		path.wall_right = t.fences[1]
	path.lost_margin = Nfs5TrackBuilder.LOST_MARGIN
	var ai_walls := Nfs3TrackBuilder.make_walls(path)
	ai_walls.name = "AiWalls"
	ai_walls.collision_layer = Nfs3TrackBuilder.AI_WALL_LAYER
	root.add_child(ai_walls)
	return path


## A mesh per pass (opaque and cut-out, see-through), as Nfs5TrackBuilder._add_meshes, with
## the layers in CUSTOM1.zw (shadow uv), CUSTOM2 (overlay uv, mask uv) and CUSTOM3
## (overlay, mask, shadow image + 1).
static func _add_meshes(geo: Node3D, mesh_name: String, pieces: Array, see_through: PackedByteArray,
		mats: Array[ShaderMaterial], range_end: float) -> void:
	for pass_i in [Nfs5TrackBuilder.PASS_OPAQUE, Nfs5TrackBuilder.PASS_GLASS]:
		var mesh := _mesh(pieces, see_through, pass_i)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = mesh_name + Nfs3TrackBuilder.PASS_SUFFIX[pass_i]
		mi.mesh = mesh
		mi.material_override = mats[pass_i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mi.visibility_range_end = range_end
			mi.visibility_range_end_margin = 40.0
			mi.set_meta("landscape", true)
		geo.add_child(mi)


## The pieces' triangles of one pass (opaque and cut-out, or see-through) as a mesh, or null.
static func _mesh(pieces: Array, see_through: PackedByteArray, pass_i: int) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	for pc: Nfs6Track.LayerPiece in pieces:
		var wet := 1.0 if pc.kind == Nfs5Track.Kind.ROAD else 0.0
		for tri in pc.tex.size():
			var tex := pc.tex[tri]
			if (see_through[tex] == 2) != (pass_i == Nfs5TrackBuilder.PASS_GLASS):
				continue
			var i := tri * 3
			var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
			var ly := pc.layers[tri]
			for k in 3:
				pos.append(pc.pos[i + k])
				nrm.append(n)
				var c := pc.colour[i + k]
				c.a = wet
				col.append(c)
				uv.append(pc.uv[i + k])
				uv2.append(Vector2(tex, 0.0))
				var s := pc.uv_s[i + k]
				c1.append_array([0.0, 0.0, s.x, s.y])
				var b := pc.uv_b[i + k]
				var m := pc.uv_m[i + k]
				c2.append_array([b.x, b.y, m.x, m.y])
				c3.append_array([ly.x, ly.y, ly.z, 0.0])
	if pos.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_CUSTOM2] = c2
	arrays[Mesh.ARRAY_CUSTOM3] = c3
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


## level.dat's props (signs, barricades, cones) as KnockableProps: standing until a car
## touches them (only their part at car height, Nfs3TrackBuilder.PROP_REACH over their foot),
## then loose. A mesh per prop type, shared.
static func _add_smackables(root: Node3D, t: Nfs6Track, see_through: PackedByteArray,
		mats: Array[ShaderMaterial]) -> void:
	if t.smackables.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Props"
	root.add_child(holder)
	var kinds := []   # per type: [mesh, reach, hull] or null
	for pc in t.smackable_kinds:
		var mesh := _mesh([pc], see_through, Nfs5TrackBuilder.PASS_OPAQUE)
		if mesh == null or pc.pos.is_empty():
			kinds.append(null)
			continue
		var box := AABB(pc.pos[0], Vector3.ZERO)
		for v in pc.pos:
			box = box.expand(v)
		var low := AABB()
		var first := true
		for v in pc.pos:
			if v.y <= box.position.y + Nfs3TrackBuilder.PROP_REACH:
				low = AABB(v, Vector3.ZERO) if first else low.expand(v)
				first = false
		kinds.append([mesh, low, pc.pos])
	var sounds := Hp2PropSounds.for_level(Game.track_dir(Game.track_id))   # per type (hp2-sounds)
	for pr in t.smackables:
		var k: Variant = kinds[pr.type]
		if k == null:
			continue
		var prop := KnockableProp.new()
		prop.transform = pr.xform
		prop.setup(k[0], mats[Nfs5TrackBuilder.PASS_OPAQUE], k[1], k[2], Nfs3TrackBuilder.DRAW_DISTANCE)
		prop.knock_sounds = sounds[pr.type] if pr.type < sounds.size() else []
		holder.add_child(prop)

## The sky dome (Nfs6Track.sky) under its own shader (sky_dome.gdshader), one surface in its
## draw order.
static func _add_sky(root: Node3D, t: Nfs6Track) -> void:
	var pc := t.sky
	if pc.pos.is_empty() or t.sky_images.is_empty():
		return
	var layers: Array[Image] = []
	for im: Image in t.sky_images:
		var l := im.duplicate()
		l.convert(Image.FORMAT_RGBA8)
		l.resize(SKY_TEX_SIZE, SKY_TEX_SIZE, Image.INTERPOLATE_BILINEAR)
		l.generate_mipmaps()
		layers.append(l)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	var uv2 := PackedVector2Array()
	for tri in pc.tex.size():
		for k in 3:
			uv2.append(Vector2(pc.tex[tri], 0.0))
	var col := PackedColorArray()
	for c in pc.colour:
		col.append(Color(c.r, c.g, c.b, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pc.pos
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = pc.uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/sky_dome.gdshader")
	m.set_shader_parameter("textures", arr)
	m.render_priority = Material.RENDER_PRIORITY_MIN
	var mi := MeshInstance3D.new()
	mi.name = "SkyDome"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	root.add_child(mi)

class_name Nfs5TrackBuilder
## Builds a Porsche Unleashed track (Nfs5Track) into the same nodes Nfs3TrackBuilder makes
## for NFS3 and High Stakes, under the same track shaders: a mesh per chunk and pass, the
## road and terrain bodies (tagged for the tyres), solid scenery, camera blockers and the
## virtual road's walls. Its road is the articles flagged road, the ground under it the rest
## flagged ground (verges, fields, cliffs), but for the ground's steep faces (the walls of
## buildings, booths, rock faces), which are solid scenery; what isn't ground is scenery,
## solid where it's opaque (rails, posts) and passable where it's a cut-out (foliage).

## Its baked colours are half-bright: the game lights them at twice their value.
const BRIGHTNESS := 2.0
## Surface codes (TrackSurface) of the road and of the ground off it.
const SURFACE_ROAD := 1
const SURFACE_GROUND := 14
## Ground triangles steeper than this (normal's y) are walls: the sides of buildings, gate
## booths, retaining walls, rock faces.
const STEEP := 0.5
## Opaque scenery at least this big (m across, and high) keeps the chase camera out.
const CAMERA_BLOCK_SIZE := Vector2(6.0, 2.5)

enum { PASS_OPAQUE, PASS_FX, PASS_GLASS }


static func build(t: Nfs5Track, root: Node3D) -> TrackPath:
	var see_through := _see_through(t)
	var textures := _texture_array(t, see_through)
	var mats: Array[ShaderMaterial] = []
	for sh in [Nfs3TrackBuilder._shader, Nfs3TrackBuilder._additive_shader, Nfs3TrackBuilder._glass_shader]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("textures", textures)
		m.set_shader_parameter("textures_clamped", textures)
		m.set_shader_parameter("ticks_per_second", t.ticks_per_second)
		m.set_shader_parameter("brightness", BRIGHTNESS)
		mats.append(m)
	root.set_meta("track_material", mats[0])
	root.set_meta("flybys", t.flybys)   # the race's start fly-by
	var night_mats: Array = root.get_meta("night_materials", [])
	night_mats.append(mats[2])
	root.set_meta("night_materials", night_mats)

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var road := _body("Road", 1)
	var terrain := _body("Terrain", 1)
	var scenery := _body("Scenery", Nfs3TrackBuilder.SCENERY_LAYER)
	var cam_block := _body("CameraBlockers", Nfs3TrackBuilder.CAMERA_LAYER)
	for bd in [road, terrain, scenery, cam_block]:
		root.add_child(bd)
	for bd in [road, terrain]:
		TrackSurface.set_images(bd, t.images)

	for ci in t.chunks.size():
		var c: Dictionary = t.chunks[ci]
		_add_meshes(geo, "Chunk%03d" % ci, c.pieces, see_through, mats, Nfs3TrackBuilder.DRAW_DISTANCE)
		_add_ground(road, c.pieces[Nfs5Track.Kind.ROAD], SURFACE_ROAD)
		var ground := _split_steep(c.pieces[Nfs5Track.Kind.GROUND])
		_add_ground(terrain, ground[0], SURFACE_GROUND)
		_add_faces(scenery, ground[1])
		_add_solid(scenery, cam_block, c.pieces[Nfs5Track.Kind.SCENERY], see_through)
	_add_meshes(geo, "Backdrop", t.backdrop, see_through, mats, 0.0)
	_add_ground(terrain, t.backdrop[Nfs5Track.Kind.GROUND], SURFACE_GROUND)

	var path := Nfs3TrackBuilder._make_path(t)
	if not t.closed and t.sprint.size() == 4:
		path.set_open(t.sprint)
	root.add_child(Nfs3TrackBuilder.make_walls(path))
	return path


static func _body(body_name: String, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = body_name
	b.collision_layer = layer
	b.collision_mask = 0
	return b


## Per image: 0 opaque, 1 cut-out (foliage, fences: alpha-tested), 2 see-through (glass,
## water: alpha-blended), as Nfs3TrackBuilder._mark_translucent tells them apart.
static func _see_through(t: Nfs5Track) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(t.images.size())
	for i in t.images.size():
		var im: Image = t.images[i]
		if im.detect_alpha() == Image.ALPHA_NONE:
			continue
		if im.get_format() != Image.FORMAT_RGBA8:
			im = im.duplicate()
			im.convert(Image.FORMAT_RGBA8)
		var d := im.get_data()
		var part := 0
		var clear := 0
		for k in range(3, d.size(), 4):
			if d[k] >= 26 and d[k] <= 230:
				part += 1
			elif d[k] < 26:
				clear += 1
		if part >= Nfs3TrackBuilder.TRANSLUCENT_MIN * (d.size() / 4):
			out[i] = 2
		elif clear > 0:
			out[i] = 1
	return out


static func _texture_array(t: Nfs5Track, see_through: PackedByteArray) -> Texture2DArray:
	var layers: Array[Image] = []
	for i in t.images.size():
		var im: Image = t.images[i].duplicate()
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		if see_through[i] != 2:
			Nfs3TrackBuilder._bleed_alpha(im)
		im.resize(Nfs3TrackBuilder.TEX_SIZE, Nfs3TrackBuilder.TEX_SIZE, Image.INTERPOLATE_BILINEAR)
		im.generate_mipmaps()
		layers.append(im)
	if layers.is_empty():
		var blank := Image.create(Nfs3TrackBuilder.TEX_SIZE, Nfs3TrackBuilder.TEX_SIZE, true, Image.FORMAT_RGBA8)
		blank.fill(Color.GRAY)
		layers.append(blank)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	return arr


## A mesh per pass (opaque and cut-out, see-through) of the pieces' triangles. The road's
## are marked (vertex alpha 1) for the shader to wet in the rain. `range` 0: no draw limit.
static func _add_meshes(geo: Node3D, mesh_name: String, pieces: Array, see_through: PackedByteArray,
		mats: Array[ShaderMaterial], range_end: float) -> void:
	for pass_i in [PASS_OPAQUE, PASS_GLASS]:
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for pc: Nfs5Track.Piece in pieces:
			var wet := 1.0 if pc.kind == Nfs5Track.Kind.ROAD else 0.0
			for tri in pc.tex.size():
				var tex := pc.tex[tri]
				if (see_through[tex] == 2) != (pass_i == PASS_GLASS):
					continue
				var i := tri * 3
				var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
				for k in 3:
					pos.append(pc.pos[i + k])
					nrm.append(n)
					var c := pc.colour[i + k]
					c.a = wet
					col.append(c)
					uv.append(pc.uv[i + k])
					uv2.append(Vector2(tex, 0.0))
		if pos.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
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


## The piece's triangles as a collision shape of `body`, each tagged with its surface and
## texture (TrackSurface).
static func _add_ground(body: StaticBody3D, pc: Nfs5Track.Piece, surface: int) -> void:
	if pc.pos.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(pc.pos)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var surf := PackedByteArray()
	surf.resize(pc.tex.size())
	surf.fill(surface)
	TrackSurface.tag(cs, surf, pc.tex)
	body.add_child(cs)


## The ground articles hold the walls standing on the ground too (buildings, booths, rock
## faces): [the level part, a Piece for the terrain the tyres run on; the steep triangles'
## corners], the steep ones for solid scenery, which the AI's scan of the road looks out for
## (TrackPath.scan_obstacles) where it passes over the terrain.
static func _split_steep(pc: Nfs5Track.Piece) -> Array:
	var level := Nfs5Track.Piece.new()
	level.kind = pc.kind
	var steep := PackedVector3Array()
	for tri in pc.tex.size():
		var i := tri * 3
		var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
		if absf(n.y) < STEEP:
			steep.append_array([pc.pos[i], pc.pos[i + 1], pc.pos[i + 2]])
			continue
		for k in 3:
			level.pos.append(pc.pos[i + k])
			level.uv.append(pc.uv[i + k])
			level.colour.append(pc.colour[i + k])
		level.tex.append(pc.tex[tri])
	return [level, steep]


static func _add_faces(body: StaticBody3D, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## The opaque scenery triangles as solid scenery; those of it big enough keep the camera out
## too. Cut-outs (foliage) and see-through ones are left passable.
static func _add_solid(scenery: StaticBody3D, cam_block: StaticBody3D, pc: Nfs5Track.Piece,
		see_through: PackedByteArray) -> void:
	var faces := PackedVector3Array()
	for tri in pc.tex.size():
		if see_through[pc.tex[tri]] != 0:
			continue
		var i := tri * 3
		faces.append_array([pc.pos[i], pc.pos[i + 1], pc.pos[i + 2]])
	if faces.is_empty():
		return
	for bd: StaticBody3D in [scenery, cam_block]:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		bd.add_child(cs)

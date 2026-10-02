class_name Nfs5TrackBuilder
## Builds a Porsche Unleashed track (Nfs5Track) into the same nodes Nfs3TrackBuilder makes
## for NFS3 and High Stakes, under the same track shaders: a mesh per chunk and pass, the
## road and terrain bodies (tagged for the tyres), solid scenery, camera blockers and the
## virtual road's walls, for the AI only: the player has none. Its road is the articles
## flagged road, the ground under it the rest flagged ground (verges, fields, cliffs), but for the ground's steep faces (the walls of
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
## How far (m) past the fences a car off the road may get before the race puts it back
## (TrackPath.lost_margin), as on the procedural track, which has no walls either.
const LOST_MARGIN := 120.0
## Opaque scenery at least this big (m across, and high) keeps the chase camera out.
const CAMERA_BLOCK_SIZE := Vector2(6.0, 2.5)
## The cut-out images that are plants (by their name in the .fsh: grass, flowers, bushes,
## ferns, reeds, vines, moss, trees and tree lines) and the glows round lamps: a car goes
## through them, wherever they stand. Every other cut-out (rails, fences, railings, signs,
## lamp posts, stonework) is solid.
const PASSABLE_CUTOUTS := [
	"abtb", "abtc", "aldr", "alt1", "alt2", "cabs", "cas1", "cas2", "cas3", "cbb1", "cbb4",
	"crnf", "crns", "dais", "decb", "decc", "dedt", "drka", "evrc", "evrs", "evrt", "fern",
	"fhb1", "fhb2", "fhb3", "fhb4", "fhca", "fhna", "fhpt", "fht1", "fht2", "fht3", "fht5",
	"fht6", "fhtb", "fhte", "fhtl", "fhtm", "fhts", "ftl2", "ftl3", "ftl4", "ftl5", "ftl6",
	"ftl7", "gpvf", "graz", "grvn", "lin1", "lin2", "litc", "mos1", "mos2", "moss", "nbsh",
	"oake", "oakf", "oakg", "palm", "rots", "shrb", "stl5", "stmb", "trl3", "vine", "vinf",
	"alfl", "bsha", "bshb", "clin", "deca", "decf", "evra", "mos3", "oaka", "sh80", "trl2",
]
## Images soft enough at the edges to pass for see-through (Nfs3TrackBuilder.TRANSLUCENT_MIN)
## that are cut-outs all the same: plants (the last row of PASSABLE_CUTOUTS), washing on a
## line, a balcony's railing. Blended in the glass pass they'd be drawn in no order (it
## writes no depth), each chunk's over the next's as the camera moves: bushes half drawn,
## popping in and out.
const CUTOUT_SOFT := [
	"alfl", "bsha", "bshb", "clin", "deca", "decf", "evra", "mos3", "oaka", "sh80", "trl2",
	"fe01",
]

## The guardrails' and railings' images: their upright triangles are taken out of the chunk
## meshes into Guardrails, cut into columns so a car's hit bends them.
const RAIL_IMAGES := [
	"abgr", "abor", "abr1", "abr2", "abr3", "abr6", "absg", "bar1", "bar2", "bar4", "bar5",
	"barr", "gud1", "gud2",
]
## m: the longest (along the ground) a rail triangle's edge is left. Twice
## Nfs3TrackBuilder.RAIL_COLUMN: PU's rails run for kilometres, and a hit (Guardrails.RADIUS)
## still bends them in a curve.
const RAIL_COLUMN := 1.0
## Chunks of rail meshed together.
const RAIL_CHUNKS := 4

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
	var passable := _passable_images(t, see_through)
	var rail_images := {}
	for i in t.image_names.size():
		if RAIL_IMAGES.has(t.image_names[i]):
			rail_images[i] = true
	var rails := Guardrails.new()
	rails.name = "Guardrails"
	root.add_child(rails)
	var rail_mesh := Nfs3TrackBuilder._rail_arrays()

	for ci in t.chunks.size():
		var c: Dictionary = t.chunks[ci]
		var taken := _take_rails(c.pieces, rail_images, rail_mesh)
		var pieces: Array = taken[0]
		_add_faces(scenery, taken[1])
		_add_meshes(geo, "Chunk%03d" % ci, pieces, see_through, mats, Nfs3TrackBuilder.DRAW_DISTANCE)
		_add_ground(road, pieces[Nfs5Track.Kind.ROAD], SURFACE_ROAD)
		var ground := _split_steep(pieces[Nfs5Track.Kind.GROUND], see_through, passable)
		_add_ground(terrain, ground[0], SURFACE_GROUND)
		_add_faces(scenery, ground[1])
		_add_solid(scenery, cam_block, pieces[Nfs5Track.Kind.SCENERY], passable)
		if (ci % RAIL_CHUNKS == RAIL_CHUNKS - 1 or ci == t.chunks.size() - 1) \
				and rail_mesh[0][Mesh.ARRAY_VERTEX].size() > 0:
			rails.add_chunk(rail_mesh[0], rail_mesh[1], mats[PASS_OPAQUE], Nfs3TrackBuilder.DRAW_DISTANCE)
			rail_mesh = Nfs3TrackBuilder._rail_arrays()
	_add_meshes(geo, "Backdrop", t.backdrop, see_through, mats, 0.0)
	if t.backdrop_far:
		for mi in geo.get_children():
			if mi is MeshInstance3D and mi.name.begins_with("Backdrop"):
				mi.set_instance_shader_parameter("far_away", true)
	var night_only: Array = root.get_meta("night_only", [])
	night_only.append_array(_add_props(t, geo, see_through, mats))
	var particles := PuParticles.build(t, Game.pu_root) if Game.quality != Game.Quality.LOW else null
	if particles:
		geo.add_child(particles)
	# The lamps' flares, at night (TrackWorld shows the "night_only" nodes then).
	var glows := PuGlows.build(t, Game.pu_root)
	if glows:
		geo.add_child(glows)
		night_only.append(glows)
	root.set_meta("night_only", night_only)
	_add_ground(terrain, t.backdrop[Nfs5Track.Kind.GROUND], SURFACE_GROUND)

	var path := Nfs3TrackBuilder._make_path(t)
	if not t.closed and t.sprint.size() == 4:
		path.set_open(t.sprint)
	if t.fences.size() == 2:
		path.wall_left = t.fences[0]
		path.wall_right = t.fences[1]
	for side_road: Array in t.side_roads:
		for vr: Nfs3Track.VRoad in side_road:
			path.add_side_slice(vr.pos, vr.right.normalized(), vr.left_wall, vr.right_wall)
	# No walls for the player: the car goes wherever the ground and the solid scenery let it,
	# and the race only puts it back far out (LOST_MARGIN). The AI, the traffic and the cops
	# keep to the lap between walls of their own (their cars don't take the shortcuts).
	path.lost_margin = LOST_MARGIN
	var ai_walls := Nfs3TrackBuilder.make_walls(path)
	ai_walls.name = "AiWalls"
	ai_walls.collision_layer = Nfs3TrackBuilder.AI_WALL_LAYER
	root.add_child(ai_walls)
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
		var soft := i < t.image_names.size() and CUTOUT_SOFT.has(t.image_names[i])
		if part >= Nfs3TrackBuilder.TRANSLUCENT_MIN * (d.size() / 4) and not soft:
			out[i] = 2
		elif clear > 0 or soft:
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
		var scroll := PackedFloat32Array()   # CUSTOM1: the UVs' scroll a second (water)
		var scrolls := false
		for pc: Nfs5Track.Piece in pieces:
			var wet := 1.0 if pc.kind == Nfs5Track.Kind.ROAD else 0.0
			for tri in pc.tex.size():
				var tex := pc.tex[tri]
				if (see_through[tex] == 2) != (pass_i == PASS_GLASS):
					continue
				# (UV2.y bit 0: the shader's one_sided.)
				var side := 1.0 if tri < pc.one_sided.size() and pc.one_sided[tri] else 0.0
				var i := tri * 3
				var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
				for k in 3:
					pos.append(pc.pos[i + k])
					nrm.append(n)
					var c := pc.colour[i + k]
					c.a = wet
					col.append(c)
					uv.append(pc.uv[i + k])
					uv2.append(Vector2(tex, side))
					var sc := pc.scroll[tri]
					scroll.append_array([sc.x, sc.y])
					scrolls = scrolls or sc != Vector2.ZERO
		if pos.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var flags := 0
		if scrolls:
			arrays[Mesh.ARRAY_CUSTOM1] = scroll
			flags = Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
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


## [`pieces` without the upright triangles of the rails (`rail_images`); those triangles'
## corners, for solid scenery]. The rails are appended to `out` (from
## Nfs3TrackBuilder._rail_arrays) instead, cut so no edge spans more than RAIL_COLUMN, each
## corner leaning by its height up its triangle (see Guardrails).
static func _take_rails(pieces: Array, rail_images: Dictionary, out: Array) -> Array:
	var faces := PackedVector3Array()
	if rail_images.is_empty():
		return [pieces, faces]
	var arrays: Array = out[0]
	var kept := []
	for pc: Nfs5Track.Piece in pieces:
		if pc.kind == Nfs5Track.Kind.ROAD:
			kept.append(pc)
			continue
		var rest := Nfs5Track.Piece.new()
		rest.kind = pc.kind
		for tri in pc.tex.size():
			var i := tri * 3
			var tex := pc.tex[tri]
			var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
			if not rail_images.has(tex) or absf(n.y) >= STEEP:
				for k in 3:
					rest.pos.append(pc.pos[i + k])
					rest.uv.append(pc.uv[i + k])
					rest.colour.append(pc.colour[i + k])
				rest.tex.append(tex)
				rest.scroll.append(pc.scroll[tri])
				continue
			faces.append_array([pc.pos[i], pc.pos[i + 1], pc.pos[i + 2]])
			var lo := minf(pc.pos[i].y, minf(pc.pos[i + 1].y, pc.pos[i + 2].y))
			var height := maxf(pc.pos[i].y, maxf(pc.pos[i + 1].y, pc.pos[i + 2].y)) - lo
			var uv2 := Vector2(tex, 0.0)
			# Halve the longest edge (along the ground) until none is longer than a column.
			var todo := [[pc.pos[i], pc.pos[i + 1], pc.pos[i + 2], pc.uv[i], pc.uv[i + 1], pc.uv[i + 2],
				pc.colour[i], pc.colour[i + 1], pc.colour[i + 2]]]
			while not todo.is_empty():
				var t: Array = todo.pop_back()
				var e := 0
				var longest := 0.0
				for k in 3:
					var d: Vector3 = t[(k + 1) % 3] - t[k]
					var l := Vector2(d.x, d.z).length()
					if l > longest:
						longest = l
						e = k
				if longest > RAIL_COLUMN:
					var a := e
					var b := (e + 1) % 3
					var m := [(t[a] + t[b]) * 0.5, (t[3 + a] + t[3 + b]) * 0.5, (t[6 + a] as Color).lerp(t[6 + b], 0.5)]
					var t1 := t.duplicate()
					var t2 := t.duplicate()
					for q in 3:
						t1[q * 3 + b] = m[q]
						t2[q * 3 + a] = m[q]
					todo.append(t1)
					todo.append(t2)
					continue
				for k in 3:
					var c: Color = t[6 + k]
					c.a = 0.0
					arrays[Mesh.ARRAY_VERTEX].append(t[k])
					arrays[Mesh.ARRAY_NORMAL].append(n)
					arrays[Mesh.ARRAY_COLOR].append(c)
					arrays[Mesh.ARRAY_TEX_UV].append(t[3 + k])
					arrays[Mesh.ARRAY_TEX_UV2].append(uv2)
					out[1].append(clampf(((t[k] as Vector3).y - lo) / height, 0.0, 1.0) if height > 0.0 else 1.0)
		kept.append(rest)
	return [kept, faces]


## The animated props (Nfs5Track.props), each a node KeyframeMover loops through its keys
## (Nfs5Track.ANIM_KEYS_PER_SECOND) with its meshes and lights' flares (PuGlows) under it.
## They're passable. The flares, for showing only at night.
static func _add_props(t: Nfs5Track, geo: Node3D, see_through: PackedByteArray,
		mats: Array[ShaderMaterial]) -> Array:
	var flares := []
	for pr: Dictionary in t.props:
		var node := Node3D.new()
		node.name = "Prop_" + String(pr.name).validate_node_name()
		node.position = pr.keys[0].pos
		node.quaternion = pr.keys[0].rot
		node.scale = pr.keys[0].scale
		node.set_script(preload("res://scripts/track/keyframe_mover.gd"))
		node.set("keys", pr.keys)
		node.set("delay", 1)
		node.set("tick_rate", Nfs5Track.ANIM_KEYS_PER_SECOND)
		_add_meshes(node, "Mesh", [pr.piece], see_through, mats, Nfs3TrackBuilder.DRAW_DISTANCE)
		_add_vertex_frames(node, pr, see_through, mats)
		var glows := PuGlows.glows(pr.lights, Game.pu_root)
		if glows:
			node.add_child(glows)
			flares.append(glows)
		geo.add_child(node)
	return flares


## A person's motion (the prop's frames) as a mesh per frame for each of `node`'s meshes,
## swapped by vertex_frames.gd.
static func _add_vertex_frames(node: Node3D, pr: Dictionary, see_through: PackedByteArray,
		mats: Array[ShaderMaterial]) -> void:
	var targets: Array[MeshInstance3D] = []
	for c in node.get_children():
		if c is MeshInstance3D:
			targets.append(c)
	if pr.frames.is_empty() or targets.is_empty():
		return
	var piece: Nfs5Track.Piece = pr.piece
	var frames := []
	for pos: PackedVector3Array in pr.frames:
		if pos.size() != piece.pos.size():
			return
		var pc := Nfs5Track.Piece.new()
		pc.kind = piece.kind
		pc.pos = pos
		pc.uv = piece.uv
		pc.colour = piece.colour
		pc.tex = piece.tex
		pc.scroll = piece.scroll
		var tmp := Node3D.new()
		_add_meshes(tmp, "Mesh", [pc], see_through, mats, 0.0)
		var meshes := tmp.get_children().map(func(m: MeshInstance3D) -> Mesh: return m.mesh)
		tmp.free()
		if meshes.size() != targets.size():
			return
		frames.append(meshes)
	var vf := Node.new()
	vf.name = "Motion"
	vf.set_script(preload("res://scripts/track/vertex_frames.gd"))
	vf.set("targets", targets)
	vf.set("frames", frames)
	vf.set("fps", Nfs5Track.ANIM_KEYS_PER_SECOND)
	node.add_child(vf)


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
## (TrackPath.scan_obstacles) where it passes over the terrain. Plants (grass, flowers,
## bushes on the verges) are neither: a car goes through them, however they lean.
static func _split_steep(pc: Nfs5Track.Piece, see_through: PackedByteArray,
		passable: PackedByteArray) -> Array:
	var level := Nfs5Track.Piece.new()
	level.kind = pc.kind
	var steep := PackedVector3Array()
	for tri in pc.tex.size():
		var tex := pc.tex[tri]
		if see_through[tex] == 1 and passable[tex]:
			continue
		var i := tri * 3
		var n := (pc.pos[i + 2] - pc.pos[i]).cross(pc.pos[i + 1] - pc.pos[i]).normalized()
		if absf(n.y) < STEEP:
			steep.append_array([pc.pos[i], pc.pos[i + 1], pc.pos[i + 2]])
			continue
		for k in 3:
			level.pos.append(pc.pos[i + k])
			level.uv.append(pc.uv[i + k])
			level.colour.append(pc.colour[i + k])
		level.tex.append(tex)
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


## The scenery triangles as solid scenery, but for the see-through ones and the plants
## (PASSABLE_CUTOUTS); those of it big enough keep the camera out too.
static func _add_solid(scenery: StaticBody3D, cam_block: StaticBody3D, pc: Nfs5Track.Piece,
		passable: PackedByteArray) -> void:
	var faces := PackedVector3Array()
	for tri in pc.tex.size():
		if passable[pc.tex[tri]]:
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


## Per image, 1 where scenery a car goes through: see-through (glass, water) or a cut-out
## plant (PASSABLE_CUTOUTS).
static func _passable_images(t: Nfs5Track, see_through: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(t.images.size())
	for i in out.size():
		out[i] = int(see_through[i] == 2 or see_through[i] == 1 and i < t.image_names.size() \
			and PASSABLE_CUTOUTS.has(t.image_names[i]))
	return out

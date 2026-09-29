class_name Nfs3TrackBuilder
## Turns parsed Nfs3Track data into a scene: one mesh per track block (with a
## visibility range, like the original's draw distance), road collision and
## invisible walls along the edge of the drivable surface.

const TEX_SIZE := 256
const DRAW_DISTANCE := 700.0
const WALL_HEIGHT := 6.0
const WALL_DEPTH := 3.0
## The longest run of road edge (m, across) that is taken for the end of a ledge, left
## open to drop off, rather than the side of a raised road.
const LEDGE_END_MAX := 16.0
## Physics layer of the solid scenery that only the chase camera collides with.
const CAMERA_LAYER := 8
## Physics layer of solid scenery (buildings, signs, posts, rocks) that cars hit. Kept off
## layer 1 so the chase camera ignores small props.
const SCENERY_LAYER := 4
## Physics layer of the water surfaces (streams, lakes): nothing collides with them, the
## race looks for them to tell a car that has gone in.
const WATER_LAYER := 16
## How far out (m) from the road's edge water opens its wall: enough for a bank down to a
## stream, short of letting cars out across open country.
const WATER_REACH := 30.0
## Extra objects no wider than this (m) and within this height range are road signs and
## posts that cars knock over; taller poles and anything bigger stay put.
const PROP_MAX_WIDTH := 3.5
const PROP_HEIGHT := Vector2(1.5, 7.0)
## Height (m) above a prop's foot that a car body can touch.
const PROP_REACH := 1.5
## Cut-out billboards at least this tall (m) get a solid trunk: trees, lamp posts.
const TRUNK_MIN_HEIGHT := 3.5
## A trunk's width (m) is its texture's opaque run at the foot, within these bounds; a
## wider run is a bush or a hedge, which stays passable.
const TRUNK_WIDTH := Vector2(0.3, 1.2)
## Height (m) of trunk and post colliders: enough for any car.
const POST_HEIGHT := 4.0
## Upright cut-out quads within these heights (m) and at least FENCE_MIN_WIDTH wide, opaque
## across their foot, are fence, railing and guardrail panels. Panels up to
## FENCE_KNOCK_WIDTH are knocked over like signs; longer ones (bridge parapets) are solid.
const FENCE_HEIGHT := Vector2(0.5, 4.5)
const FENCE_MIN_WIDTH := 2.5
const FENCE_KNOCK_WIDTH := 10.0
## Knockable panels are separate draw calls (hundreds on a track): drawn nearer than the
## blocks, which a thin fence barely shows beyond anyway.
const FENCE_DRAW_DISTANCE := 300.0
## Upright cut-out quads within these heights (m) and at least RAIL_MIN_WIDTH wide, at the
## road's edge and with a continuous rail along their top, are guardrails that bend when
## hit (see Guardrails).
const RAIL_HEIGHT := Vector2(0.4, 1.6)
const RAIL_MIN_WIDTH := 1.5
## Guardrail panels are cut into columns about this wide (m) so they bend in a curve.
const RAIL_COLUMN := 0.5
## Track blocks per guardrail mesh.
const RAIL_CHUNK_BLOCKS := 4
## Additive textures that are daylight (sun shafts), per track: faded out at night, while
## glows and fire keep shining. Hometown's are the shafts in its two covered bridges.
const SUNLIGHT_TEXTURES := {"trk000": [195]}

static var _shader: Shader = preload("res://shaders/track.gdshader")
static var _additive_shader: Shader = preload("res://shaders/track_additive.gdshader")


static func build(t: Nfs3Track, root: Node3D) -> TrackPath:
	var textures := _texture_array(t)
	# [opaque, additive]: effect textures (light shafts, glows, fire) are blended additively.
	var mats: Array[ShaderMaterial] = []
	for sh in [_shader, _additive_shader]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("textures", textures)
		mats.append(m)
	root.set_meta("track_material", mats[0])   # the race sets its night lighting
	var night_mats: Array = root.get_meta("night_materials", [])
	night_mats.append(mats[1])                 # ...and fades the sun shafts
	root.set_meta("night_materials", night_mats)

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	# The drivable surface (road, verges, shortcuts) and the scenery terrain beyond it are
	# separate bodies so the race can tell a car on a shortcut from one that got out.
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.collision_layer = 1
	terrain.collision_mask = 0
	root.add_child(terrain)
	for bd in [body, terrain]:
		TrackSurface.set_images(bd, t.images)

	var rails := Guardrails.new()
	rails.name = "Guardrails"
	root.add_child(rails)
	var rail_mesh := _rail_arrays()

	var road_quads := _drivable_quads(t)
	var foliage := {}
	var fence_faces := PackedVector3Array()
	for bi in t.blocks.size():
		var b: Nfs3Track.Block = t.blocks[bi]
		_mark_compound(b)
		# Fence panels: short ones leave the block mesh to be knocked over, long ones stay
		# in it and are made solid.
		var knocked := {}
		for panel in _fence_panels(t, b, road_quads, foliage, false):
			if panel.width <= FENCE_KNOCK_WIDTH:
				props.add_child(_make_panel(t, panel, mats[0]))
				for m in panel.members:
					knocked[m[0][0]] = true
			else:
				var c: PackedVector3Array = panel.corners
				fence_faces.append_array([c[0], c[1], c[2], c[0], c[2], c[3]])
		# Guardrails leave it to be bent.
		for panel in _fence_panels(t, b, road_quads, foliage, true):
			_add_rail(t, panel, rail_mesh)
			for m in panel.members:
				knocked[m[0][0]] = true
		if (bi % RAIL_CHUNK_BLOCKS == RAIL_CHUNK_BLOCKS - 1 or bi == t.blocks.size() - 1) \
				and rail_mesh[0][Mesh.ARRAY_VERTEX].size() > 0:
			rails.add_chunk(rail_mesh[0], rail_mesh[1], mats[0], DRAW_DISTANCE)
			rail_mesh = _rail_arrays()
		var standing := func(p: Nfs3Track.Poly) -> bool: return not knocked.has(p)
		# The road's drivable polys are flagged so the shader can wet them in the rain; its
		# painted lines (no flags: all drivable) with it.
		var groups := [[b.road, b.verts, b.shading, Vector3.ZERO, false, b.road_flags],
			[b.lanes, b.verts, b.shading, Vector3.ZERO, false, PackedByteArray()]]
		for obj in b.objects:
			groups.append([obj.filter(standing) if knocked.size() > 0 else obj, b.verts, b.shading, Vector3.ZERO, false])
		for x in b.xobjs:
			if x.has("anim"):
				continue
			if _is_prop(t, x):
				props.add_child(_make_prop(t, x, mats[0]))
			else:
				groups.append([x.polys.filter(standing) if knocked.size() > 0 else x.polys, x.verts, x.shading, x.ref, _mirrored(x)])
		for pass_i in 2:
			var mesh := _mesh(t, groups, pass_i == 1)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Block%03d%s" % [bi, "Fx" if pass_i == 1 else ""]
			mi.mesh = mesh
			mi.material_override = mats[pass_i]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = DRAW_DISTANCE
			mi.visibility_range_end_margin = 40.0
			mi.set_meta("landscape", true)   # keeps its range on Low quality (see Race)
			geo.add_child(mi)

		# Collision: the block's ground (road and terrain).
		var faces := PackedVector3Array()
		var terrain_faces := PackedVector3Array()
		# Per triangle, for TrackSurface (what the tyres are on): [surface, texture] each.
		var faces_surf := [PackedByteArray(), PackedInt32Array()]
		var terrain_surf := [PackedByteArray(), PackedInt32Array()]
		for i in b.road.size():
			var p: Nfs3Track.Poly = b.road[i]
			if p.v[0] >= b.verts.size() or p.v[1] >= b.verts.size() or p.v[2] >= b.verts.size() or p.v[3] >= b.verts.size():
				continue
			var drivable := i >= b.road_flags.size() or Nfs3Track.drivable(b.road_flags[i])
			for k in Nfs3Track.QUAD:
				if drivable:
					faces.append(b.verts[p.v[k]])
				else:
					terrain_faces.append(b.verts[p.v[k]])
			var surf: Array = faces_surf if drivable else terrain_surf
			var tex: int = t.textures[p.tex].qfs_index if p.tex < t.textures.size() else -1
			for tri in 2:
				surf[0].append(b.road_flags[i] & 0x0F if i < b.road_flags.size() else TrackSurface.UNKNOWN)
				surf[1].append(tex)
		for pair in [[body, faces, faces_surf], [terrain, terrain_faces, terrain_surf]]:
			if pair[1].size() > 0:
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(pair[1])
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				TrackSurface.tag(cs, pair[2][0], pair[2][1])
				pair[0].add_child(cs)

		# Animated extra objects (planes, boats, ...): keyframed along the track.
		for x in b.xobjs:
			if not x.has("anim") or x.anim.size() == 0:
				continue
			for pass_i in 2:
				var amesh := _mesh(t, [[x.polys, x.verts, x.shading, Vector3.ZERO, _mirrored(x)]], pass_i == 1)
				if amesh == null:
					continue
				var ami := MeshInstance3D.new()
				ami.mesh = amesh
				ami.material_override = mats[pass_i]
				ami.visibility_range_end = DRAW_DISTANCE * 1.5
				ami.set_script(preload("res://scripts/track/keyframe_mover.gd"))
				ami.set("keys", x.anim)
				ami.set("delay", x.get("anim_delay", 1))
				geo.add_child(ami)

	# Global scenery from the .col file.
	var global_groups := []
	for o in t.col_objects:
		global_groups.append([o.polys, o.verts, o.shading, o.ref, false])
	for pass_i in 2:
		var gmesh := _mesh(t, global_groups, pass_i == 1)
		if gmesh == null:
			continue
		var gmi := MeshInstance3D.new()
		gmi.name = "GlobalObjects%s" % ("Fx" if pass_i == 1 else "")
		gmi.mesh = gmesh
		gmi.material_override = mats[pass_i]
		geo.add_child(gmi)

	var water := _water_quads(t)
	root.add_child(_scenery_body(t, fence_faces))
	root.add_child(_camera_blockers(t))
	root.add_child(_water_body(water[0]))
	root.add_child(_edge_walls(t, road_quads, water))
	return _make_path(t)


## Cars collide with every opaque scenery object: buildings, bridge piers and road signs
## stand inside the virtual road's walls. The track files carry no per-object collision
## flag, so foliage and other cut-out billboards, glows and lane markings stay passable,
## except for the trunks and posts they stand on (see _post_boxes). `extra_faces` are the
## long fence panels (see _fence_panels).
static func _scenery_body(t: Nfs3Track, extra_faces := PackedVector3Array()) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Scenery"
	body.collision_layer = SCENERY_LAYER
	body.collision_mask = 0
	var faces := PackedVector3Array()
	for b in t.blocks:
		for obj in b.objects:
			_solid_faces(t, obj, b.verts, Vector3.ZERO, faces, false)
		for x in b.xobjs:
			if not x.has("anim") and not _is_prop(t, x):
				_solid_faces(t, x.polys, x.verts, x.ref, faces, false)
	for o in t.col_objects:
		_solid_faces(t, o.polys, o.verts, o.ref, faces, false)
	faces.append_array(extra_faces)
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	for box in _post_boxes(t):
		var bs := BoxShape3D.new()
		bs.size = box.size
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.position = box.get_center()
		body.add_child(cs)
	return body


## Solid boxes for what the scenery mesh alone would let a car through: the trunks of
## cut-out trees and lamp posts (a flat billboard, whose foot is found in the texture's
## alpha), and thin opaque posts (a quad or two, too thin to stop a fast car).
static func _post_boxes(t: Nfs3Track) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var seen := {}
	for b in t.blocks:
		for obj in b.objects:
			_trunk_boxes(t, obj, b.verts, Vector3.ZERO, false, boxes, seen)
		for x in b.xobjs:
			if x.has("anim") or _is_prop(t, x):
				continue
			_trunk_boxes(t, x.polys, x.verts, x.ref, _mirrored(x), boxes, seen)
			var box := _poly_box(x.polys, x.verts)
			if maxf(box.size.x, box.size.z) <= 2.0 and box.size.y >= 2.0 and _has_solid(t, x.polys):
				var size := Vector3(maxf(box.size.x, TRUNK_WIDTH.x), minf(box.size.y, POST_HEIGHT),
						maxf(box.size.z, TRUNK_WIDTH.x))
				var foot: Vector3 = x.ref + Vector3(box.get_center().x, box.position.y, box.get_center().z)
				boxes.append(AABB(foot - Vector3(size.x, 0.0, size.z) * 0.5, size))
	for o in t.col_objects:
		_trunk_boxes(t, o.polys, o.verts, o.ref, false, boxes, seen)
	return boxes


static func _has_solid(t: Nfs3Track, polys: Array) -> bool:
	for p in polys:
		if p.tex < t.textures.size():
			var ti: Nfs3Track.TexInfo = t.textures[p.tex]
			if not (ti.cutout or ti.additive or ti.is_lane):
				return true
	return false


## Appends a box per trunk standing at the foot of the objects' tall upright cut-out quads.
## `seen` (grid cells) drops the duplicates from a tree's crossed or front/back quads.
static func _trunk_boxes(t: Nfs3Track, polys: Array, verts: PackedVector3Array, offset: Vector3,
		mirrored: bool, out: Array[AABB], seen: Dictionary) -> void:
	const COLS := FOOT_COLUMNS
	var order: Array = [1, 0, 3, 2] if mirrored else [0, 1, 2, 3]
	for p in polys:
		if p.tex >= t.textures.size():
			continue
		var ti: Nfs3Track.TexInfo = t.textures[p.tex]
		if not ti.cutout or ti.additive or ti.is_lane or ti.qfs_index >= t.images.size():
			continue
		if p.v[0] >= verts.size() or p.v[1] >= verts.size() or p.v[2] >= verts.size() or p.v[3] >= verts.size():
			continue
		var pos: Array[Vector3] = []
		for k in 4:
			pos.append(verts[p.v[order[k]]] + offset)
		var lo := minf(minf(pos[0].y, pos[1].y), minf(pos[2].y, pos[3].y))
		var height := maxf(maxf(pos[0].y, pos[1].y), maxf(pos[2].y, pos[3].y)) - lo
		var normal := (pos[2] - pos[0]).cross(pos[1] - pos[0]).normalized()
		if height < TRUNK_MIN_HEIGHT or absf(normal.y) > 0.3:
			continue
		# The bottom edge (A, B).
		var ia := _bottom_edge(pos)
		var ib := (ia + 1) % 4
		var width := pos[ia].distance_to(pos[ib])
		if width < 0.1:
			continue
		# Opaque columns over the bottom metre of the quad.
		var solid := _foot_columns(t, ti, ia, minf(1.0 / height, 0.2), 2.0 / 3.0)
		# Runs of opaque columns, bridging gaps of up to 2 columns (a pine's lowest branches).
		var runs: Array[Vector2i] = []
		var c0 := 0
		while c0 < COLS:
			if not solid[c0]:
				c0 += 1
				continue
			var c1 := c0
			var c := c0 + 1
			while c < COLS and c <= c1 + 3:
				if solid[c]:
					c1 = c
				c += 1
			runs.append(Vector2i(c0, c1))
			c0 = c1 + 1
		# A tree or a post stands on one foot (a half of a split tree on a foot at its edge);
		# more are the bars of a fence or a gate (see _fence_panels).
		if runs.size() != 1:
			continue
		var frac := float(runs[0].y - runs[0].x + 1) / COLS
		var run := frac * width
		var at := (runs[0].x + runs[0].y + 1) * 0.5 / COLS
		var size := clampf(run, TRUNK_WIDTH.x, TRUNK_WIDTH.y)
		if run > TRUNK_WIDTH.y:
			size = TRUNK_WIDTH.y * 0.5
			# Foliage down to the ground (a pine): the trunk is hidden in the middle of it,
			# or at the edge of a half tree. Wall to wall, it is a hedge.
			if height < 6.0 or frac >= 0.6:
				continue
			if runs[0].x == 0:
				at = size * 0.5 / width
			elif runs[0].y == COLS - 1:
				at = 1.0 - size * 0.5 / width
		var foot := pos[ia].lerp(pos[ib], at)
		var cell := Vector3i((foot / 0.5).round())
		if not seen.has(cell):
			seen[cell] = true
			out.append(AABB(foot - Vector3(size, 0.0, size) * 0.5, Vector3(size, POST_HEIGHT, size)))


const FOOT_COLUMNS := 32


## Index of the corner that starts a quad's bottom edge (the lowest pair of neighbours).
static func _bottom_edge(pos: Array[Vector3]) -> int:
	var i := 0
	var best := INF
	for k in 4:
		var y := pos[k].y + pos[(k + 1) % 4].y
		if y < best:
			best = y
			i = k
	return i


## Which of FOOT_COLUMNS columns across an upright cut-out quad are opaque over the bottom
## `reach` (share of its height), counting a column when at least `min_share` of its samples
## are. `ia` is the corner starting the bottom edge.
static func _foot_columns(t: Nfs3Track, ti: Nfs3Track.TexInfo, ia: int, reach: float,
		min_share: float) -> Array[bool]:
	const ROWS := 6
	var ib := (ia + 1) % 4
	var ic := (ia + 2) % 4
	var id := (ia + 3) % 4
	var img: Image = t.images[ti.qfs_index]
	var w := img.get_width()
	var h := img.get_height()
	var solid: Array[bool] = []
	for c in FOOT_COLUMNS:
		var s := (c + 0.5) / FOOT_COLUMNS
		var hits := 0
		for r in ROWS:
			var f := (r + 0.5) / ROWS * reach
			var uv := ti.uv[ia].lerp(ti.uv[ib], s).lerp(ti.uv[id].lerp(ti.uv[ic], s), f)
			var px := clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1)
			var py := clampi(int(fposmod(uv.y, 1.0) * h), 0, h - 1)
			if img.get_pixel(px, py).a > 0.5:
				hits += 1
		solid.append(hits >= ROWS * min_share - 0.001)
	return solid


## The block's fence panels (see FENCE_HEIGHT) that stand on the drivable surface, with
## road on both sides: those at its edge are backed by the invisible walls already. With
## `rail`, those guardrails at its edge instead (see RAIL_HEIGHT). Each is
## {members: [[polys, verts, shading, offset, mirrored]], corners: bottom edge first, width};
## a panel drawn as a front and a back quad over the same corners is one panel. `drivable`
## is from _drivable_quads; `foliage` caches _is_foliage per image.
static func _fence_panels(t: Nfs3Track, b: Nfs3Track.Block, drivable: Array,
		foliage: Dictionary, rail: bool) -> Array:
	var heights := RAIL_HEIGHT if rail else FENCE_HEIGHT
	var sources := []
	for obj in b.objects:
		sources.append([obj, b.verts, b.shading, Vector3.ZERO, false])
	for x in b.xobjs:
		if not x.has("anim"):
			sources.append([x.polys, x.verts, x.shading, x.ref, _mirrored(x)])
	var by_corners := {}
	var panels := []
	for src in sources:
		var verts: PackedVector3Array = src[1]
		var order: Array = [1, 0, 3, 2] if src[4] else [0, 1, 2, 3]
		for p: Nfs3Track.Poly in src[0]:
			if p.tex >= t.textures.size():
				continue
			var ti: Nfs3Track.TexInfo = t.textures[p.tex]
			if not ti.cutout or ti.additive or ti.is_lane or ti.qfs_index >= t.images.size():
				continue
			if p.v[0] >= verts.size() or p.v[1] >= verts.size() or p.v[2] >= verts.size() or p.v[3] >= verts.size():
				continue
			var pos: Array[Vector3] = []
			for k in 4:
				pos.append(verts[p.v[order[k]]] + src[3])
			var lo := minf(minf(pos[0].y, pos[1].y), minf(pos[2].y, pos[3].y))
			var height := maxf(maxf(pos[0].y, pos[1].y), maxf(pos[2].y, pos[3].y)) - lo
			var normal := (pos[2] - pos[0]).cross(pos[1] - pos[0]).normalized()
			if height < heights.x or height > heights.y or absf(normal.y) > 0.3:
				continue
			var ia := _bottom_edge(pos)
			var width := pos[ia].distance_to(pos[(ia + 1) % 4])
			var n := FOOT_COLUMNS
			if rail:
				# Road on one side and a continuous rail along the top.
				if width < RAIL_MIN_WIDTH or _road_sides(drivable, pos[ia], pos[(ia + 1) % 4]) != 1 \
						or _is_foliage(t, ti.qfs_index, foliage) \
						or _foot_columns(t, ti, (ia + 2) % 4, 0.3, 0.5).count(true) < n * 3 / 4:
					continue
			elif width < FENCE_MIN_WIDTH or _road_sides(drivable, pos[ia], pos[(ia + 1) % 4]) != 2 \
					or _is_foliage(t, ti.qfs_index, foliage):
				continue
			else:
				# Opaque at both ends of its foot and, between them, mostly opaque (rails,
				# planks, lattice) or barred: a bush's foot is one run short of the edges.
				var solid := _foot_columns(t, ti, ia, minf(1.0 / height, 1.0), 1.0 / 3.0)
				if not (solid[0] or solid[1] or solid[2]) or not (solid[n - 1] or solid[n - 2] or solid[n - 3]):
					continue
				var count := 0
				var runs := 0
				for c in n:
					if solid[c]:
						count += 1
						if c == 0 or not solid[c - 1]:
							runs += 1
				if count < n / 2 and runs < 3:
					continue
				# And a rail, plank or frame along its top: a grass or dirt fringe along the
				# foot of a field is see-through above it.
				if _foot_columns(t, ti, (ia + 2) % 4, 0.25, 1.0 / 3.0).count(true) < n / 4:
					continue
			var keys := []
			for v in pos:
				var r := (v * 100.0).round()
				keys.append("%d,%d,%d" % [r.x, r.y, r.z])
			keys.sort()
			var key := ";".join(keys)
			var member := [[p], verts, src[2], src[3], src[4]]
			if by_corners.has(key):
				by_corners[key].members.append(member)
				continue
			var corners := PackedVector3Array()
			for k in 4:
				corners.append(pos[(ia + k) % 4])
			by_corners[key] = {"members": [member], "corners": corners, "width": width}
			panels.append(by_corners[key])
	return panels


## On how many sides (0-2) of the upright quad standing on `a`-`b` there is drivable surface.
static func _road_sides(drivable: Array, a: Vector3, b: Vector3) -> int:
	var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * 1.5
	var sides := 0
	for s in [side, -side]:
		for f: float in [0.25, 0.5, 0.75]:
			if _road_near(drivable[0], drivable[1], a.lerp(b, f) + s, 1.5):
				sides += 1
				break
	return sides


## Whether an image is plant life (a bush, hedge or grass fringe): its opaque texels are
## green on average.
static func _is_foliage(t: Nfs3Track, index: int, cache: Dictionary) -> bool:
	if not cache.has(index):
		var img: Image = t.images[index]
		var sum := Color(0, 0, 0, 0)
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					sum += c
		cache[index] = sum.g > sum.r * 1.05 and sum.g > sum.b * 1.05
	return cache[index]


## A knockable fence panel. Its frame runs along the panel (X) so the trigger box that
## catches the cars stays as thin as the panel, whichever way it faces.
static func _make_panel(t: Nfs3Track, panel: Dictionary, material: Material) -> KnockableProp:
	var c: PackedVector3Array = panel.corners
	var along := Vector3(c[1].x - c[0].x, 0.0, c[1].z - c[0].z).normalized()
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var foot := (c[0] + c[1]) * 0.5
	foot.y = minf(c[0].y, c[1].y)
	var to_local := Transform3D(basis, foot).affine_inverse()
	# The panel's quads over their own local copy of the corners.
	var groups := []
	var hull := PackedVector3Array()
	var box := AABB()
	for m: Array in panel.members:
		var p: Nfs3Track.Poly = m[0][0]
		var verts := PackedVector3Array()
		var shading := PackedColorArray()
		var q := Nfs3Track.Poly.new()
		q.v = PackedInt32Array([0, 1, 2, 3])
		q.tex = p.tex
		q.flags = p.flags
		q.anim_frames = p.anim_frames
		q.anim_period = p.anim_period
		for k in 4:
			var v: Vector3 = to_local * (m[1][p.v[k]] + m[3])
			verts.append(v)
			shading.append(m[2][p.v[k]] if p.v[k] < m[2].size() else Color.WHITE)
			box = AABB(v, Vector3.ZERO) if hull.is_empty() else box.expand(v)
			# A flat hull has no volume: give the loose panel some thickness.
			hull.append(v + Vector3(0, 0, 0.05))
			hull.append(v - Vector3(0, 0, 0.05))
		groups.append([[q], verts, shading, Vector3.ZERO, m[4]])
	var prop := KnockableProp.new()
	prop.transform = Transform3D(basis, foot)
	prop.setup(_mesh(t, groups, false), material, box, hull, FENCE_DRAW_DISTANCE)
	return prop


## Empty guardrail mesh data: [arrays (Mesh.ARRAY_MAX), lean per vertex] (see Guardrails).
static func _rail_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	return [arrays, PackedFloat32Array()]


## Appends a guardrail panel to `out` (from _rail_arrays), drawn as _add_polys would but cut
## into RAIL_COLUMN wide columns so it can bend.
static func _add_rail(t: Nfs3Track, panel: Dictionary, out: Array) -> void:
	var arrays: Array = out[0]
	var c: PackedVector3Array = panel.corners
	var lo := minf(minf(c[0].y, c[1].y), minf(c[2].y, c[3].y))
	var height := maxf(maxf(c[0].y, c[1].y), maxf(c[2].y, c[3].y)) - lo
	var cols := maxi(ceili(panel.width / RAIL_COLUMN), 1)
	# A front and a back quad over the same corners: cull each one's back face.
	var one_sided := 1.0 if panel.members.size() > 1 else 0.0
	for m: Array in panel.members:
		var p: Nfs3Track.Poly = m[0][0]
		var verts: PackedVector3Array = m[1]
		var shading: PackedColorArray = m[2]
		var ti: Nfs3Track.TexInfo = t.textures[p.tex]
		var order: Array = [1, 0, 3, 2] if m[4] else [0, 1, 2, 3]
		var pos: Array[Vector3] = []
		var cols_of: Array[Color] = []
		for k in 4:
			var vi: int = p.v[order[k]]
			pos.append(verts[vi] + m[3])
			var sc: Color = shading[vi] if vi < shading.size() else Color.WHITE
			sc.a = 0.0
			cols_of.append(sc)
		var ia := _bottom_edge(pos)
		var ib := (ia + 1) % 4
		var ic := (ia + 2) % 4
		var id := (ia + 3) % 4
		var frames := _anim_frames(t, p)
		var uv2 := Vector2(ti.qfs_index, one_sided + (2.0 * frames + 16.0 * p.anim_period if frames > 1 else 0.0))
		for col in cols:
			# The column's corners in the quad's own winding: foot, foot, top, top.
			var cp: Array[Vector3] = []
			var cuv: Array[Vector2] = []
			var cc: Array[Color] = []
			for e in [[ia, ib, float(col) / cols], [ia, ib, float(col + 1) / cols],
					[id, ic, float(col + 1) / cols], [id, ic, float(col) / cols]]:
				cp.append(pos[e[0]].lerp(pos[e[1]], e[2]))
				cuv.append(ti.uv[e[0]].lerp(ti.uv[e[1]], e[2]))
				cc.append(cols_of[e[0]].lerp(cols_of[e[1]], e[2]))
			var normal := (cp[2] - cp[0]).cross(cp[1] - cp[0]).normalized()
			for k in Nfs3Track.QUAD:
				arrays[Mesh.ARRAY_VERTEX].append(cp[k])
				arrays[Mesh.ARRAY_NORMAL].append(normal)
				arrays[Mesh.ARRAY_COLOR].append(cc[k])
				arrays[Mesh.ARRAY_TEX_UV].append(cuv[k])
				arrays[Mesh.ARRAY_TEX_UV2].append(uv2)
				out[1].append(clampf((cp[k].y - lo) / height, 0.0, 1.0) if height > 0.0 else 1.0)


## Sign-sized extra objects with an opaque post or plate and no foliage (foliage cut-outs are
## left standing: the car passes through them anyway). A cut-out plate is still a sign: High
## Stakes' round and triangular ones are see-through at the corners.
static var _foliage_cache := {}

static func _is_prop(t: Nfs3Track, x: Dictionary) -> bool:
	if not x.has("prop"):
		x.prop = false
		if x.get("compound", false):
			return false
		var box := _poly_box(x.polys, x.verts)
		if box.size != Vector3.ZERO and maxf(box.size.x, box.size.z) <= PROP_MAX_WIDTH \
				and box.size.y >= PROP_HEIGHT.x and box.size.y <= PROP_HEIGHT.y:
			var opaque := false
			x.prop = true
			for p in x.polys:
				if p.tex >= t.textures.size():
					continue
				var ti: Nfs3Track.TexInfo = t.textures[p.tex]
				if ti.additive or ti.is_lane or ti.qfs_index >= t.images.size() \
						or ti.cutout and _is_foliage(t, ti.qfs_index, _foliage_cache.get_or_add(t.get_instance_id(), {})):
					x.prop = false
					break
				opaque = opaque or not ti.cutout
			x.prop = x.prop and opaque
	return x.prop


## Flags the single-quad extra objects that touch another one: faces of a bigger thing
## (the Hometown covered bridge's posts are four quads each), not signs to knock over.
static func _mark_compound(b: Nfs3Track.Block) -> void:
	var boxes := []
	for x in b.xobjs:
		var box := _poly_box(x.polys, x.verts)
		boxes.append(AABB(box.position + x.ref, box.size).grow(0.05))
	for i in b.xobjs.size():
		if b.xobjs[i].polys.size() != 1:
			continue
		for j in b.xobjs.size():
			if j != i and boxes[i].intersects(boxes[j]):
				b.xobjs[i].compound = true
				break


static func _make_prop(t: Nfs3Track, x: Dictionary, material: Material) -> KnockableProp:
	var box := _poly_box(x.polys, x.verts)
	var foot := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	# Only the polys that reach down to car height can be hit: a sign's post, not its plate.
	var low := []
	for p in x.polys:
		for k in 4:
			if p.v[k] < x.verts.size() and x.verts[p.v[k]].y < box.position.y + PROP_REACH:
				low.append(p)
				break
	var reach := _poly_box(low, x.verts) if low.size() > 0 else box
	reach = AABB(reach.position - foot, Vector3(reach.size.x, minf(reach.size.y, PROP_REACH), reach.size.z))
	var hull := PackedVector3Array()
	for v in x.verts:
		hull.append(v - foot)
	var prop := KnockableProp.new()
	prop.position = x.ref + foot
	prop.setup(_mesh(t, [[x.polys, x.verts, x.shading, -foot, _mirrored(x)]], false), material,
			reach, hull, DRAW_DISTANCE)
	return prop


static func _poly_box(polys: Array, verts: PackedVector3Array) -> AABB:
	var box := AABB()
	var first := true
	for p in polys:
		for k in 4:
			if p.v[k] < verts.size():
				box = AABB(verts[p.v[k]], Vector3.ZERO) if first else box.expand(verts[p.v[k]])
				first = false
	return box


## The chase camera must not end up inside a building and show its back faces. Large
## solid objects (buildings, walls, bridges) block the camera; foliage, glows and small
## props would only make it jump, so they are left out.
static func _camera_blockers(t: Nfs3Track) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CameraBlockers"
	body.collision_layer = CAMERA_LAYER
	body.collision_mask = 0
	var faces := PackedVector3Array()
	for b in t.blocks:
		for obj in b.objects:
			_solid_faces(t, obj, b.verts, Vector3.ZERO, faces, true)
		for x in b.xobjs:
			if not x.has("anim"):
				_solid_faces(t, x.polys, x.verts, x.ref, faces, true)
	for o in t.col_objects:
		_solid_faces(t, o.polys, o.verts, o.ref, faces, true)
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


## Appends the triangles of an object's opaque polys; with `large_only`, only when the
## object is big enough to block the camera.
static func _solid_faces(t: Nfs3Track, polys: Array, verts: PackedVector3Array, offset: Vector3,
		out: PackedVector3Array, large_only: bool) -> void:
	var tris := PackedVector3Array()
	var box := AABB()
	for p in polys:
		if p.tex >= t.textures.size():
			continue
		var ti: Nfs3Track.TexInfo = t.textures[p.tex]
		if ti.is_lane or ti.additive or ti.cutout or _is_water(t, p, verts):
			continue
		if p.v[0] >= verts.size() or p.v[1] >= verts.size() or p.v[2] >= verts.size() or p.v[3] >= verts.size():
			continue
		for k in Nfs3Track.QUAD:
			var v: Vector3 = verts[p.v[k]] + offset
			box = AABB(v, Vector3.ZERO) if tris.is_empty() else box.expand(v)
			tris.append(v)
	if tris.is_empty():
		return
	if not large_only or (maxf(box.size.x, box.size.z) >= 6.0 and box.size.y >= 2.5):
		out.append_array(tris)


## Whether extra object `x` stores its quads mirrored (see _mesh): the FRD's do, those from
## the .col file (see Nfs3Track._parse_col) and High Stakes' (see Nfs4Track) don't.
static func _mirrored(x: Dictionary) -> bool:
	return not x.get("unmirrored", false)


## One mesh from [polys, verts, shading, offset, mirrored, (road flags)] groups, keeping only
## the polys whose texture is (or isn't) additive. Null when nothing matched. Vertex colour
## alpha is 1 on drivable road polys (a group with road flags), 0 elsewhere; in the
## additive pass it is 1 on sunlight (SUNLIGHT_TEXTURES) instead.
## Extra objects (xobjs) store their quads mirrored (corners 0<->1, 2<->3) relative to the
## texture corners: read as-is, the half-tree quads of a split tree show their trunk on the
## outside and the front/back quads of a sign face the wrong way.
static func _mesh(t: Nfs3Track, groups: Array, additive: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var twins := _twin_polys(groups)
	var n := 0
	for g in groups:
		n += _add_polys(st, t, g[0], g[1], g[2], g[3], g[4], additive, twins, g[5] if g.size() > 5 else null)
	return st.commit() if n > 0 else null


static func _add_polys(st: SurfaceTool, t: Nfs3Track, polys: Array, verts: PackedVector3Array,
		shading: PackedColorArray, offset: Vector3, mirrored: bool, additive: bool, twins: Dictionary,
		road_flags: Variant = null) -> int:
	var order: Array = [1, 0, 3, 2] if mirrored else [0, 1, 2, 3]
	var sunlight: Array = SUNLIGHT_TEXTURES.get(t.name, [])
	var n := 0
	for pi in polys.size():
		var p: Nfs3Track.Poly = polys[pi]
		if p.tex >= t.textures.size():
			continue
		var ti: Nfs3Track.TexInfo = t.textures[p.tex]
		if ti.additive != additive or ti.qfs_index >= t.images.size():
			continue
		var bad := false
		for k in 4:
			if p.v[k] >= verts.size():
				bad = true
		if bad:
			continue
		var a := verts[p.v[order[0]]]
		var normal := (verts[p.v[order[2]]] - a).cross(verts[p.v[order[1]]] - a).normalized()
		var one_sided := 1.0 if twins.has(p) else 0.0
		# UV2.y = one_sided + 2 * frames + 16 * period: the shaders flip through `frames`
		# consecutive texture layers.
		var frames := _anim_frames(t, p)
		var anim: float = 2.0 * frames + 16.0 * p.anim_period if frames > 1 else 0.0
		var road := 0.0
		if additive:
			road = 1.0 if p.tex in sunlight else 0.0
		elif road_flags != null and (pi >= road_flags.size() or Nfs3Track.drivable(road_flags[pi])):
			road = 1.0
		for k in Nfs3Track.QUAD:
			var vi: int = p.v[order[k]]
			var c: Color = shading[vi] if vi < shading.size() else Color.WHITE
			c.a = road
			st.set_color(c)
			st.set_uv(ti.uv[k])
			st.set_uv2(Vector2(ti.qfs_index, one_sided + anim))
			st.set_normal(normal)
			st.add_vertex(verts[vi] + offset)
		n += 2
	return n


## How many frames of a poly's animated texture can be drawn: the frames must sit in
## consecutive texture layers (they do in every stock track), else the poly stays still.
static func _anim_frames(t: Nfs3Track, p: Nfs3Track.Poly) -> int:
	if p.anim_frames < 2:
		return 0
	var base: int = t.textures[p.tex].qfs_index
	for f in range(1, p.anim_frames):
		if p.tex + f >= t.textures.size() or t.textures[p.tex + f].qfs_index != base + f \
				or base + f >= t.images.size():
			return f if f > 1 else 0
	return p.anim_frames


## Polys that share their corners with an opposite-facing poly of the mesh: road signs and
## billboards are a front quad plus a back quad over the same four points, sometimes split
## across two objects (the Redrock Ridge motel sign). Drawn double-sided they z-fight or
## show the far quad's mirrored back, so these get their back faces culled in the shader.
static func _twin_polys(groups: Array) -> Dictionary:
	var by_corners := {}
	for g in groups:
		var verts: PackedVector3Array = g[1]
		var order: Array = [1, 0, 3, 2] if g[4] else [0, 1, 2, 3]
		for p in g[0]:
			if p.v[0] >= verts.size() or p.v[1] >= verts.size() or p.v[2] >= verts.size() or p.v[3] >= verts.size():
				continue
			var corners := []
			for k in 4:
				var v: Vector3 = ((verts[p.v[k]] + g[3]) * 100.0).round()
				corners.append("%d,%d,%d" % [v.x, v.y, v.z])
			corners.sort()
			var key := ";".join(corners)
			if not by_corners.has(key):
				by_corners[key] = []
			var a := verts[p.v[order[0]]]
			by_corners[key].append([p, (verts[p.v[order[2]]] - a).cross(verts[p.v[order[1]]] - a).normalized()])
	var out := {}
	for group: Array in by_corners.values():
		for i in group.size():
			for j in range(i + 1, group.size()):
				if group[i][1].dot(group[j][1]) < -0.9:
					out[group[i][0]] = true
					out[group[j][0]] = true
	return out


static func _texture_array(t: Nfs3Track) -> Texture2DArray:
	var layers: Array[Image] = []
	for img in t.images:
		var im: Image = img.duplicate()
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		_bleed_alpha(im)
		im.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_BILINEAR)
		im.generate_mipmaps()
		layers.append(im)
	if layers.is_empty():
		var blank := Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
		blank.fill(Color.GRAY)
		layers.append(blank)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	return arr


## Fill the colour of fully transparent texels from opaque neighbours so that
## filtering doesn't produce dark fringes around foliage.
static func _bleed_alpha(im: Image) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var avg := Color(0, 0, 0, 0)
	var cnt := 0
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if c.a > 0.5:
				avg += c
				cnt += 1
	if cnt == 0 or cnt == w * h:
		return
	avg /= cnt
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if c.a <= 0.5:
				im.set_pixel(x, y, Color(avg.r, avg.g, avg.b, 0.0))


static func _make_path(t: Nfs3Track) -> TrackPath:
	var path := TrackPath.new()
	for vr in t.vroad:
		path.points.append(vr.pos)
		# Mirroring X is a change of basis, so the converted "right" still points to the
		# driver's right (it equals forward x normal in Godot space).
		path.rights.append(vr.right.normalized())
		path.ups.append(vr.normal.normalized() if vr.normal.length() > 0.1 else Vector3.UP)
		path.left_width.append(vr.left_wall)
		path.right_width.append(vr.right_wall)
	path.finalize()
	return path


## The drivable road polys as [quads (PackedVector3Array each), grid of _edge_cell ->
## quad indices], for _road_near and _height_in_quad.
static func _drivable_quads(t: Nfs3Track) -> Array:
	var quads: Array = []
	for b in t.blocks:
		for i in b.road.size():
			if i < b.road_flags.size() and not Nfs3Track.drivable(b.road_flags[i]):
				continue
			var p: Nfs3Track.Poly = b.road[i]
			if p.v[0] >= b.verts.size() or p.v[1] >= b.verts.size() or p.v[2] >= b.verts.size() or p.v[3] >= b.verts.size():
				continue
			quads.append(PackedVector3Array([b.verts[p.v[0]], b.verts[p.v[1]], b.verts[p.v[2]], b.verts[p.v[3]]]))
	return [quads, _quad_grid(quads)]


## The water surfaces (see _is_water) as [quads, grid], like _drivable_quads.
static func _water_quads(t: Nfs3Track) -> Array:
	var quads: Array = []
	var groups := []
	for b in t.blocks:
		for obj in b.objects:
			groups.append([obj, b.verts, Vector3.ZERO])
		for x in b.xobjs:
			if not x.has("anim"):
				groups.append([x.polys, x.verts, x.ref])
	for o in t.col_objects:
		groups.append([o.polys, o.verts, o.ref])
	for g in groups:
		var verts: PackedVector3Array = g[1]
		for p: Nfs3Track.Poly in g[0]:
			if _is_water(t, p, verts):
				var off: Vector3 = g[2]
				quads.append(PackedVector3Array([verts[p.v[0]] + off, verts[p.v[1]] + off, verts[p.v[2]] + off, verts[p.v[3]] + off]))
	return [quads, _quad_grid(quads)]


## Streams and lakes are scenery quads, flat, with an animated texture that isn't blended
## additively (that is fire). There is no ocean to find: Atlantica's and Aquatica's sea is
## the horizon panorama.
static func _is_water(t: Nfs3Track, p: Nfs3Track.Poly, verts: PackedVector3Array) -> bool:
	if p.anim_frames <= 1 or p.tex >= t.textures.size() or t.textures[p.tex].additive:
		return false
	if p.v[0] >= verts.size() or p.v[1] >= verts.size() or p.v[2] >= verts.size() or p.v[3] >= verts.size():
		return false
	var n := (verts[p.v[1]] - verts[p.v[0]]).cross(verts[p.v[2]] - verts[p.v[0]])
	return n.length() > 1e-4 and absf(n.normalized().y) > 0.85


## Grid of _edge_cell -> indices of the quads over that cell.
static func _quad_grid(quads: Array) -> Dictionary:
	var grid := {}
	for qi in quads.size():
		var q: PackedVector3Array = quads[qi]
		var lo := _edge_cell(q[0])
		var hi := lo
		for v in q:
			var c := _edge_cell(v)
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				if not grid.has(Vector2i(x, z)):
					grid[Vector2i(x, z)] = []
				grid[Vector2i(x, z)].append(qi)
	return grid


## Invisible walls along the edge of the drivable surface, the way NFS3 fences you in. The
## virtual road's wall distances can't simply be joined into two lines: where the road
## splits around an island (the Lost Canyons temple) or bends tighter than the wall is wide,
## those lines cut across drivable ground and close off shortcuts. Where the edge faces a
## stream or a lake (`water`, from _water_quads) it stays open: the car can go in.
static func _edge_walls(t: Nfs3Track, drivable: Array, water := [[], {}]) -> StaticBody3D:
	var quads: Array = drivable[0]
	var quad_grid: Dictionary = drivable[1]
	# Drivable poly edges, by welded corner ids (blocks don't share vertices); an edge used
	# by one poly only is on the boundary.
	var ids := {}
	var edges := {}   # Vector2i(id, id) -> [a, b, uses]
	for q: PackedVector3Array in quads:
		for k in 4:
			var ia: int = ids.get_or_add(Vector3i((q[k] * 10.0).round()), ids.size())
			var ib: int = ids.get_or_add(Vector3i((q[(k + 1) % 4] * 10.0).round()), ids.size())
			if ia == ib:
				continue
			var e := Vector2i(mini(ia, ib), maxi(ia, ib))
			if edges.has(e):
				edges[e][2] += 1
			else:
				edges[e] = [q[k], q[(k + 1) % 4], 1]

	var walled: Array[Vector2i] = []
	var drops := {}   # edge -> true: where the surface ends in a drop onto the road below
	var open := {}    # edge -> true: left without a wall
	for key: Vector2i in edges:
		var e: Array = edges[key]
		if e[2] != 1:
			continue
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var m := (a + b) * 0.5
		var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * 0.75
		# Road on both sides: a seam inside the road, not its edge (a T-junction where one
		# block's long edge meets two short ones of the next, corners that don't quite weld,
		# the odd bow-tie quad).
		if side == Vector3.ZERO or (_road_near(quads, quad_grid, m + side, 1.5) and _road_near(quads, quad_grid, m - side, 1.5)):
			continue
		walled.append(key)
		var out := -side if _road_near(quads, quad_grid, m + side, 1.5) else side
		if _drop_off(quads, quad_grid, m, out):
			drops[key] = true
		if _faces_water(quads, quad_grid, water, m, out):
			open[key] = true
	# The end of a ledge that drops onto the road below (the Redrock Ridge skeleton path,
	# the Empire City rooftops): the car should fall off it, not hit a wall. A drop along
	# the side of a raised road, longer than a road is wide, keeps its wall.
	for run in _runs(drops.keys()):
		var length := 0.0
		for key: Vector2i in run:
			var ab: Vector3 = edges[key][1] - edges[key][0]
			length += Vector2(ab.x, ab.z).length()
		if length <= LEDGE_END_MAX:
			for key: Vector2i in run:
				open[key] = true

	var faces := PackedVector3Array()
	for key in walled:
		if open.has(key):
			continue
		var a: Vector3 = edges[key][0]
		var b: Vector3 = edges[key][1]
		# Short of any other road above or below (bridges, overpasses, tunnels).
		var down := WALL_DEPTH
		var up := WALL_HEIGHT
		for f: float in [0.1, 0.5, 0.9]:
			var p := a.lerp(b, f)
			for qi: int in quad_grid.get(_edge_cell(p), []):
				var dy := _height_in_quad(quads[qi], p) - p.y
				if dy > 3.0:
					up = minf(up, dy - 0.5)
				elif dy < -3.0:
					down = minf(down, -dy - 2.5)
		faces.append_array([a + Vector3.DOWN * down, b + Vector3.DOWN * down, b + Vector3.UP * up,
			a + Vector3.DOWN * down, b + Vector3.UP * up, a + Vector3.UP * up])
	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


## Whether the road edge at `m`, facing `out`, looks out over a stream or a lake within
## WATER_REACH, below the road and with no other road in between. Not a bridge's side:
## there the water runs under the road too.
static func _faces_water(quads: Array, quad_grid: Dictionary, water: Array, m: Vector3, out: Vector3) -> bool:
	var dir := out.normalized()
	if _water_height(water, m - dir * 1.5) > -INF:
		return false
	var d := 2.0
	while d <= WATER_REACH:
		var p := m + dir * d
		if _road_near(quads, quad_grid, p, 3.0):
			return false
		var h := _water_height(water, p)
		if h > -INF and h < m.y + 0.5:
			# Not where the stream passes under the road (a median island over a culvert).
			for e: float in [2.0, 4.0, 6.0, 8.0]:
				if _road_near(quads, quad_grid, p + dir * e, 3.0):
					return false
			return true
		d += 2.0
	return false


## Height of the water surface over `p` (from _water_quads), or -INF where there is none.
static func _water_height(water: Array, p: Vector3) -> float:
	var h := -INF
	for qi: int in water[1].get(_edge_cell(p), []):
		var y := _height_in_quad(water[0][qi], p)
		if not is_nan(y):
			h = maxf(h, y)
	return h


## The water surfaces as a body on WATER_LAYER, in the "water" group: cars pass through
## it (they don't collide with the layer), the race casts rays against it.
static func _water_body(quads: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Water"
	body.collision_layer = WATER_LAYER
	body.collision_mask = 0
	body.add_to_group("water")
	var faces := PackedVector3Array()
	for q: PackedVector3Array in quads:
		faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


## Edges (Vector2i of corner ids) grouped into runs that share corners.
static func _runs(keys: Array) -> Array:
	var by_corner := {}
	for key: Vector2i in keys:
		for c in [key.x, key.y]:
			if not by_corner.has(c):
				by_corner[c] = []
			by_corner[c].append(key)
	var runs := []
	var seen := {}
	for key: Vector2i in keys:
		if seen.has(key):
			continue
		var run: Array[Vector2i] = []
		var todo: Array[Vector2i] = [key]
		seen[key] = true
		while not todo.is_empty():
			var k: Vector2i = todo.pop_back()
			run.append(k)
			for c in [k.x, k.y]:
				for n: Vector2i in by_corner[c]:
					if not seen.has(n):
						seen[n] = true
						todo.append(n)
		runs.append(run)
	return runs


## Whether the road edge at `m`, facing `out`, is where the drivable surface ends in a
## sheer drop onto more road: road right below beyond it (a cliff road above a lower one
## has a slope or a verge between them, and keeps its wall) but none below short of it (a
## bridge's side has the road it crosses on both sides).
static func _drop_off(quads: Array, quad_grid: Dictionary, m: Vector3, out: Vector3) -> bool:
	var dir := out.normalized()
	return _road_below(quads, quad_grid, m + dir) and not _road_below(quads, quad_grid, m - dir * 1.5)


## Whether there is drivable surface more than 3 m under `p`.
static func _road_below(quads: Array, quad_grid: Dictionary, p: Vector3) -> bool:
	for qi: int in quad_grid.get(_edge_cell(p), []):
		if _height_in_quad(quads[qi], p) - p.y < -3.0:
			return true
	return false


## Whether there is drivable surface under `p` within `reach` metres of its height.
static func _road_near(quads: Array, quad_grid: Dictionary, p: Vector3, reach: float) -> bool:
	for qi: int in quad_grid.get(_edge_cell(p), []):
		if absf(_height_in_quad(quads[qi], p) - p.y) < reach:
			return true
	return false


## Height of the quad's surface above `p` (ground-plane test), or NAN when `p` is outside it.
static func _height_in_quad(q: PackedVector3Array, p: Vector3) -> float:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a := q[tri[0]]
		var b := q[tri[1]]
		var c := q[tri[2]]
		var bc := _barycentric(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		if bc.x >= -0.001 and bc.y >= -0.001 and bc.z >= -0.001:
			return a.y * bc.x + b.y * bc.y + c.y * bc.z
	return NAN


static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-6:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


const _EDGE_CELL := 8.0


static func _edge_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / _EDGE_CELL), floori(p.z / _EDGE_CELL))


## Invisible walls along both sides of the path (the procedural track's fence).
static func make_walls(path: TrackPath) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	var n := path.size()
	var grid := _path_grid(path)
	for side: float in [-1.0, 1.0]:
		var foot := PackedVector3Array()
		var extent := PackedVector2Array()   # (down, up) per node
		for i in n:
			var w: float = path.right_width[i] if side > 0 else path.left_width[i]
			var p: Vector3 = path.points[i] + path.rights[i] * w * side
			foot.append(p)
			extent.append(_wall_extent(path, grid, i, p))
		var faces := PackedVector3Array()
		for i in n:
			var j := (i + 1) % n
			var a := foot[i]
			var b := foot[j]
			faces.append_array([a + Vector3.DOWN * extent[i].x, b + Vector3.DOWN * extent[j].x, b + Vector3.UP * extent[j].y,
				a + Vector3.DOWN * extent[i].x, b + Vector3.UP * extent[j].y, a + Vector3.UP * extent[i].y])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


const _GRID_CELL := 40.0


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / _GRID_CELL), floori(p.z / _GRID_CELL))


## Path nodes bucketed by ground-plane cell, for finding where the track crosses itself.
static func _path_grid(path: TrackPath) -> Dictionary:
	var grid := {}
	for i in path.size():
		var c := _cell(path.points[i])
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		grid[c].append(i)
	return grid


## How far a wall post at `p` (belonging to node `i`) may reach down and up. Where another
## stretch of the track passes over or under (bridges, overpasses) the wall is cut short so
## it doesn't poke through that road.
static func _wall_extent(path: TrackPath, grid: Dictionary, i: int, p: Vector3) -> Vector2:
	var down := WALL_DEPTH
	var up := WALL_HEIGHT
	var n := path.size()
	var c := _cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for k: int in grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var gap := absi(k - i)
				if mini(gap, n - gap) < 20:
					continue
				var q := path.points[k]
				var reach := maxf(path.left_width[k], path.right_width[k]) + 2.0
				if Vector2(q.x - p.x, q.z - p.z).length() > reach:
					continue
				# Only a separate level counts (a car fits in between); side-by-side
				# stretches such as hairpins keep their full walls.
				var dy := q.y - p.y
				if dy > 3.0:
					up = minf(up, dy - 0.5)
				elif dy < -3.0:
					down = minf(down, -dy - 2.5)
	return Vector2(down, up)

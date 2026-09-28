class_name Nfs3TrackBuilder
## Turns parsed Nfs3Track data into a scene: one mesh per track block (with a
## visibility range, like the original's draw distance), road collision and
## invisible side walls from the virtual road.

const TEX_SIZE := 256
const DRAW_DISTANCE := 700.0
const WALL_HEIGHT := 6.0
const WALL_DEPTH := 3.0
## Physics layer of the solid scenery that only the chase camera collides with.
const CAMERA_LAYER := 8
## Physics layer of solid scenery (buildings, signs, posts, rocks) that cars hit. Kept off
## layer 1 so the chase camera ignores small props.
const SCENERY_LAYER := 4
## Extra objects no wider than this (m) and within this height range are road signs and
## posts that cars knock over; taller poles and anything bigger stay put.
const PROP_MAX_WIDTH := 3.5
const PROP_HEIGHT := Vector2(1.5, 7.0)
## Height (m) above a prop's foot that a car body can touch.
const PROP_REACH := 1.5

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

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	for bi in t.blocks.size():
		var b: Nfs3Track.Block = t.blocks[bi]
		var groups := [[b.road, b.verts, b.shading, Vector3.ZERO, false], [b.lanes, b.verts, b.shading, Vector3.ZERO, false]]
		for obj in b.objects:
			groups.append([obj, b.verts, b.shading, Vector3.ZERO, false])
		for x in b.xobjs:
			if x.has("anim"):
				continue
			if _is_prop(t, x):
				props.add_child(_make_prop(t, x, mats[0]))
			else:
				groups.append([x.polys, x.verts, x.shading, x.ref, true])
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
			geo.add_child(mi)

		# Collision: the drivable surface only (terrain + road of the block).
		var faces := PackedVector3Array()
		for p in b.road:
			if p.v[0] >= b.verts.size() or p.v[1] >= b.verts.size() or p.v[2] >= b.verts.size() or p.v[3] >= b.verts.size():
				continue
			for k in Nfs3Track.QUAD:
				faces.append(b.verts[p.v[k]])
		if faces.size() > 0:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)

		# Animated extra objects (planes, boats, ...): keyframed along the track.
		for x in b.xobjs:
			if not x.has("anim") or x.anim.size() == 0:
				continue
			for pass_i in 2:
				var amesh := _mesh(t, [[x.polys, x.verts, x.shading, Vector3.ZERO, true]], pass_i == 1)
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

	root.add_child(_scenery_body(t))
	root.add_child(_camera_blockers(t))
	var path := _make_path(t)
	root.add_child(make_walls(path))
	return path


## Cars collide with every opaque scenery object: buildings, bridge piers and road signs
## stand inside the virtual road's walls. The track files carry no per-object collision
## flag, so foliage and other cut-out billboards, glows and lane markings stay passable.
static func _scenery_body(t: Nfs3Track) -> StaticBody3D:
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
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


## Sign-sized extra objects drawn only with opaque textures (foliage cut-outs are left
## standing: the car passes through them anyway).
static func _is_prop(t: Nfs3Track, x: Dictionary) -> bool:
	if not x.has("prop"):
		x.prop = false
		var box := _poly_box(x.polys, x.verts)
		if box.size != Vector3.ZERO and maxf(box.size.x, box.size.z) <= PROP_MAX_WIDTH \
				and box.size.y >= PROP_HEIGHT.x and box.size.y <= PROP_HEIGHT.y:
			x.prop = true
			for p in x.polys:
				if p.tex >= t.textures.size():
					continue
				var ti: Nfs3Track.TexInfo = t.textures[p.tex]
				if ti.cutout or ti.additive or ti.is_lane:
					x.prop = false
					break
	return x.prop


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
	prop.setup(_mesh(t, [[x.polys, x.verts, x.shading, -foot, true]], false), material,
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
		if ti.is_lane or ti.additive or ti.cutout:
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


## One mesh from [polys, verts, shading, offset, mirrored] groups, keeping only the polys
## whose texture is (or isn't) additive. Null when nothing matched.
## Extra objects (xobjs) store their quads mirrored (corners 0<->1, 2<->3) relative to the
## texture corners: read as-is, the half-tree quads of a split tree show their trunk on the
## outside and the front/back quads of a sign face the wrong way.
static func _mesh(t: Nfs3Track, groups: Array, additive: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var twins := _twin_polys(groups)
	var n := 0
	for g in groups:
		n += _add_polys(st, t, g[0], g[1], g[2], g[3], g[4], additive, twins)
	return st.commit() if n > 0 else null


static func _add_polys(st: SurfaceTool, t: Nfs3Track, polys: Array, verts: PackedVector3Array,
		shading: PackedColorArray, offset: Vector3, mirrored: bool, additive: bool, twins: Dictionary) -> int:
	var order: Array = [1, 0, 3, 2] if mirrored else [0, 1, 2, 3]
	var n := 0
	for p in polys:
		if p.tex >= t.textures.size():
			continue
		var ti: Nfs3Track.TexInfo = t.textures[p.tex]
		if ti.is_lane or ti.additive != additive or ti.qfs_index >= t.images.size():
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
		for k in Nfs3Track.QUAD:
			var vi: int = p.v[order[k]]
			st.set_color(shading[vi] if vi < shading.size() else Color.WHITE)
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


## Invisible walls along both sides of the path (the way NFS3 fences you in).
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

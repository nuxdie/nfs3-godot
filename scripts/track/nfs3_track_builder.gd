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

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	for bi in t.blocks.size():
		var b: Nfs3Track.Block = t.blocks[bi]
		var groups := [[b.road, b.verts, b.shading, Vector3.ZERO], [b.lanes, b.verts, b.shading, Vector3.ZERO]]
		for obj in b.objects:
			groups.append([obj, b.verts, b.shading, Vector3.ZERO])
		for x in b.xobjs:
			if not x.has("anim"):
				groups.append([x.polys, x.verts, x.shading, x.ref])
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
				var amesh := _mesh(t, [[x.polys, x.verts, x.shading, Vector3.ZERO]], pass_i == 1)
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
		global_groups.append([o.polys, o.verts, o.shading, o.ref])
	for pass_i in 2:
		var gmesh := _mesh(t, global_groups, pass_i == 1)
		if gmesh == null:
			continue
		var gmi := MeshInstance3D.new()
		gmi.name = "GlobalObjects%s" % ("Fx" if pass_i == 1 else "")
		gmi.mesh = gmesh
		gmi.material_override = mats[pass_i]
		geo.add_child(gmi)

	root.add_child(_camera_blockers(t))
	var path := _make_path(t)
	root.add_child(make_walls(path))
	return path


## Cars drive through roadside scenery (NFS3 fences them in with the virtual road's walls
## instead), but the chase camera must not end up inside a building and show its back
## faces. Large solid objects (buildings, walls, bridges) block the camera; foliage, glows
## and small props would only make it jump, so they are left out.
static func _camera_blockers(t: Nfs3Track) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CameraBlockers"
	body.collision_layer = CAMERA_LAYER
	body.collision_mask = 0
	var faces := PackedVector3Array()
	for b in t.blocks:
		for obj in b.objects:
			_blocker_faces(t, obj, b.verts, Vector3.ZERO, faces)
		for x in b.xobjs:
			if not x.has("anim"):
				_blocker_faces(t, x.polys, x.verts, x.ref, faces)
	for o in t.col_objects:
		_blocker_faces(t, o.polys, o.verts, o.ref, faces)
	if faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


static func _blocker_faces(t: Nfs3Track, polys: Array, verts: PackedVector3Array, offset: Vector3,
		out: PackedVector3Array) -> void:
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
	if maxf(box.size.x, box.size.z) >= 6.0 and box.size.y >= 2.5:
		out.append_array(tris)


## One mesh from [polys, verts, shading, offset] groups, keeping only the polys whose
## texture is (or isn't) additive. Null when nothing matched.
static func _mesh(t: Nfs3Track, groups: Array, additive: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for g in groups:
		n += _add_polys(st, t, g[0], g[1], g[2], g[3], additive)
	return st.commit() if n > 0 else null


static func _add_polys(st: SurfaceTool, t: Nfs3Track, polys: Array, verts: PackedVector3Array,
		shading: PackedColorArray, offset: Vector3, additive: bool) -> int:
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
		var a := verts[p.v[0]]
		var normal := (verts[p.v[2]] - a).cross(verts[p.v[1]] - a).normalized()
		for k in Nfs3Track.QUAD:
			var vi: int = p.v[k]
			st.set_color(shading[vi] if vi < shading.size() else Color.WHITE)
			st.set_uv(ti.uv[k])
			st.set_uv2(Vector2(ti.qfs_index, 0))
			st.set_normal(normal)
			st.add_vertex(verts[vi] + offset)
		n += 2
	return n


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

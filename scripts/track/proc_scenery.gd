class_name ProcScenery
extends RefCounted
## What stands along the procedural track, stretch by stretch: shops, houses and street
## lamps in town; fields, barns, silos, fences and telephone lines on the farms; forest,
## guardrails, chevrons and bend warnings through the hills and the mountain pass; rocks on
## the cuttings; lamps over the bridges; the start/finish gantry. Plus forest over the land
## beyond, thinning out up the mountains. The named places and every sign that names or
## points to one are ProcPlaces'; they are laid out first, and the rest keeps off them.
##
## Everything is low-poly and drawn through MultiMeshes bucketed by CELL-sized squares, so
## each bucket is culled on its own and far ones drop out. There are no invisible walls, so
## what a car could reach is solid: rails, buildings, poles, lamp posts, rocks and tree trunks
## (crops, bushes and the backdrop forest stay passable). Signs, chevrons, cones, sawhorses and
## fence panels are knocked flying by a car that hits them (Breakables), and the guardrails
## bend where they're hit (Guardrails), as on the NFS3 tracks.

const Kind := ProceduralTrack.Kind
const Zone := ProceduralTrack.Zone
const CELL := 160.0

var lay: ProceduralTrack.Layout
var root: Node3D
var rng := RandomNumberGenerator.new()
var _batches := {}    # "kind|cx|cz" -> {kind, xforms: Array[Transform3D], colors: PackedColorArray}
var _meshes := {}     # kind -> {mesh, range, shadow}
var _veg: StandardMaterial3D
var _paint: StandardMaterial3D
var _density := 1.0   # of the forests, by quality preset
var _pools: Array[Transform3D] = []   # under the street lamps
var _body: StaticBody3D
var _solid_shapes := {}   # kind -> [Shape3D, offset up the instance's local Y (m)]
var _faces := PackedVector3Array()   # rails and fences
var _keep := {}       # Vector2i cell -> Array of Vector3(x, z, radius): ground a place took
const KEEP_CELL := 50.0
var no_fence := {}    # node * 2 + (1 on the right): a driveway or lot along the road
var places: ProcPlaces
var signs: ProcSigns
var breakables: Breakables
var _mm_of := {}      # batch key -> its MultiMesh, once flushed
var parked := []     # where the places leave a car parked (see ParkedCars)
var _knock := []      # props to knock over, registered once flushed: [frame, reach, puts, node]
var plain_mat: Material


static func build(p_root: Node3D, p_lay: ProceduralTrack.Layout, seed_value: int) -> void:
	var s := ProcScenery.new()
	s.root = p_root
	s.lay = p_lay
	s.rng.seed = seed_value * 31 + 5
	s._density = [0.45, 0.75, 1.0][clampi(Game.quality, 0, 2)]
	s._make_meshes()
	s._make_shapes()
	s.breakables = Breakables.new()
	s.breakables.name = "Breakables"
	p_root.add_child(s.breakables)
	s.places = ProcPlaces.build(s, seed_value)
	s.signs = ProcSigns.build(s, s.places, seed_value)
	s._town()
	s._gantry()
	s._farms()
	s._rails()
	s._fences()
	s._poles()
	s._bend_signs()
	s.places.billboards()
	s.signs.flush(p_root)
	s.places = null   # they refer to each other: let both go
	s.signs = null
	s._bridge_lamps()
	s._rocks()
	s._roadside_trees()
	s._forests()
	s._flush()
	s._register_knockables()
	# The race parks real cars there (ParkedCars).
	p_root.set_meta("parking", s.parked)
	s._light_pools()
	if not s._faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(s._faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		s._body.add_child(cs)


# --- Placement helpers -----------------------------------------------------------------------

## Draws a `kind` at `xf`: returns [batch key, its index there, kind, xf] (see knockable()).
func _put(kind: String, xf: Transform3D, color := Color.WHITE) -> Array:
	var key := "%s|%d|%d" % [kind, floori(xf.origin.x / CELL), floori(xf.origin.z / CELL)]
	if not _batches.has(key):
		_batches[key] = {"kind": kind, "xforms": [], "colors": PackedColorArray()}
	_batches[key].xforms.append(xf)
	_batches[key].colors.append(color)
	var out := [key, _batches[key].xforms.size() - 1, kind, xf]
	if _solid_shapes.has(kind):
		var sh: Array = _solid_shapes[kind]
		# Unscaled, turned with the instance, stood on its foot.
		var b := xf.basis.orthonormalized()
		var o := _body.create_shape_owner(_body)
		_body.shape_owner_add_shape(o, sh[0])
		_body.shape_owner_set_transform(o, Transform3D(b, xf.origin + b.y * sh[1] * xf.basis.get_scale().y))
	return out


## A prop a car knocks flying: the instances `puts` (from _put) and/or `node` (whose meshes and
## lettering fly off as they are), standing at `xf` (its foot), touched within `reach` (in its
## frame).
func knockable(xf: Transform3D, reach: AABB, puts: Array = [], node: Node3D = null) -> void:
	_knock.append([xf, reach, puts, node])


func _register_knockables() -> void:
	for k: Array in _knock:
		var xf: Transform3D = k[0]
		var puts: Array = k[2]
		var node: Node3D = k[3]
		var piece: Array = k.slice(4)   # [fence chunk, first vertex], for a fence panel
		breakables.add(xf, k[1], func() -> Variant:
			var parts := []
			if not piece.is_empty():
				parts.append([Breakables.take_piece(piece[0], piece[1], 18, xf), Transform3D()])
			for p: Array in puts:
				var mm: MultiMesh = _mm_of[p[0]]
				Breakables.take_instance(mm, p[1])
				parts.append([_meshes[p[2]].mesh, xf.affine_inverse() * (p[3] as Transform3D)])
			if node == null:
				return [Breakables.combine(parts), null]
			for part: Array in parts:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				mi.transform = node.global_transform.affine_inverse() * xf * (part[1] as Transform3D)
				node.add_child(mi)
			return node)
	_knock.clear()


func _make_shapes() -> void:
	_body = ProcGround.scenery_body(root)
	var box := func(size: Vector3) -> BoxShape3D:
		var b := BoxShape3D.new()
		b.size = size
		return b
	var cyl := func(r: float, h: float) -> CylinderShape3D:
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = h
		return c
	var trunk: Shape3D = cyl.call(0.3, 4.0)
	_solid_shapes = {
		"shop": [box.call(Vector3(14, 5.0, 10)), 2.5],
		"block": [box.call(Vector3(12, 10.8, 12)), 5.4],
		"house": [box.call(Vector3(9, 5.2, 7.5)), 2.6],
		"barn": [box.call(Vector3(18, 8.0, 11)), 4.0],
		"diner": [box.call(Vector3(17, 4.6, 9)), 2.3],
		"motel": [box.call(Vector3(26, 4.0, 8)), 2.0],
		"kiosk": [box.call(Vector3(10, 4.2, 7)), 2.1],
		"cabin": [box.call(Vector3(6, 3.4, 5)), 1.7],
		"silo": [cyl.call(2.8, 14.0), 7.0],
		"pole": [cyl.call(0.15, 9.6), 4.8],
		"lamp_post": [cyl.call(0.13, 8.0), 4.0],
		"rock": [_sphere(1.0), 0.3],
		"conifer": [trunk, 2.0],
		"broadleaf": [trunk, 2.0],
		"poplar": [trunk, 2.0],
	}


static func _sphere(r: float) -> SphereShape3D:
	var sh := SphereShape3D.new()
	sh.radius = r
	return sh


## A solid strip from `a` to `b` (ground points), from a little below them to `h` up.
func _solid_strip(a: Vector3, b: Vector3, h: float) -> void:
	var d := Vector3.DOWN * 0.4
	var u := Vector3.UP * h
	_faces.append_array([a + d, b + d, b + u, a + d, b + u, a + u])


func _flush() -> void:
	for key: String in _batches:
		var b: Dictionary = _batches[key]
		var m: Dictionary = _meshes[b.kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m.mesh
		mm.instance_count = b.xforms.size()
		for k in b.xforms.size():
			mm.set_instance_transform(k, b.xforms[k])
			mm.set_instance_color(k, b.colors[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m.shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = m.range
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
		_mm_of[key] = mm


## Standing upright at `p` facing `facing` (its local +Z) on the ground plane.
static func _upright(p: Vector3, facing: Vector3, scale := Vector3.ONE) -> Transform3D:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	return Transform3D(Basis(Vector3.UP.cross(f) * scale.x, Vector3.UP * scale.y, f * scale.z), p)


## Ground point `d` m out to side `s` of node `i`, `along` m ahead of it.
func _beside(i: int, s: float, d: float, along := 0.0) -> Vector3:
	var p := lay.pts[i] + lay.flat_right[i] * s * d + lay.fwd[i] * along
	p.y = ProcGround.surface_y(lay, p.x, p.z)
	return p


## Whether a prop of radius `r` at `p` would stand clear of every stretch of road (outside
## its walls), above the water and on ground no steeper than `max_slope`.
func _clear(p: Vector3, r: float, max_slope := 0.8) -> bool:
	if p.y < lay.water + 0.5 or kept(p, r) or lay.on_branch(p.x, p.z, r):
		return false
	for i in lay.nearby(p.x, p.z):
		var v := Vector3(p.x - lay.pts[i].x, 0.0, p.z - lay.pts[i].z)
		if absf(v.dot(lay.fwd[i])) > ProceduralTrack.STEP:
			continue
		var lat := v.dot(lay.flat_right[i])
		var wall := lay.wall_r[i] if lat > 0.0 else lay.wall_l[i]
		if absf(lat) < wall + r + 1.0:
			return false
	if max_slope < 10.0:
		var hx := ProcGround.surface_y(lay, p.x + 1.5, p.z) - ProcGround.surface_y(lay, p.x - 1.5, p.z)
		var hz := ProcGround.surface_y(lay, p.x, p.z + 1.5) - ProcGround.surface_y(lay, p.x, p.z - 1.5)
		if Vector2(hx, hz).length() / 3.0 > max_slope:
			return false
	return true


## Keeps everything else `r` m round `p` off the ground (a place's building, lot or yard).
func keep_out(p: Vector3, r: float) -> void:
	# Registered in every cell a prop standing in the circle's reach could be in.
	var pad := r + 8.0
	for cx in range(floori((p.x - pad) / KEEP_CELL), floori((p.x + pad) / KEEP_CELL) + 1):
		for cz in range(floori((p.z - pad) / KEEP_CELL), floori((p.z + pad) / KEEP_CELL) + 1):
			var c := Vector2i(cx, cz)
			if not _keep.has(c):
				_keep[c] = []
			_keep[c].append(Vector3(p.x, p.z, r))


func kept(p: Vector3, r: float) -> bool:
	for k: Vector3 in _keep.get(Vector2i(floori(p.x / KEEP_CELL), floori(p.z / KEEP_CELL)), []):
		if Vector2(p.x - k.x, p.z - k.y).length() < k.z + r:
			return true
	return false


func _straight(i: int, span: int) -> bool:
	for k in range(-span, span + 1):
		if absf(lay.curv[lay.idx(i + k)]) > 1.0 / 400.0:
			return false
	return true


# --- Meshes ----------------------------------------------------------------------------------

func _make_meshes() -> void:
	_veg = StandardMaterial3D.new()
	_veg.vertex_color_use_as_albedo = true
	_veg.vertex_color_is_srgb = true
	_veg.albedo_texture = ProcGround.speckle(0.62)
	_veg.uv1_triplanar = true
	_veg.uv1_world_triplanar = true
	_veg.uv1_scale = Vector3.ONE * 0.9
	_veg.roughness = 0.95
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.vertex_color_is_srgb = true
	_paint.roughness = 0.7
	var metal := _paint.duplicate() as StandardMaterial3D
	metal.metallic = 0.55
	metal.roughness = 0.4
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wood := _paint.duplicate() as StandardMaterial3D
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.albedo_color = Color(1.0, 0.9, 0.65)

	var bark := Color(0.33, 0.24, 0.16)
	var leaf := Color(0.2, 0.35, 0.16)
	_mesh("conifer", _merge([
		[_cyl(0.12, 0.2, 1.6, 5), Vector3(0, 0.8, 0), bark],
		[_cyl(0.0, 2.3, 3.4, 7), Vector3(0, 2.9, 0), leaf],
		[_cyl(0.0, 1.75, 3.0, 7), Vector3(0, 4.6, 0), leaf],
		[_cyl(0.0, 1.1, 2.6, 6), Vector3(0, 6.3, 0), leaf]], _veg), 650.0, false)
	# Backdrop forest: the same shape with fewer faces.
	_mesh("conifer_far", _merge([
		[_cyl(0.0, 2.2, 4.8, 5), Vector3(0, 3.0, 0), leaf],
		[_cyl(0.0, 1.4, 3.6, 5), Vector3(0, 5.6, 0), leaf]], _veg), 900.0, false)
	var green := Color(0.29, 0.44, 0.17)
	_mesh("broadleaf", _merge([
		[_cyl(0.17, 0.27, 3.2, 5), Vector3(0, 1.6, 0), bark],
		[_ball(2.2, 3.6, 7, 4), Vector3(0, 4.4, 0), green],
		[_ball(1.6, 2.6, 6, 3), Vector3(1.3, 3.7, 0.4), green],
		[_ball(1.7, 2.8, 6, 3), Vector3(-1.1, 3.9, -0.6), green]], _veg), 650.0, false)
	_mesh("poplar", _merge([
		[_cyl(0.12, 0.2, 2.0, 5), Vector3(0, 1.0, 0), bark],
		[_ball(1.3, 7.5, 6, 5), Vector3(0, 5.2, 0), Color(0.26, 0.4, 0.15)]], _veg), 650.0, false)
	_mesh("bush", _merge([
		[_ball(1.2, 1.5, 6, 3), Vector3(0, 0.5, 0), green],
		[_ball(0.9, 1.2, 5, 3), Vector3(0.9, 0.4, 0.3), green]], _veg), 300.0, false)
	_mesh("rock", _rock_mesh(), 500.0, false)
	var grey := Color(0.72, 0.73, 0.75)
	_mesh("rail_post", _merge([[_box(Vector3(0.12, 1.0, 0.16)), Vector3(0, 0.3, 0), grey]], metal), 250.0, false)
	var white := Color(0.92, 0.91, 0.87)
	_mesh("fence_post", _merge([[_box(Vector3(0.14, 1.4, 0.14)), Vector3(0, 0.7, 0), white]], wood), 250.0, false)
	var pole_c := Color(0.32, 0.24, 0.17)
	_mesh("pole", _merge([
		[_cyl(0.1, 0.15, 9.6, 6), Vector3(0, 4.8, 0), pole_c],
		[_box(Vector3(2.4, 0.12, 0.12)), Vector3(0, 8.9, 0), pole_c]], wood), 700.0, true)
	var steel := Color(0.45, 0.47, 0.5)
	_mesh("lamp_post", _merge([
		[_cyl(0.08, 0.13, 8.0, 6), Vector3(0, 4.0, 0), steel],
		[_box(Vector3(0.1, 0.1, 2.3)), Vector3(0, 7.95, 1.1), steel]], _paint), 450.0, true)
	_mesh("lamp_head", _merge([[_box(Vector3(0.45, 0.16, 0.8)), Vector3(0, 7.85, 2.1), Color.WHITE]], lamp), 900.0, false)
	_mesh("sign_post", _merge([[_cyl(0.045, 0.045, 2.2, 5), Vector3(0, 1.1, 0), steel]], _paint), 300.0, false)
	_mesh("chevron", _board(Vector2(0.8, 1.0), 1.75, _sign_mat(_chevron_image())), 350.0, false)
	_mesh("curve_sign", _board(Vector2(1.0, 1.0), 2.0, _sign_mat(_curve_image()), true), 350.0, false)
	var orange := Color(0.98, 0.42, 0.05)
	_mesh("cone", _merge([[_cyl(0.035, 0.17, 0.62, 8), Vector3(0, 0.34, 0), orange],
		[_cyl(0.07, 0.11, 0.14, 8), Vector3(0, 0.38, 0), Color(0.95, 0.95, 0.95)],
		[_box(Vector3(0.42, 0.04, 0.42)), Vector3(0, 0.02, 0), orange]], _paint), 250.0, false)
	_buildings()


func _mesh(kind: String, mesh: Mesh, draw_range: float, shadow: bool) -> void:
	_meshes[kind] = {"mesh": mesh, "range": draw_range, "shadow": shadow}


static func _cyl(top: float, bottom: float, h: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 0
	m.cap_top = top > 0.0
	return m


static func _ball(r: float, h: float, segs: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = segs
	m.rings = rings
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## One mesh from primitives [mesh, offset, colour], coloured through its vertex colours.
static func _merge(parts: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		_append(st, part[0], Transform3D(Basis(), part[1]), part[2])
	st.set_material(mat)
	return st.commit()


static func _append(st: SurfaceTool, m: Mesh, xf: Transform3D, c: Color) -> void:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	for k in ix:
		st.set_color(c)
		st.set_normal((nb * nr[k]).normalized())
		st.set_uv(uv[k] if uv.size() > k else Vector2.ZERO)
		st.add_vertex(xf * v[k])


static func _rock_mesh() -> ArrayMesh:
	var base := _ball(1.0, 1.5, 7, 4)
	var arr := base.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	# Knock the ball into a boulder: every vertex pushed in or out by where it points.
	for k in v.size():
		var p := v[k]
		var bump := 1.0 + 0.22 * sin(p.x * 4.1 + p.z * 2.3) + 0.15 * sin(p.y * 5.7 - p.x * 3.1)
		v[k] = p * bump
	arr[Mesh.ARRAY_VERTEX] = v
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in ix:
		st.set_color(Color(0.6, 0.57, 0.52))
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v[k])
	st.generate_normals()   # faceted
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = ProcGround.speckle(0.55)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.7
	mat.roughness = 1.0
	st.set_material(mat)
	return st.commit()


## A sign board of `size` whose bottom edge stands `y` m up, facing +Z; `diamond` turns
## it 45 degrees.
static func _board(size: Vector2, y: float, mat: Material, diamond := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := QuadMesh.new()
	q.size = size
	var b := Basis()
	if diamond:
		b = Basis(Vector3.BACK, PI / 4.0)
	_append(st, q, Transform3D(b, Vector3(0, y + size.y * (0.7 if diamond else 0.5), 0.06)), Color.WHITE)
	st.set_material(mat)
	return st.commit()


static func _sign_mat(img: Image) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Retro-reflective: lit up by headlights at night more than paint would be.
	m.rim_enabled = true
	m.rim = 0.3
	return m


## Black chevrons pointing right on yellow.
static func _chevron_image() -> Image:
	var img := Image.create(64, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.78, 0.1))
	for y in 80:
		for x in 64:
			var yy := absf(y - 40.0)
			for c0: float in [8.0, 30.0]:
				var edge := c0 + yy * -0.55 + 22.0
				if x >= edge - 10.0 and x < edge:
					img.set_pixel(x, y, Color(0.05, 0.05, 0.05))
			if x < 3 or x > 60 or y < 3 or y > 76:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.05))
	return img


## A black arrow bending right, for a diamond sign.
static func _curve_image() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.78, 0.1))
	var black := Color(0.05, 0.05, 0.05)
	# The board is turned 45 degrees, so draw in its rotated frame.
	for y in 64:
		for x in 64:
			var u := (x - 32.0 + y - 32.0) * 0.7071
			var v := (y - 32.0 - (x - 32.0)) * 0.7071
			var border := absf(x - 32.0) > 28.0 or absf(y - 32.0) > 28.0
			var stem := absf(u + 2.0) < 3.0 and v > -4.0 and v < 16.0
			var bend := v > -8.0 and v < -2.0 and u > -5.0 and u < 8.0
			var head := u >= 6.0 and u < 15.0 and absf(v + 5.0) < 15.0 - u
			if border or stem or bend or head:
				img.set_pixel(x, y, black)
	return img


# --- Buildings -------------------------------------------------------------------------------

## Box buildings with window-bay walls (4 x 3.3 m a bay) and flat or pitched roofs.
func _buildings() -> void:
	var facade := _building_mat(_facade_texture(), Vector2.ONE, 0.4)
	var plain := _paint.duplicate() as StandardMaterial3D
	plain.albedo_texture = ProcGround.speckle(0.8)
	plain.uv1_triplanar = true
	plain.uv1_world_triplanar = true
	plain.uv1_scale = Vector3.ONE * 0.5
	var store := _building_mat(_storefront_texture(), Vector2(2, 1), 0.75)
	# Shops under two floors of flats.
	var above := Image.create(128, 192, false, Image.FORMAT_RGBA8)
	var bay := _facade_image()
	for k in 4:
		above.blit_rect(bay, Rect2i(0, 0, 64, 64), Vector2i((k % 2) * 64, (k / 2) * 64))
	above.blit_rect(_storefront_image(), Rect2i(0, 0, 128, 64), Vector2i(0, 128))
	above.generate_mipmaps()
	var block_front := _building_mat(ImageTexture.create_from_image(above), Vector2(2, 3), 0.45)
	var rooms := _building_mat(_motel_texture(), Vector2.ONE, 0.5)
	plain_mat = plain
	var roof_grey := Color(0.38, 0.37, 0.36)
	var roof_red := Color(0.48, 0.2, 0.15)
	var one := Vector2(2.0, 1.0)
	_mesh("shop", _house(Vector3(14, 4.4, 10), 0.0, facade, plain, roof_grey, true, store, one), 700.0, true)
	_mesh("diner", _house(Vector3(17, 4.0, 9), 0.0, facade, plain, Color(0.5, 0.52, 0.55), true, store, one), 700.0, true)
	_mesh("kiosk", _house(Vector3(10, 3.6, 7), 0.0, plain, plain, roof_grey, true, store, one), 600.0, true)
	_mesh("motel", _house(Vector3(26, 3.4, 8), 1.4, plain, plain, Color(0.33, 0.36, 0.4), false, rooms, Vector2.ONE), 700.0, true)
	_mesh("cabin", _house(Vector3(6, 2.8, 5), 1.9, plain, plain, Color(0.28, 0.3, 0.26), false), 450.0, true)
	# Over each shop's front: an awning and the board its sign is painted on.
	var awning := SurfaceTool.new()
	awning.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope := Basis(Vector3.RIGHT, 0.36)
	_append(awning, _box(Vector3(12.0, 0.06, 1.7)), Transform3D(slope, Vector3(0, 2.95, 5.8)), Color.WHITE)
	_append(awning, _box(Vector3(12.0, 0.3, 0.05)), Transform3D(Basis(), Vector3(0, 2.52, 6.6)), Color(0.85, 0.85, 0.85))
	awning.set_material(_paint)
	_mesh("awning", awning.commit(), 350.0, true)
	_mesh("shop_sign", _merge([[_box(Vector3(8.4, 0.95, 0.1)), Vector3(0, 3.8, 5.05), Color.WHITE]], _paint), 400.0, false)
	_mesh("block", _house(Vector3(12, 10.2, 12), 0.0, facade, plain, roof_grey, true, block_front, Vector2(2.0, 3.0)), 900.0, true)
	_mesh("house", _house(Vector3(9, 3.3, 7.5), 2.6, facade, plain, roof_red, false), 600.0, true)
	_mesh("barn", _house(Vector3(18, 5.0, 11), 4.2, plain, plain, Color(0.3, 0.3, 0.32), false), 800.0, true)
	var silo := SurfaceTool.new()
	silo.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append(silo, _cyl(2.8, 2.8, 13.0, 10), Transform3D(Basis(), Vector3(0, 6.5, 0)), Color(0.8, 0.8, 0.78))
	_append(silo, _ball(2.8, 3.2, 10, 3), Transform3D(Basis(), Vector3(0, 13.0, 0)), Color(0.6, 0.62, 0.65))
	silo.set_material(plain)
	_mesh("silo", silo.commit(), 900.0, true)
	var field := StandardMaterial3D.new()
	field.albedo_texture = _crop_texture()
	field.vertex_color_use_as_albedo = true
	field.vertex_color_is_srgb = true
	field.uv1_triplanar = true
	field.uv1_world_triplanar = true
	field.uv1_scale = Vector3(0.35, 0.45, 0.35)
	field.roughness = 1.0
	field.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var box := SurfaceTool.new()
	box.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append(box, _box(Vector3.ONE), Transform3D(Basis(), Vector3(0, 0.5, 0)), Color.WHITE)
	box.set_material(field)
	_mesh("field", box.commit(), 800.0, false)


## Walls with windows that light up at night: TrackWorld sets `night` on what the track lists
## under "night_materials".
func _building_mat(tex: Texture2D, cells: Vector2, lit: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/building.gdshader")
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("lit_share", lit)
	var list: Array = root.get_meta("night_materials", [])
	list.append(m)
	root.set_meta("night_materials", list)
	return m


## `size` (width along X, wall height, depth along Z) with a gable `roof` m high along X
## (0: flat, with a parapet); the front faces +Z.
## `front`, when given, dresses the front wall instead, its texture spanning `front_span`
## (bays, floors).
static func _house(size: Vector3, roof: float, walls: Material, plain: Material, roof_c: Color,
		parapet: bool, front: Material = null, front_span := Vector2.ONE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var corners := [Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var w := a.distance_to(b)
		var bays := maxf(roundf(w / 4.0), 1.0)
		var floors := maxf(roundf(h / 3.3), 1.0)
		var out := (a + b).normalized()
		if k == 0 and front:
			_wall(fst, a, b, h, Vector2(bays, floors) / front_span, out)
		else:
			_wall(st, a, b, h, Vector2(bays, floors), out)
	st.set_material(walls)
	var mesh := st.commit()
	if front:
		fst.set_material(front)
		fst.commit(mesh)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	top.set_color(roof_c)
	top.set_uv(Vector2.ZERO)
	if roof <= 0.0:
		var y := h + (0.6 if parapet else 0.0)
		var lift := Vector3(0, y, 0)
		_tri(top, corners[0] + lift, corners[1] + lift, corners[2] + lift, Vector3.UP)
		_tri(top, corners[0] + lift, corners[2] + lift, corners[3] + lift, Vector3.UP)
		if parapet:
			for k in 4:
				var a: Vector3 = corners[k]
				var b: Vector3 = corners[(k + 1) % 4]
				_wall(top, a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.6, Vector2.ZERO, (a + b).normalized())
	else:
		var ridge_a := Vector3(-hx - 0.4, h + roof, 0)
		var ridge_b := Vector3(hx + 0.4, h + roof, 0)
		for sz: float in [1.0, -1.0]:
			var ea := Vector3(-hx - 0.4, h - 0.3, sz * (hz + 0.5))
			var eb := Vector3(hx + 0.4, h - 0.3, sz * (hz + 0.5))
			var n := Vector3(0, 1, sz * 0.8).normalized()
			_tri(top, ea, eb, ridge_b, n)
			_tri(top, ea, ridge_b, ridge_a, n)
		# Gable ends.
		for sx: float in [1.0, -1.0]:
			top.set_color(Color(0.85, 0.83, 0.8))
			_tri(top, Vector3(sx * hx, h, hz), Vector3(sx * hx, h, -hz), Vector3(sx * hx, h + roof, 0), Vector3(sx, 0, 0))
	top.set_material(plain)
	top.commit(mesh)
	return mesh


## A wall from `a` to `b` on the ground, `h` tall, facing `out`; `tiles` the texture repeats.
static func _wall(st: SurfaceTool, a: Vector3, b: Vector3, h: float, tiles: Vector2, out: Vector3) -> void:
	var up := Vector3(0, h, 0)
	var q := [[a, Vector2(0, tiles.y)], [b, Vector2(tiles.x, tiles.y)], [b + up, Vector2(tiles.x, 0)], [a + up, Vector2(0, 0)]]
	var n := (b - a).cross(up)
	var order := [0, 2, 1, 0, 3, 2] if n.dot(out) > 0.0 else [0, 1, 2, 0, 2, 3]
	var nrm := n.normalized() if n.dot(out) > 0.0 else -n.normalized()
	for k in order:
		st.set_normal(nrm)
		st.set_uv(q[k][1])
		st.add_vertex(q[k][0])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var verts := [a, c, b] if n.dot(out) > 0.0 else [a, b, c]
	for v in verts:
		st.set_normal(out.normalized())
		st.add_vertex(v)


## One window bay: wall, a framed window with a sill, a sky glint in the glass.
static func _facade_texture() -> ImageTexture:
	var img := _facade_image()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _facade_image() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.88, 0.84))
	img.fill_rect(Rect2i(0, 60, 64, 4), Color(0.75, 0.73, 0.7))
	img.fill_rect(Rect2i(12, 12, 40, 34), Color(0.93, 0.93, 0.92))
	# The glass (alpha 0: see building.gdshader).
	img.fill_rect(Rect2i(14, 14, 36, 30), Color(0.16, 0.2, 0.26, 0.0))
	img.fill_rect(Rect2i(14, 14, 36, 9), Color(0.33, 0.4, 0.48, 0.0))
	img.fill_rect(Rect2i(31, 14, 2, 30), Color(0.93, 0.93, 0.92))
	img.fill_rect(Rect2i(10, 46, 44, 3), Color(0.7, 0.68, 0.65))
	return img


## Two bays of shopfront: a sign band, a display window, then a window and a glazed door.
static func _storefront_texture() -> ImageTexture:
	var img := _storefront_image()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _storefront_image() -> Image:
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.88, 0.84))
	var frame := Color(0.3, 0.26, 0.22)
	var glass := Color(0.14, 0.18, 0.23)
	var sky := Color(0.3, 0.37, 0.45)
	img.fill_rect(Rect2i(0, 58, 128, 6), Color(0.55, 0.52, 0.5))
	for r: Rect2i in [Rect2i(5, 20, 54, 38), Rect2i(69, 20, 34, 38), Rect2i(107, 20, 17, 44)]:
		img.fill_rect(r, frame)
		img.fill_rect(r.grow(-2), Color(glass, 0.0))
		img.fill_rect(Rect2i(r.position + Vector2i(2, 2), Vector2i(r.size.x - 4, 8)), Color(sky, 0.0))
	# Glazing bars and the door's handle.
	img.fill_rect(Rect2i(31, 20, 2, 38), frame)
	img.fill_rect(Rect2i(109, 40, 13, 2), frame)
	img.fill_rect(Rect2i(119, 44, 2, 6), Color(0.8, 0.75, 0.5))
	return img


## One motel room: its door, number plate and window.
static func _motel_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.92, 0.9, 0.85))
	img.fill_rect(Rect2i(0, 58, 64, 6), Color(0.6, 0.58, 0.55))
	img.fill_rect(Rect2i(6, 18, 16, 40), Color(0.25, 0.42, 0.5))
	img.fill_rect(Rect2i(19, 38, 2, 3), Color(0.85, 0.75, 0.4))
	img.fill_rect(Rect2i(10, 22, 8, 3), Color(0.85, 0.8, 0.6))
	img.fill_rect(Rect2i(28, 20, 30, 24), Color(0.95, 0.95, 0.94))
	img.fill_rect(Rect2i(30, 22, 26, 20), Color(0.18, 0.22, 0.28, 0.0))
	img.fill_rect(Rect2i(30, 22, 26, 20).grow_individual(0, 0, -13, 0), Color(0.55, 0.3, 0.25, 0.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Rows of crops seen side-on: stalks, darker gaps, lighter tops.
static func _crop_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for x in 64:
		var shade := r.randf_range(0.75, 1.1)
		for y in 64:
			var tip := 1.0 - y / 64.0
			var c := Color(0.55, 0.6, 0.3).lerp(Color(0.85, 0.78, 0.45), tip * tip) * shade
			if (x + y / 9) % 5 == 0:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Town ------------------------------------------------------------------------------------

func _town() -> void:
	var tints := [Color(1, 1, 1), Color(0.95, 0.85, 0.7), Color(0.85, 0.9, 0.95), Color(0.95, 0.8, 0.75),
		Color(0.85, 0.9, 0.8), Color(0.9, 0.9, 0.82)]
	for s: float in [-1.0, 1.0]:
		var i := 0
		while i < lay.n:
			if lay.zone[i] != Zone.TOWN or lay.kind[i] != Kind.OPEN or absf(lay.curv[i]) > 1.0 / 60.0:
				i += 1
				continue
			var pick := rng.randf()
			var kind := "shop" if pick < 0.45 else ("block" if pick < 0.7 else "house")
			var width: float = {"shop": 14.0, "block": 12.0, "house": 9.0}[kind]
			var depth: float = {"shop": 10.0, "block": 12.0, "house": 7.5}[kind]
			var d := lay.edge[i] + 5.0 + depth * 0.5 + rng.randf_range(0.0, 2.0)
			var p := _beside(i, s, d)
			var gap := int(ceilf((width + rng.randf_range(2.0, 7.0)) / ProceduralTrack.STEP))
			if rng.randf() < 0.85 and _clear(p, depth * 0.5, 10.0):
				p.y = minf(p.y, _beside(i, s, d - depth * 0.5).y) - 0.3
				var xf := _upright(p, -lay.flat_right[i] * s)
				_put(kind, xf, tints[rng.randi() % tints.size()])
				places.dress(kind, xf, i, s)
			i += gap
	# Street lamps over the pavements, staggered.
	for i in range(0, lay.n, 5):
		if lay.zone[i] != Zone.TOWN or lay.kind[i] != Kind.OPEN:
			continue
		var s := 1.0 if (i / 5) % 2 == 0 else -1.0
		# Just behind the pavement, clear of a car running wide; the arm reaches the kerb.
		_lamp(i, s, lay.edge[i] + 1.4)


func _lamp(i: int, s: float, d: float) -> void:
	var p := lay.pts[i] + lay.right[i] * s * d
	if lay.on_branch(p.x, p.z, 0.3):
		return
	p.y = lay.side_y(i, s, d) if d > lay.edge[i] else lay.road_y(i, s, d) + ProcGround._kerb(lay, i, s)
	var xf := _upright(p, -lay.flat_right[i] * s)
	_put("lamp_post", xf)
	_put("lamp_head", xf)
	var under := lay.pts[i] + lay.right[i] * s * (d - 3.0)
	_pools.append(Transform3D(Basis.from_scale(Vector3(11.0, 1.0, 11.0)), under + lay.up[i] * 0.04))


## Warm pools of light on the road under the street lamps, drawn over it (added, not lit),
## shown only at night: TrackWorld turns on what the track lists under "night_only".
func _light_pools() -> void:
	if _pools.is_empty():
		return
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var f := clampf(1.0 - r, 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			img.set_pixel(x, y, Color(f, f, f))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color(0.75, 0.52, 0.25)
	mat.no_depth_test = false
	mat.render_priority = 1
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = _pools.size()
	for k in _pools.size():
		mm.set_instance_transform(k, _pools[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	root.add_child(mmi)
	var night: Array = root.get_meta("night_only", [])
	night.append(mmi)
	root.set_meta("night_only", night)


func _bridge_lamps() -> void:
	for run in ProceduralTrack._runs(lay.kind, Kind.BRIDGE):
		for k in range(2, run[1] - 1, 6):
			var i := lay.idx(run[0] + k)
			for s: float in [-1.0, 1.0]:
				_lamp(i, s, lay.edge[i] + 0.2)


## The start/finish gantry over the line.
func _gantry() -> void:
	var i := 0
	var e := lay.edge[i] + 0.8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color(0.28, 0.3, 0.34)
	for s: float in [-1.0, 1.0]:
		_append(st, _box(Vector3(0.7, 8.4, 0.7)), Transform3D(Basis(), Vector3(s * e, 4.2 - 0.5, 0)), steel)
	_append(st, _box(Vector3(e * 2.0 + 0.7, 0.5, 0.6)), Transform3D(Basis(), Vector3(0, 7.7, 0)), steel)
	_append(st, _box(Vector3(e * 2.0 - 1.0, 0.3, 0.4)), Transform3D(Basis(), Vector3(0, 5.6, 0)), steel)
	st.set_material(_paint)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var banner := Image.create(128, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 128:
			banner.set_pixel(x, y, Color(0.95, 0.95, 0.95) if (x / 8 + y / 8) % 2 == 0 else Color(0.06, 0.06, 0.06))
	var bm := _sign_mat(banner)
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var board := MeshInstance3D.new()
	board.mesh = _board(Vector2(e * 2.0 - 1.0, 1.6), 5.8, bm)
	var holder := Node3D.new()
	holder.transform = _upright(lay.pts[i], -lay.fwd[i])
	holder.add_child(mi)
	holder.add_child(board)
	var font: Font = load("res://fonts/BarlowCondensed-BoldItalic.ttf")
	for face: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "START  ·  FINISH" if face > 0.0 else "FINISH"
		label.font = font
		label.font_size = 96
		label.pixel_size = 0.012
		label.modulate = Color(1.0, 0.8, 0.1)
		label.outline_size = 24
		label.outline_modulate = Color(0.05, 0.05, 0.05)
		label.position = Vector3(0, 6.6, 0.25 * face)
		label.rotation.y = 0.0 if face > 0.0 else PI
		label.double_sided = false
		holder.add_child(label)
	root.add_child(holder)
	for s: float in [-1.0, 1.0]:
		var o := _body.create_shape_owner(_body)
		var tower := BoxShape3D.new()
		tower.size = Vector3(0.7, 8.4, 0.7)
		_body.shape_owner_add_shape(o, tower)
		_body.shape_owner_set_transform(o, holder.transform * Transform3D(Basis(), Vector3(s * e, 3.7, 0)))


# --- Farms -----------------------------------------------------------------------------------

func _farms() -> void:
	var i := 0
	while i < lay.n:
		if lay.zone[i] != Zone.FARM or lay.kind[i] != Kind.OPEN:
			i += 1
			continue
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		if rng.randf() < 0.3:
			_farmstead(i, s)
			i += 20
			continue
		# A field running along the road: tall corn or short wheat.
		var length := rng.randf_range(50.0, 110.0)
		var depth := rng.randf_range(30.0, 70.0)
		var wall := lay.wall_r[i] if s > 0.0 else lay.wall_l[i]
		var d := wall + rng.randf_range(4.0, 10.0) + depth * 0.5
		var c := _beside(i, s, d, length * 0.5)
		var ys := PackedFloat32Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			ys.append(_beside(i, s, d + corner.x * depth * 0.5, length * 0.5 + corner.y * length * 0.5).y)
		var lo := ys[0]
		var hi := ys[0]
		for y in ys:
			lo = minf(lo, y)
			hi = maxf(hi, y)
		var corn := rng.randf() < 0.55
		var h := 2.3 if corn else 0.8
		var over_lane := false
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO, Vector2(0, -1), Vector2(0, 1)]:
			var q := _beside(i, s, d + corner.x * depth * 0.5, length * 0.5 + corner.y * length * 0.5)
			over_lane = over_lane or lay.on_branch(q.x, q.z, maxf(depth, length) * 0.3)
		if hi - lo < 3.0 and not over_lane and _clear(c + lay.flat_right[i] * s * (-depth * 0.5), 0.0, 10.0):
			var tint := Color(0.85, 1.0, 0.8) if corn else Color(1.15, 1.0, 0.75)
			c.y = lo - 0.6
			_put("field", _upright(c, lay.fwd[i], Vector3(depth, hi - lo + h + 0.6, length)), tint)
		i += int(length / ProceduralTrack.STEP) + rng.randi_range(2, 8)


## A barn, a silo or two and the farmhouse, set back from the road.
func _farmstead(i: int, s: float) -> void:
	var wall := lay.wall_r[i] if s > 0.0 else lay.wall_l[i]
	var d := wall + rng.randf_range(22.0, 40.0)
	var face := -lay.flat_right[i] * s
	var barn := _beside(i, s, d)
	if not _clear(barn, 10.0, 0.35):
		return
	_put("barn", _upright(barn - Vector3(0, 0.4, 0), lay.fwd[i].rotated(Vector3.UP, rng.randf_range(-0.2, 0.2))),
		Color(0.72, 0.22, 0.16) if rng.randf() < 0.7 else Color(0.85, 0.82, 0.76))
	for k in rng.randi_range(1, 2):
		var p := _beside(i, s, d + 10.0 + k * 6.5, -12.0)
		if _clear(p, 3.0, 10.0):
			_put("silo", _upright(p - Vector3(0, 0.3, 0), face))
	var house := _beside(i, s, d - 4.0, 26.0)
	if _clear(house, 6.0, 0.35):
		_put("house", _upright(house - Vector3(0, 0.3, 0), face), Color(0.97, 0.95, 0.88))
	for k in 5:
		var p := _beside(i, s, d + rng.randf_range(-12.0, 18.0), rng.randf_range(-25.0, 35.0))
		if _clear(p, 2.0):
			_put("broadleaf", _upright(p, Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU), Vector3.ONE * rng.randf_range(0.9, 1.3)),
				_leaf_tint())


# --- Along the road --------------------------------------------------------------------------

## Galvanised guardrails where the layout put them: a W-beam on posts along the wall, cut
## into half-metre columns so a car's hit bends it (Guardrails). The collision strip behind
## it does the stopping.
func _rails() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rails := Guardrails.new()
	rails.name = "Guardrails"
	root.add_child(rails)
	var grey := Color(0.74, 0.76, 0.78)
	const COLS := 12
	# Beam cross-section: (out from the wall, up from the ground).
	var prof := [Vector2(0.0, 0.48), Vector2(0.07, 0.58), Vector2(0.0, 0.68), Vector2(0.07, 0.78), Vector2(0.0, 0.84)]
	for s: float in [-1.0, 1.0]:
		var rail := lay.rail_r if s > 0.0 else lay.rail_l
		var walls := lay.wall_r if s > 0.0 else lay.wall_l
		var out := Nfs3TrackBuilder._rail_arrays()
		for i in lay.n:
			var j := lay.idx(i + 1)
			# A mesh per 40 nodes of road, so each is culled by how far off its own stretch is.
			if i % 40 == 0 and not out[1].is_empty():
				rails.add_chunk(out[0], out[1], mat, 450.0)
				out = Nfs3TrackBuilder._rail_arrays()
			if not rail[i]:
				continue
			var base_i := _rail_base(i, s, walls[i])
			_put("rail_post", _upright(base_i, lay.fwd[i]))
			if not rail[j]:
				continue
			var base_j := _rail_base(j, s, walls[j])
			_solid_strip(base_i, base_j, 1.1)
			var arrays: Array = out[0]
			for c in COLS:
				var t0 := float(c) / COLS
				var t1 := float(c + 1) / COLS
				for m in prof.size() - 1:
					var q := [_rail_col(i, j, s, base_i, base_j, t0, prof[m]), _rail_col(i, j, s, base_i, base_j, t0, prof[m + 1]),
						_rail_col(i, j, s, base_i, base_j, t1, prof[m + 1]), _rail_col(i, j, s, base_i, base_j, t1, prof[m])]
					var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
					for k in [0, 1, 2, 0, 2, 3]:
						arrays[Mesh.ARRAY_VERTEX].append(q[k])
						arrays[Mesh.ARRAY_NORMAL].append(n)
						arrays[Mesh.ARRAY_COLOR].append(grey)
						arrays[Mesh.ARRAY_TEX_UV].append(Vector2.ZERO)
						arrays[Mesh.ARRAY_TEX_UV2].append(Vector2.ZERO)
						out[1].append(prof[m + (1 if k == 1 or k == 2 else 0)].y / 0.84)
		if not out[1].is_empty():
			rails.add_chunk(out[0], out[1], mat, 450.0)


## A point of the beam `t` of the way from node `i` to `j`, at profile point `q`.
func _rail_col(i: int, j: int, s: float, base_i: Vector3, base_j: Vector3, t: float, q: Vector2) -> Vector3:
	var out := lay.flat_right[i].lerp(lay.flat_right[j], t).normalized()
	return base_i.lerp(base_j, t) + out * s * q.x + Vector3.UP * q.y


func _rail_base(i: int, s: float, d: float) -> Vector3:
	var p := lay.pts[i] + lay.flat_right[i] * s * d
	p.y = lay.side_y(i, s, d)
	return p


func _rail_pt(i: int, s: float, base: Vector3, q: Vector2) -> Vector3:
	return base + lay.flat_right[i] * s * q.x + Vector3.UP * q.y


## White three-rail wooden fences along the farms, a panel a node long: a car knocks the
## panel it hits flying, post and all, as the NFS3 tracks' fences go.
func _fences() -> void:
	var white := Color(0.92, 0.91, 0.87)
	var mat: Material = _meshes["fence_post"].mesh.surface_get_material(0)
	var ch := {}
	for s: float in [-1.0, 1.0]:
		var rail := lay.rail_r if s > 0.0 else lay.rail_l
		var walls := lay.wall_r if s > 0.0 else lay.wall_l
		var on := false
		for i in lay.n:
			if i % 40 == 0 or ch.is_empty():
				ch = _fence_chunk(ch, mat)
			var farm := lay.zone[i] == Zone.FARM and lay.kind[i] == Kind.OPEN and not rail[i]
			# Runs of a few hundred metres with gaps (gates, driveways).
			if i % 25 == 0:
				on = rng.randf() < 0.7
			var gaps := lay.gap_r if s > 0.0 else lay.gap_l
			if not farm or not on or no_fence.has(i * 2 + int(s > 0.0)) or gaps[i] or gaps[lay.idx(i + 1)]:
				continue
			var d := walls[i] + 1.5
			var a := _beside(i, s, d)
			if lay.on_branch(a.x, a.z, 0.3):
				continue
			var j := lay.idx(i + 1)
			var b := _beside(j, s, walls[j] + 1.5) if j < lay.n else a
			var mid := (a + b) * 0.5
			if absf(b.y - a.y) > 2.0 or lay.on_branch(b.x, b.z, 0.3) or lay.on_branch(mid.x, mid.z, 0.3):
				continue
			# The panel's frame: its foot at the post, X along it to the next.
			var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var xf := _upright(a, along.cross(Vector3.UP).normalized())
			var post := _put("fence_post", _upright(a, lay.fwd[i]))
			var arrays: Array = ch.arrays
			var from: int = arrays[Mesh.ARRAY_VERTEX].size()
			for h: float in [0.45, 0.8, 1.15]:
				var q := [a + Vector3.UP * h, b + Vector3.UP * h, b + Vector3.UP * (h + 0.12), a + Vector3.UP * (h + 0.12)]
				var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
				for k in [0, 1, 2, 0, 2, 3]:
					arrays[Mesh.ARRAY_VERTEX].append(q[k])
					arrays[Mesh.ARRAY_NORMAL].append(n)
					arrays[Mesh.ARRAY_COLOR].append(white)
			var lb := xf.affine_inverse() * b
			var reach := AABB(Vector3(minf(lb.x, 0.0) - 0.2, 0.0, -0.3), Vector3(absf(lb.x) + 0.4, 1.3, 0.6))
			_knock_panel(xf, reach, ch, from, post)
	_fence_chunk(ch, mat)


## The fence chunk after `ch` (which is drawn, if it has anything in it).
func _fence_chunk(ch: Dictionary, mat: Material) -> Dictionary:
	if not ch.is_empty() and not ch.arrays[Mesh.ARRAY_VERTEX].is_empty():
		var built := Breakables.chunk(ch.arrays, mat)
		ch.mesh = built.mesh
		ch.mat = mat
		var mi := MeshInstance3D.new()
		mi.mesh = ch.mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 450.0
		root.add_child(mi)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	return {"arrays": arrays}


## A fence panel (vertices `from` on in chunk `ch`, 3 rails) and its post `post` (from _put),
## knocked flying together.
func _knock_panel(xf: Transform3D, reach: AABB, ch: Dictionary, from: int, post: Array) -> void:
	_knock.append([xf, reach, [post], null, ch, from])


## Telephone poles down one side of the farm and lake roads, wires sagging between them.
func _poles() -> void:
	var wire := ImmediateMesh.new()
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color(0.1, 0.1, 0.1)
	var s := -1.0
	var prev := Transform3D()
	var have_prev := false
	var segments := 0
	wire.surface_begin(Mesh.PRIMITIVE_LINES, wm)
	for i in range(0, lay.n, 7):
		var z := lay.zone[i]
		var d := lay.wall_l[i] + 6.0
		var p := _beside(i, s, d)
		var ok := (z == Zone.FARM or z == Zone.LAKE) and lay.kind[i] == Kind.OPEN and _clear(p, 0.5, 1.5)
		if not ok:
			have_prev = false
			continue
		var xf := _upright(p, lay.fwd[i])
		_put("pole", xf)
		if have_prev and prev.origin.distance_to(p) < 70.0:
			for off: float in [-1.05, 0.0, 1.05]:
				var a := prev * Vector3(off, 8.95, 0)
				var b := xf * Vector3(off, 8.95, 0)
				const SEG := 8
				for k in SEG:
					for t: float in [float(k) / SEG, float(k + 1) / SEG]:
						var sag := 4.0 * t * (1.0 - t) * 0.9
						wire.surface_add_vertex(a.lerp(b, t) + Vector3.DOWN * sag)
			segments += 1
		prev = xf
		have_prev = true
	if segments == 0:
		wire.surface_add_vertex(Vector3.ZERO)
		wire.surface_add_vertex(Vector3.ZERO)
	wire.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = wire
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Chevrons round the outside of tight bends, and a warning sign on the way into them with
## the speed to take them at.
func _bend_signs() -> void:
	var i := 0
	while i < lay.n:
		var k := absf(lay.curv[i])
		if k < 1.0 / 95.0 or lay.zone[i] == Zone.TOWN or lay.kind[i] != Kind.OPEN:
			i += 1
			continue
		# The whole bend: while it keeps turning the same way.
		var turn := signf(lay.curv[i])
		var a := i
		var tightest := k
		while i < lay.n and lay.curv[i] * turn > 1.0 / 140.0:
			tightest = maxf(tightest, absf(lay.curv[i]))
			i += 1
		var outside := -turn
		var walls := lay.wall_r if outside > 0.0 else lay.wall_l
		for j in range(a, i, 3):
			if lay.kind[j] != Kind.OPEN:
				continue
			var p := _beside(j, outside, walls[j] + 0.9)
			if lay.on_branch(p.x, p.z, 0.5):
				continue
			# Facing the traffic coming round, angled a little in towards it.
			var face := (-lay.fwd[j] - lay.flat_right[j] * outside * 0.35).normalized()
			var sc := Vector3(turn, 1, 1)
			knockable(_upright(p, face), ProcSigns.POST_REACH, [_put("sign_post", _upright(p, face)),
				_put("chevron", _upright(p, face, sc))])
		var w := lay.idx(a - 16)
		var wp := _beside(w, 1.0, lay.wall_r[w] + 1.2)
		if lay.kind[w] == Kind.OPEN and not lay.on_branch(wp.x, wp.z, 0.5):
			knockable(_upright(wp, -lay.fwd[w]), ProcSigns.POST_REACH, [_put("sign_post", _upright(wp, -lay.fwd[w])),
				_put("curve_sign", _upright(wp, -lay.fwd[w], Vector3(turn, 1, 1)))])
			signs.advisory(_upright(wp, -lay.fwd[w]), 1.0 / tightest)


## Boulders on the cuttings and scattered off the road in the hills and by the lake.
func _rocks() -> void:
	for i in range(0, lay.n, 2):
		var z := lay.zone[i]
		if z != Zone.MOUNTAIN and z != Zone.LAKE and z != Zone.FOREST or lay.kind[i] != Kind.OPEN:
			continue
		for s: float in [-1.0, 1.0]:
			if rng.randf() > (0.5 if z == Zone.MOUNTAIN else 0.15):
				continue
			var wall := lay.wall_r[i] if s > 0.0 else lay.wall_l[i]
			var p := _beside(i, s, wall + rng.randf_range(1.5, 30.0), rng.randf_range(-3.0, 3.0))
			if not _clear(p, 0.5, 10.0):
				continue
			var sc := Vector3(rng.randf_range(0.8, 2.6), rng.randf_range(0.6, 1.8), rng.randf_range(0.8, 2.4))
			var xf := _upright(p + Vector3.DOWN * sc.y * 0.3, Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU), sc)
			_put("rock", xf, Color(1, 1, 1) * rng.randf_range(0.8, 1.1))


# --- Trees -----------------------------------------------------------------------------------

func _leaf_tint() -> Color:
	var v := rng.randf_range(0.8, 1.15)
	return Color(v * rng.randf_range(0.9, 1.15), v, v * rng.randf_range(0.85, 1.0))


## Trees near the road, thickest through the forest.
func _roadside_trees() -> void:
	var density := {Zone.TOWN: 0.12, Zone.FARM: 0.2, Zone.FOREST: 1.9, Zone.MOUNTAIN: 0.7, Zone.LAKE: 0.5}
	for i in lay.n:
		var z := lay.zone[i]
		for s: float in [-1.0, 1.0]:
			var count := int(density[z] + rng.randf())
			for c in count:
				var wall := lay.wall_r[i] if s > 0.0 else lay.wall_l[i]
				var d := wall + 3.5 + pow(rng.randf(), 1.6) * 60.0
				var p := _beside(i, s, d, rng.randf_range(-3.0, 3.0))
				if not _clear(p, 1.0):
					continue
				_tree(p, z, false)
	# Poplar windbreaks along a few farm lanes.
	for i in range(0, lay.n, 45):
		if lay.zone[i] != Zone.FARM or rng.randf() < 0.4:
			continue
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var wall := lay.wall_r[i] if s > 0.0 else lay.wall_l[i]
		var d := wall + rng.randf_range(15.0, 30.0)
		for k in 12:
			var p := _beside(i, s, d + rng.randf_range(-0.5, 0.5), k * 7.0)
			if _clear(p, 1.0):
				_put("poplar", _upright(p, Vector3.FORWARD, Vector3.ONE * rng.randf_range(0.85, 1.2)), _leaf_tint())


func _tree(p: Vector3, z: int, far: bool) -> void:
	var sc := Vector3.ONE * rng.randf_range(0.8, 1.45)
	sc.y *= rng.randf_range(0.9, 1.2)
	var xf := _upright(p + Vector3.DOWN * 0.2, Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU), sc)
	var conifer_share: float = {Zone.TOWN: 0.1, Zone.FARM: 0.2, Zone.FOREST: 0.7, Zone.MOUNTAIN: 0.9, Zone.LAKE: 0.55}[z]
	if rng.randf() < conifer_share:
		_put("conifer_far" if far else "conifer", xf, _leaf_tint())
	elif rng.randf() < 0.85:
		_put("broadleaf", xf, _leaf_tint())
	else:
		_put("bush", xf, _leaf_tint())


## Forest over the land beyond the road, in patches, thinning out with height.
func _forests() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = rng.randi()
	fn.frequency = 1.0 / 420.0
	fn.fractal_octaves = 3
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in lay.pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2.ONE * 380.0
	hi += Vector2.ONE * 380.0
	var top := -INF
	for p in lay.pts:
		top = maxf(top, p.y)
	const SPACING := 17.0
	var x := lo.x
	while x < hi.x:
		var z := lo.y
		while z < hi.y:
			var px := x + rng.randf_range(-7.0, 7.0)
			var pz := z + rng.randf_range(-7.0, 7.0)
			z += SPACING
			var i := lay.closest(px, pz)
			var zone: int = lay.zone[i] if i >= 0 else Zone.FOREST
			var bias: float = {Zone.TOWN: -0.35, Zone.FARM: -0.25, Zone.FOREST: 0.25, Zone.MOUNTAIN: 0.1, Zone.LAKE: 0.0}[zone]
			var f := fn.get_noise_2d(px, pz) + bias
			if f < 0.05 or rng.randf() > _density * smoothstep(0.05, 0.3, f):
				continue
			var p := Vector3(px, ProcGround.surface_y(lay, px, pz), pz)
			if p.y > top + 120.0 - rng.randf() * 40.0 or not _clear(p, 2.0, 0.75):
				continue
			var near := i >= 0 and Vector2(px - lay.pts[i].x, pz - lay.pts[i].z).length() < 120.0
			_tree(p, zone if near else Zone.MOUNTAIN, not near)
		x += SPACING

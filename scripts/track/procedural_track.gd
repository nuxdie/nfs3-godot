class_name ProceduralTrack
## A generated closed circuit (road ribbon, verges, rolling terrain, trees,
## fences) used when no NFS3 data is installed.

const ROAD_HALF := 7.0
const VERGE := 5.0
const STEP := 6.0
const TREE_DRAW_DISTANCE := 450.0


static func build(root: Node3D, seed_value := 1998) -> TrackPath:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var curve := _curve(rng)

	var path := TrackPath.new()
	var total := curve.get_baked_length()
	var count := int(total / STEP)
	for i in count:
		var p := curve.sample_baked(i * STEP)
		var q := curve.sample_baked(fmod((i + 1) * STEP, total))
		var fwd := (q - p).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		path.points.append(p)
		path.rights.append(right)
		path.ups.append(Vector3.UP)
		path.left_width.append(ROAD_HALF + VERGE)
		path.right_width.append(ROAD_HALF + VERGE)
	path.finalize()

	var ground := _ground_level(path)
	_build_road(root, path, ground)
	_build_terrain(root, ground)
	_build_props(root, path, rng, ground)
	root.add_child(Nfs3TrackBuilder.make_walls(path))
	return path


## The lap's centreline, without building the track (for the menu's map).
static func outline(seed_value := 1998) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _curve(rng).get_baked_points()


static func _curve(rng: RandomNumberGenerator) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = STEP
	var n_ctrl := 14
	var ctrl: Array[Vector3] = []
	for i in n_ctrl:
		var a := TAU * i / n_ctrl
		var r := rng.randf_range(380.0, 620.0)
		ctrl.append(Vector3(cos(a) * r * 1.3, rng.randf_range(0.0, 22.0), sin(a) * r))
	for i in n_ctrl:
		var prev := ctrl[(i - 1 + n_ctrl) % n_ctrl]
		var next := ctrl[(i + 1) % n_ctrl]
		var tan := (next - prev) * 0.28
		curve.add_point(ctrl[i], -tan, tan)
	curve.add_point(ctrl[0], -(ctrl[1] - ctrl[n_ctrl - 1]) * 0.28, Vector3.ZERO)
	return curve


static func _mat(color: Color, stripes := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if stripes:
		var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		img.fill(color)
		for y in 64:
			for x in 64:
				var n := randf_range(-0.04, 0.04)
				img.set_pixel(x, y, Color(color.r + n, color.g + n, color.b + n))
				if absi(x - 32) < 1 and y < 32:
					img.set_pixel(x, y, Color(0.95, 0.85, 0.3))
				if x < 2 or x > 61:
					img.set_pixel(x, y, Color(0.95, 0.95, 0.95))
		img.generate_mipmaps()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.albedo_color = Color.WHITE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## The flat ground sits below the lowest point of the road.
static func _ground_level(path: TrackPath) -> float:
	var lowest := INF
	for p in path.points:
		lowest = minf(lowest, p.y)
	return lowest - 1.5


## Width of the grass bank from the verge's outer edge down to the ground, for road height `y`.
static func _bank_width(y: float, ground: float) -> float:
	return maxf((y - 0.3 - ground) * 1.6, 1.0)


## Ground height `d` metres to the side of a road point at height `y` (verge, then bank, then flat).
static func _ground_at(y: float, d: float, ground: float) -> float:
	var off := d - (ROAD_HALF + VERGE)
	if off <= 0.0:
		return y - 0.3
	return lerpf(y - 0.3, ground, clampf(off / _bank_width(y, ground), 0.0, 1.0))


static func _build_road(root: Node3D, path: TrackPath, ground: float) -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verge := SurfaceTool.new()
	verge.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Grass banks from the verges down to the ground, so a raised stretch doesn't float in the air.
	var bank := SurfaceTool.new()
	bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var n := path.size()
	for i in n:
		var j := (i + 1) % n
		var a := path.points[i]
		var b := path.points[j]
		var ra := path.rights[i]
		var rb := path.rights[j]
		var v0 := i * STEP / 20.0
		var v1 := v0 + STEP / 20.0
		var al := a - ra * ROAD_HALF
		var ar := a + ra * ROAD_HALF
		var bl := b - rb * ROAD_HALF
		var br := b + rb * ROAD_HALF
		_quad(road, al, ar, br, bl, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1))
		faces.append_array([al, ar, br, al, br, bl])
		for side: float in [-1.0, 1.0]:
			var ai := a + ra * ROAD_HALF * side
			var ao := a + ra * (ROAD_HALF + VERGE) * side + Vector3.DOWN * 0.3
			var bi := b + rb * ROAD_HALF * side
			var bo := b + rb * (ROAD_HALF + VERGE) * side + Vector3.DOWN * 0.3
			var ga := ao + ra * _bank_width(a.y, ground) * side
			ga.y = ground
			var gb := bo + rb * _bank_width(b.y, ground) * side
			gb.y = ground
			# Wound outward from the road on the right, so the left side is listed in reverse.
			if side > 0.0:
				_quad(verge, ai, ao, bo, bi, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
				_quad(bank, ao, ga, gb, bo, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(verge, bi, bo, ao, ai, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO)
				_quad(bank, bo, gb, ga, ao, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT, Vector2.ZERO)
			faces.append_array([ai, ao, bo, ai, bo, bi])
	road.generate_normals()
	verge.generate_normals()
	bank.generate_normals()
	var bmi := MeshInstance3D.new()
	bmi.mesh = bank.commit()
	bmi.material_override = _mat(Color(0.3, 0.45, 0.2))
	root.add_child(bmi)
	var mi := MeshInstance3D.new()
	mi.mesh = road.commit()
	mi.material_override = _mat(Color(0.28, 0.28, 0.3), true)
	root.add_child(mi)
	root.set_meta("road_material", mi.material_override)   # Reflections wets it in the rain
	var vi := MeshInstance3D.new()
	vi.mesh = verge.commit()
	vi.material_override = _mat(Color(0.45, 0.4, 0.3))
	root.add_child(vi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	# Wound so the face points up in Godot's (counter-clockwise front) convention.
	for pair in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


static func _build_terrain(root: Node3D, ground: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(0, ground, 0)
	mi.material_override = _mat(Color(0.3, 0.45, 0.2))
	root.add_child(mi)


static func _build_props(root: Node3D, path: TrackPath, rng: RandomNumberGenerator, ground: float) -> void:
	# Low-poly on purpose: the default primitives (~4k tris per crown) times a few
	# hundred trees, times every shadow cascade and the mirror, was millions of tris a frame.
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 0
	trunk.cap_top = false
	trunk.cap_bottom = false
	var crown := SphereMesh.new()
	crown.radius = 2.6
	crown.height = 6.5
	crown.radial_segments = 10
	crown.rings = 5
	var trunk_mat := _mat(Color(0.35, 0.22, 0.12))
	var leaf := _mat(Color.WHITE)
	leaf.vertex_color_use_as_albedo = true
	var trees: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(0, path.size(), 2):
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.35:
				continue
			var d := ROAD_HALF + VERGE + rng.randf_range(4.0, 60.0)
			var p: Vector3 = path.points[i] + path.rights[i] * d * side
			p.y = _ground_at(path.points[i].y, d, ground) - 0.2
			var s := rng.randf_range(0.8, 1.5)
			trees.append(Transform3D(Basis().scaled(Vector3.ONE * s), p))
	for t in trees:
		colors.append(Color.from_hsv(rng.randf_range(0.05, 0.3), 0.7, rng.randf_range(0.35, 0.6)))
	# Consecutive trees along the road share a MultiMesh, so each chunk has a tight AABB
	# and gets frustum-culled / distance-culled instead of the whole forest always drawing.
	const CHUNK := 24
	for start in range(0, trees.size(), CHUNK):
		var n := mini(CHUNK, trees.size() - start)
		var trunk_mm := MultiMesh.new()
		trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
		trunk_mm.mesh = trunk
		trunk_mm.instance_count = n
		var crown_mm := MultiMesh.new()
		crown_mm.transform_format = MultiMesh.TRANSFORM_3D
		crown_mm.use_colors = true
		crown_mm.mesh = crown
		crown_mm.instance_count = n
		for k in n:
			var t := trees[start + k]
			trunk_mm.set_instance_transform(k, t.translated(Vector3.UP * 1.5 * t.basis.get_scale().y))
			crown_mm.set_instance_transform(k, t.translated(Vector3.UP * 5.5 * t.basis.get_scale().y))
			crown_mm.set_instance_color(k, colors[start + k])
		for pair in [[trunk_mm, trunk_mat], [crown_mm, leaf]]:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = pair[0]
			mmi.material_override = pair[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = TREE_DRAW_DISTANCE
			mmi.visibility_range_end_margin = 30.0
			root.add_child(mmi)

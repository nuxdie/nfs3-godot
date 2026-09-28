class_name ProcGround
## The procedural track's ground: the road and its verges, the land shaped around it
## (strips of cross-section along the road, cut into hillsides and built up over hollows),
## the terrain grid beyond that and the mountains on the horizon, the river and lake, the
## tunnel and the bridges. See ProceduralTrack for the layout it builds from.


## Cross-section samples beyond the verge's edge (m); scaled in on the inside of tight bends.
const DD := [0.0, 1.2, 2.8, 5.0, 7.5, 11.0, 15.5, 21.0, 28.0, 36.0, 45.0]
const REACH := 45.0
const CHUNK := 32            # path nodes per mesh chunk
const CELL := 12.5           # terrain grid spacing...
const GRID_CHUNK := 16       # ...and cells per terrain mesh
const MARGIN := 500.0        # terrain grid beyond the course
const TUNNEL_WALL := 4.6     # height where the tunnel's walls turn into its roof...
const TUNNEL_ROOF := 2.6     # ...and how much higher its crown is
const DECK := 1.5            # bridge deck depth

# Surface codes (see TrackSurface) and the dust images they index.
const S_ASPHALT := 1
const S_CONCRETE := 4
const S_GRAVEL := 5
const S_GRASS := 14


class Strip:
	## A grid of vertices: one row per path node round the lap, `cols` across it, ordered
	## left to right as the driver sees them.
	var rows: Array[PackedVector3Array] = []
	var uvs: Array[PackedVector2Array] = []
	var colors: Array[PackedColorArray] = []
	var normals: Array[PackedVector3Array] = []

	func compute_normals() -> void:
		var n := rows.size()
		normals.clear()
		for i in n:
			var r := rows[i]
			var prev := rows[(i - 1 + n) % n]
			var next := rows[(i + 1) % n]
			var out := PackedVector3Array()
			for k in r.size():
				var along := next[k] - prev[k]
				var across := r[mini(k + 1, r.size() - 1)] - r[maxi(k - 1, 0)]
				var nrm := across.cross(along).normalized()
				out.append(nrm if nrm.y >= 0.0 else -nrm)
			normals.append(out)


static func build(root: Node3D, lay: ProceduralTrack.Layout) -> void:
	var fine := _noise_tex(1.0 / 24.0, 256)
	var coarse := _noise_tex(1.0 / 40.0, 256)
	var road_mat := ShaderMaterial.new()
	road_mat.shader = preload("res://shaders/proc_road.gdshader")
	road_mat.set_shader_parameter("noise_fine", fine)
	road_mat.set_shader_parameter("noise_coarse", coarse)
	road_mat.set_shader_parameter("half_width", ProceduralTrack.ROAD_HALF)
	road_mat.set_shader_parameter("lap_length", lay.n * ProceduralTrack.STEP)
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = preload("res://shaders/proc_ground.gdshader")
	ground_mat.set_shader_parameter("noise_fine", fine)
	ground_mat.set_shader_parameter("noise_coarse", coarse)
	ground_mat.set_shader_parameter("water_line", lay.water)
	var highest := -INF
	for p in lay.pts:
		highest = maxf(highest, p.y)
	ground_mat.set_shader_parameter("snow_line", highest + 230.0)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.72, 0.7, 0.66)
	concrete.albedo_texture = speckle(0.8)
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	concrete.uv1_scale = Vector3.ONE * 0.35
	concrete.roughness = 0.9
	concrete.vertex_color_use_as_albedo = true
	concrete.vertex_color_is_srgb = true
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED

	var road_body := _body("Road")
	var terrain_body := _body("Terrain")
	root.add_child(road_body)
	root.add_child(terrain_body)
	var dust: Array[Image] = []
	for c in [Color(0.3, 0.3, 0.31), Color(0.58, 0.53, 0.45), Color(0.6, 0.6, 0.58), Color(0.36, 0.44, 0.22)]:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(c)
		dust.append(img)
	for b in [road_body, terrain_body]:
		TrackSurface.set_images(b, dust)

	_road(root, lay, road_mat, ground_mat, road_body)
	_sides(root, lay, ground_mat, terrain_body)
	_terrain(root, lay, ground_mat, terrain_body)
	_water(root, lay, fine)
	_tunnels(root, lay, concrete, ground_mat)
	_bridges(root, lay, concrete, ground_mat)
	root.set_meta("road_material", road_mat)   # Reflections wets it in the rain


static func _body(body_name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = body_name
	b.collision_layer = 1
	b.collision_mask = 0
	return b


## Soft noise between `lo` and white, to multiply into a flat colour.
static func speckle(lo: float) -> NoiseTexture2D:
	var t := _noise_tex(1.0 / 16.0, 128)
	var g := Gradient.new()
	g.set_color(0, Color(lo, lo, lo))
	g.set_color(1, Color.WHITE)
	t.color_ramp = g
	return t


static func _noise_tex(freq: float, size: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = fn
	return t


# --- Road and verges -----------------------------------------------------------------------

## How far the verge rises above the road: a kerb and pavement in town, none elsewhere
## (the tunnel's and bridges' paved strips are flush, so a car along their walls can't ride
## up a kerb).
static func _kerb(lay: ProceduralTrack.Layout, i: int) -> float:
	return 0.12 if lay.zone[i] == ProceduralTrack.Zone.TOWN and lay.kind[i] == ProceduralTrack.Kind.OPEN else 0.0


## Whether the verge is paved (town, tunnel and bridges) rather than gravel.
static func _paved(lay: ProceduralTrack.Layout, i: int) -> bool:
	return lay.zone[i] == ProceduralTrack.Zone.TOWN or lay.kind[i] != ProceduralTrack.Kind.OPEN


static func _road(root: Node3D, lay: ProceduralTrack.Layout, road_mat: Material, ground_mat: Material,
		body: StaticBody3D) -> void:
	var half := ProceduralTrack.ROAD_HALF
	var road := Strip.new()
	var verge_l := Strip.new()
	var verge_r := Strip.new()
	var style := PackedFloat32Array()
	for i in lay.n:
		var p := lay.pts[i]
		var r := lay.right[i]
		var v := i * ProceduralTrack.STEP
		# Double yellow through the hills and round the blind bends.
		var z := lay.zone[i]
		style.append(1.0 if z == ProceduralTrack.Zone.MOUNTAIN or z == ProceduralTrack.Zone.FOREST and absf(lay.curv[i]) > 1.0 / 150.0 else 0.0)
		road.rows.append(PackedVector3Array([p - r * half, p + r * half]))
		road.uvs.append(PackedVector2Array([Vector2(-half, v), Vector2(half, v)]))
		road.colors.append(PackedColorArray([Color.WHITE, Color.WHITE]))
		var kerb := _kerb(lay, i)
		var paved := _paved(lay, i)
		var vc := Color(0, 1, 0) if paved else Color(1, 0, 0)
		var e := lay.edge[i]
		for s: float in [-1.0, 1.0]:
			var inner := p + r * half * s
			# A sloped kerb a wheel rolls up, not a step that trips the car.
			var top := inner + r * s * (0.45 if kerb > 0.0 else 0.0) + lay.up[i] * kerb
			var outer := p + r * e * s + lay.up[i] * (kerb if paved else -0.12)
			var pts := PackedVector3Array([inner, top, outer])
			var cols := PackedColorArray([vc, vc, vc])
			var st := verge_r if s > 0.0 else verge_l
			if s < 0.0:
				pts.reverse()
			st.rows.append(pts)
			st.uvs.append(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
			st.colors.append(cols)
	# Held a few nodes either side so it doesn't flicker on and off.
	var raw := style.duplicate()
	for i in lay.n:
		for k in range(-3, 4):
			style[i] = maxf(style[i], raw[lay.idx(i + k)])
	for st in [road, verge_l, verge_r]:
		st.compute_normals()
	var faces := PackedVector3Array()
	var surf := PackedByteArray()
	var all := func(_i: int) -> bool: return true
	_emit_strip(root, road, lay, all, road_mat, true, faces, surf, S_ASPHALT, style)
	for st in [verge_l, verge_r]:
		_emit_strip(root, st, lay, all, ground_mat, true, faces, surf, S_GRAVEL)
	# Pavements: concrete, not gravel.
	var tex := PackedInt32Array()
	for k in surf.size():
		tex.append({S_ASPHALT: 0, S_GRAVEL: 1, S_CONCRETE: 2}.get(surf[k], 3))
	_add_shape(body, faces, surf, tex)


## Meshes `st` in chunks of CHUNK nodes (so each can be culled), skipping the segments
## `keep` rejects, and appends its triangles to `faces` for collision (surface `code` each;
## verges pick gravel or concrete from their vertex colour). `style` fills UV2.x per row.
static func _emit_strip(parent: Node3D, st: Strip, lay: ProceduralTrack.Layout, keep: Callable, mat: Material,
		shadows: bool, faces: PackedVector3Array, surf: PackedByteArray, code: int,
		style := PackedFloat32Array(), collide := Vector2i(0, 999)) -> void:
	var n := st.rows.size()
	for c0 in range(0, n, CHUNK):
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var cols_n := st.rows[0].size()
		var row_base := {}
		for i in range(c0, mini(c0 + CHUNK, n)):
			if not keep.call(i):
				continue
			for ii in [i, (i + 1) % n]:
				if row_base.has(ii):
					continue
				row_base[ii] = verts.size()
				verts.append_array(st.rows[ii])
				nrms.append_array(st.normals[ii])
				cols.append_array(st.colors[ii])
				var u := st.uvs[ii].duplicate()
				if ii < i:   # the lap's last segment: carry the distance on past its end
					for k in u.size():
						u[k].y += n * ProceduralTrack.STEP
				uvs.append_array(u)
				for k in cols_n:
					uv2.append(Vector2(style[ii] if style.size() > 0 else 0.0, 0.0))
			var a: int = row_base[i]
			var b: int = row_base[(i + 1) % n]
			for k in cols_n - 1:
				# Left-near, right-near, right-far, left-far; Godot's front faces wind clockwise.
				var q := [a + k, a + k + 1, b + k + 1, b + k]
				idx.append_array([q[0], q[2], q[1], q[0], q[3], q[2]])
				if k >= collide.x and k < collide.y:
					var qa := [verts[q[0]], verts[q[1]], verts[q[2]], verts[q[3]]]
					faces.append_array([qa[0], qa[2], qa[1], qa[0], qa[3], qa[2]])
					var sc := code
					if code == S_GRAVEL and cols[q[0]].g > 0.5:
						sc = S_CONCRETE
					surf.append_array([sc, sc])
		if idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## The track's solid scenery (tunnel, bridges, rails, buildings, trunks): on the layer the
## NFS3 tracks use for theirs.
static func scenery_body(root: Node3D) -> StaticBody3D:
	var b := root.get_node_or_null("Scenery") as StaticBody3D
	if b == null:
		b = StaticBody3D.new()
		b.name = "Scenery"
		b.collision_layer = Nfs3TrackBuilder.SCENERY_LAYER
		b.collision_mask = 0
		root.add_child(b)
	return b


## Makes `mesh` solid (both sides of every face).
static func solid(root: Node3D, mesh: Mesh) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	scenery_body(root).add_child(cs)


static func _add_shape(body: StaticBody3D, faces: PackedVector3Array, surf: PackedByteArray,
		tex: PackedInt32Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	TrackSurface.tag(cs, surf, tex)


# --- The land along the road -----------------------------------------------------------------

## How far out the cross-section reaches on side `s` of node `i`: short of the centre of a
## tight bend, so the strips on its inside don't fold over each other.
static func _reach(lay: ProceduralTrack.Layout, i: int, s: float) -> float:
	var r := REACH
	var k := lay.curv[i] * s
	if k > 0.0:
		r = minf(r, 0.8 / k - lay.edge[i])
	return maxf(r, 3.0)


static func _sides(root: Node3D, lay: ProceduralTrack.Layout, mat: Material, body: StaticBody3D) -> void:
	var faces := PackedVector3Array()
	var surf := PackedByteArray()
	for s: float in [-1.0, 1.0]:
		var st := Strip.new()
		for i in lay.n:
			var p := lay.pts[i]
			var fr := lay.flat_right[i] * s
			var e := lay.edge[i]
			var scale := _reach(lay, i, s) / REACH
			var row := PackedVector3Array()
			var cols := PackedColorArray()
			for dd: float in DD:
				var d := e + dd * scale
				var q := p + fr * d
				q.y = lay.side_y(i, s, d)
				if dd == 0.0:
					# Meet the verge exactly.
					q = p + lay.right[i] * e * s + lay.up[i] * (_kerb(lay, i) if _paved(lay, i) else -0.12)
				row.append(q)
				cols.append(Color(0.6, 0, 0) if dd == 0.0 and not _paved(lay, i) else Color(0, 0, 0))
			if s < 0.0:
				row.reverse()
				cols.reverse()
			st.rows.append(row)
			st.colors.append(cols)
			var uv := PackedVector2Array()
			uv.resize(DD.size())
			st.uvs.append(uv)
		st.compute_normals()
		var keep := func(i: int) -> bool:
			return lay.kind[i] == ProceduralTrack.Kind.OPEN or lay.kind[lay.idx(i + 1)] == ProceduralTrack.Kind.OPEN
		# There are no invisible walls: a car can drive out over all of it.
		_emit_strip(root, st, lay, keep, mat, false, faces, surf, S_GRASS)
	var tex := PackedInt32Array()
	tex.resize(surf.size())
	tex.fill(3)
	_add_shape(body, faces, surf, tex)


## The ground at (x, z) as the terrain grid shapes it: the side strips' profile near the
## road (a little below it, so the grid never pokes through them), over the tunnel the
## hill, under a bridge the valley, and the natural land further out. `erode` m: the
## profile is taken that much nearer the road, so a grid triangle reaching from the road
## up a cutting stays under the strip that follows the cutting's foot.
static func ground_y(lay: ProceduralTrack.Layout, x: float, z: float, erode := 0.0) -> float:
	var nat := lay.natural(x, z)
	var i := lay.closest(x, z)
	if i < 0:
		return nat
	var v := Vector3(x, 0.0, z) - Vector3(lay.pts[i].x, 0.0, lay.pts[i].z)
	if lay.kind[i] != ProceduralTrack.Kind.OPEN:
		# Just outside the tunnel or bridge: the open road's cutting or bank.
		var j := lay.idx(i + (1 if v.dot(lay.fwd[i]) > 0.0 else -1))
		if lay.kind[j] == ProceduralTrack.Kind.OPEN:
			i = j
			v = Vector3(x, 0.0, z) - Vector3(lay.pts[i].x, 0.0, lay.pts[i].z)
	var lat := v.dot(lay.flat_right[i])
	var d := absf(lat)
	var s := signf(lat) if lat != 0.0 else 1.0
	var e := lay.edge[i]
	if d > e + REACH + 4.0:
		return nat
	match lay.kind[i]:
		ProceduralTrack.Kind.TUNNEL:
			# A slot under the tube, so no grid triangle ramps up through it; the hillside
			# over the tunnel is its own strip (see _hill_over).
			if d < e + CELL * 1.3:
				return lay.pts[i].y - 2.0
			return maxf(nat, _hill_min(lay, i))
		ProceduralTrack.Kind.BRIDGE:
			return minf(nat, lay.pts[i].y - DECK - 2.5)
	var prof := lay.side_y(i, s, maxf(d - erode * clampf((e + REACH - d) / 15.0, 0.0, 1.0), 0.0))
	var drop := lerpf(1.0, 0.15, clampf((d - e) / REACH, 0.0, 1.0))
	if d < e:
		drop = 0.8
	return minf(nat, prof) - drop


## The height of the ground a prop stands on at (x, z): the strips along the road where
## they reach, the terrain grid beyond.
static func surface_y(lay: ProceduralTrack.Layout, x: float, z: float) -> float:
	var i := lay.closest(x, z)
	if i >= 0 and lay.kind[i] == ProceduralTrack.Kind.TUNNEL:
		return maxf(lay.natural(x, z), _hill_min(lay, i))
	if i >= 0 and lay.kind[i] == ProceduralTrack.Kind.OPEN:
		var lat := (Vector3(x, 0.0, z) - Vector3(lay.pts[i].x, 0.0, lay.pts[i].z)).dot(lay.flat_right[i])
		var s := 1.0 if lat >= 0.0 else -1.0
		if absf(lat) <= lay.edge[i] + _reach(lay, i, s):
			return lay.side_y(i, s, absf(lat))
	return ground_y(lay, x, z)


# --- Terrain grid and mountains --------------------------------------------------------------

static func _terrain(root: Node3D, lay: ProceduralTrack.Layout, mat: Material, body: StaticBody3D) -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in lay.pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2.ONE * MARGIN
	hi += Vector2.ONE * MARGIN
	var cells := Vector2i(ceili((hi.x - lo.x) / CELL), ceili((hi.y - lo.y) / CELL))
	cells = (cells + Vector2i.ONE * (GRID_CHUNK - 1)) / GRID_CHUNK * GRID_CHUNK
	var w := cells.x + 1
	var h := PackedFloat32Array()
	h.resize(w * (cells.y + 1))
	for gz in cells.y + 1:
		for gx in w:
			h[gz * w + gx] = ground_y(lay, lo.x + gx * CELL, lo.y + gz * CELL, CELL * 1.5)
	var get_h := func(gx: int, gz: int) -> float:
		return h[clampi(gz, 0, cells.y) * w + clampi(gx, 0, cells.x)]
	var black := Color(0, 0, 0)
	var faces := PackedVector3Array()
	for cz in range(0, cells.y, GRID_CHUNK):
		for cx in range(0, cells.x, GRID_CHUNK):
			var verts := PackedVector3Array()
			var nrms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			for gz in range(cz, cz + GRID_CHUNK + 1):
				for gx in range(cx, cx + GRID_CHUNK + 1):
					verts.append(Vector3(lo.x + gx * CELL, get_h.call(gx, gz), lo.y + gz * CELL))
					var dx: float = get_h.call(gx + 1, gz) - get_h.call(gx - 1, gz)
					var dz: float = get_h.call(gx, gz + 1) - get_h.call(gx, gz - 1)
					nrms.append(Vector3(-dx, 2.0 * CELL, -dz).normalized())
					cols.append(black)
			var row := GRID_CHUNK + 1
			for gz in GRID_CHUNK:
				for gx in GRID_CHUNK:
					var a := gz * row + gx
					_quad_up(idx, verts, a, a + 1, a + row + 1, a + row)
			_add_mesh(root, verts, nrms, cols, idx, mat, false)
			for k in idx:
				faces.append(verts[k])
	# Solid as far as a car can get before the race puts it back (TrackPath.lost_margin).
	var surf := PackedByteArray()
	surf.resize(faces.size() / 3)
	surf.fill(S_GRASS)
	var tex := PackedInt32Array()
	tex.resize(surf.size())
	tex.fill(3)
	_add_shape(body, faces, surf, tex)
	_mountains(root, lay, mat, lo, hi)


## Two triangles over the quad a-b-c-d (in either winding), front faces upwards.
static func _quad_up(idx: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, d: int) -> void:
	var nrm := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if nrm.y > 0.0:
		idx.append_array([a, c, b, a, d, c])
	else:
		idx.append_array([a, b, c, a, c, d])


static func _add_mesh(parent: Node3D, verts: PackedVector3Array, nrms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array, mat: Material, shadows: bool) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A ring of land from under the grid's edge out to the horizon, where the mountains are.
static func _mountains(root: Node3D, lay: ProceduralTrack.Layout, mat: Material, lo: Vector2, hi: Vector2) -> void:
	var c := (lo + hi) * 0.5
	var r0 := minf(hi.x - lo.x, hi.y - lo.y) * 0.5 - CELL * 2.0
	var rings := PackedFloat32Array([r0, r0 + 150.0, r0 + 350.0, r0 + 650.0, r0 + 1000.0, r0 + 1450.0,
		r0 + 2000.0, r0 + 2700.0, r0 + 3600.0])
	const SEGS := 160
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for r in rings:
		for k in SEGS:
			var a := TAU * k / SEGS
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			var y := lay.natural(x, z)
			var inside := x > lo.x + CELL and x < hi.x - CELL and z > lo.y + CELL and z < hi.y - CELL
			if inside:
				y -= 8.0   # tucked under the grid
			verts.append(Vector3(x, y, z))
			cols.append(Color(0, 0, 0))
	var nrms := PackedVector3Array()
	nrms.resize(verts.size())
	var idx := PackedInt32Array()
	for ri in rings.size() - 1:
		for k in SEGS:
			var a := ri * SEGS + k
			var b := ri * SEGS + (k + 1) % SEGS
			_quad_up(idx, verts, a, b, b + SEGS, a + SEGS)
	# Smooth normals from the faces round each vertex.
	for t in range(0, idx.size(), 3):
		var f := (verts[idx[t + 2]] - verts[idx[t]]).cross(verts[idx[t + 1]] - verts[idx[t]])
		for q in 3:
			nrms[idx[t + q]] += f
	for k in nrms.size():
		nrms[k] = nrms[k].normalized()
	var mi := _add_mesh(root, verts, nrms, cols, idx, mat, false)
	mi.extra_cull_margin = 200.0


static func _water(root: Node3D, lay: ProceduralTrack.Layout, fine: NoiseTexture2D) -> void:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.2, 0.23)
	wm.roughness = 0.06
	wm.metallic = 0.2
	wm.metallic_specular = 0.8
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	nt.noise = fine.noise
	wm.normal_enabled = true
	wm.normal_texture = nt
	wm.normal_scale = 0.35
	wm.uv1_triplanar = true
	wm.uv1_world_triplanar = true
	wm.uv1_scale = Vector3.ONE / 14.0
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (lay.extent * 2.0 + MARGIN * 2.0 + 400.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = wm
	mi.position = Vector3(lay.centre.x, lay.water, lay.centre.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# --- Tunnel ----------------------------------------------------------------------------------

## The tunnel's cross-section, (across, up) from the road's centre: walkway kerb, walls, and
## an arched roof.
static func _tunnel_profile(e: float) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(-e, 0.0), Vector2(-e, TUNNEL_WALL)])
	for k in range(1, 10):
		var a := PI * (1.0 - k / 10.0)
		out.append(Vector2(cos(a) * e, TUNNEL_WALL + sin(a) * TUNNEL_ROOF))
	out.append_array([Vector2(e, TUNNEL_WALL), Vector2(e, 0.0)])
	return out


static func _tunnels(root: Node3D, lay: ProceduralTrack.Layout, concrete: StandardMaterial3D, ground_mat: Material) -> void:
	var tube_mat := concrete.duplicate() as StandardMaterial3D
	tube_mat.albedo_color = Color(0.8, 0.78, 0.72)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1.0, 0.85, 0.55)
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.35, 0.12, 2.4)
	for run in ProceduralTrack._runs(lay.kind, ProceduralTrack.Kind.TUNNEL):
		var a: int = run[0]
		var count: int = run[1]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lamps: Array[Transform3D] = []
		for k in count - 1:
			var i := lay.idx(a + k)
			var j := lay.idx(i + 1)
			var pi := _tunnel_ring(lay, i)
			var pj := _tunnel_ring(lay, j)
			for m in pi.size() - 1:
				var shade := Color(0.55, 0.55, 0.55) if m == 0 or m == pi.size() - 2 else Color.WHITE
				var axis := (lay.pts[i] + lay.pts[j]) * 0.5 + lay.up[i] * TUNNEL_WALL
				_face(st, [pi[m], pi[m + 1], pj[m + 1], pj[m]], axis, shade)
			if k % 2 == 0:
				for side: float in [-1.0, 1.0]:
					var at := lay.pts[i] + lay.right[i] * side * 2.2 + lay.up[i] * (TUNNEL_WALL + TUNNEL_ROOF * 0.93)
					lamps.append(Transform3D(Basis.looking_at(lay.fwd[i], lay.up[i]), at))
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		solid(root, mi.mesh)
		mi.material_override = tube_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		root.add_child(mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lamp
		mm.instance_count = lamps.size()
		for li in lamps.size():
			mm.set_instance_transform(li, lamps[li])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = lamp_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		_hill_over(root, lay, a, count, ground_mat)
		_portal(root, lay, a, -1.0, concrete)
		_portal(root, lay, lay.idx(a + count - 1), 1.0, concrete)


## The lowest the hillside over the tunnel at node `i` may come: clear of its roof.
static func _hill_min(lay: ProceduralTrack.Layout, i: int) -> float:
	return lay.pts[i].y + TUNNEL_WALL + TUNNEL_ROOF + 2.0


## The hillside over a tunnel run from node `a`, `count` nodes long: the natural land,
## sampled finely across the slot the terrain grid leaves along the tunnel.
static func _hill_over(root: Node3D, lay: ProceduralTrack.Layout, a: int, count: int, mat: Material) -> void:
	var st := Strip.new()
	var half := lay.edge[a] + CELL * 2.6
	const COLS := 16
	for k in count:
		var i := lay.idx(a + k)
		var row := PackedVector3Array()
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for c in COLS + 1:
			var lat := -half + 2.0 * half * c / COLS
			var q := lay.pts[i] + lay.flat_right[i] * lat
			q.y = maxf(lay.natural(q.x, q.z), _hill_min(lay, i))
			row.append(q)
			cols.append(Color(0, 0, 0))
			uvs.append(Vector2.ZERO)
		st.rows.append(row)
		st.colors.append(cols)
		st.uvs.append(uvs)
	st.compute_normals()
	var keep := func(k: int) -> bool: return k < count - 1
	_emit_strip(root, st, lay, keep, mat, false, PackedVector3Array(), PackedByteArray(), 0, PackedFloat32Array(),
		Vector2i(0, 0))


static func _tunnel_ring(lay: ProceduralTrack.Layout, i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in _tunnel_profile(lay.edge[i]):
		out.append(lay.pts[i] + lay.right[i] * q.x + lay.up[i] * q.y)
	return out


## Appends quad `q` (4 corners in order round it) facing `towards` a point in front of it.
static func _face(st: SurfaceTool, q: Array, towards: Vector3, color := Color.WHITE, flip := false) -> void:
	var nrm: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
	var c: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
	var facing := nrm.dot(towards - c) > 0.0
	if flip:
		facing = not facing
	var order := [0, 2, 1, 0, 3, 2] if facing else [0, 1, 2, 0, 2, 3]
	st.set_color(color)
	for k in order:
		st.add_vertex(q[k])


## A concrete face across the tunnel's mouth at node `i`, up to the hillside over it, with
## the arch cut out. `dir` -1 faces back down the road (the entrance), +1 on (the exit).
static func _portal(root: Node3D, lay: ProceduralTrack.Layout, i: int, dir: float, concrete: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := lay.pts[i]
	var e := lay.edge[i]
	var r := lay.right[i]
	var u := lay.up[i]
	var front := p + lay.fwd[i] * dir * 20.0
	var span := e + 24.0
	# Across: 2 m strips outside the arch, finer ones over it.
	var xs := PackedFloat32Array()
	for k in 13:
		xs.append(-span + k * 2.0)
	for k in range(1, 20):
		xs.append(-e + e * 2.0 * k / 20.0)
	for k in 13:
		xs.append(e + k * 2.0)
	for xi in xs.size() - 1:
		var bottom := []
		var top := []
		for xx: float in [xs[xi], xs[xi + 1]]:
			var ax := absf(xx)
			var lo := -2.0
			if ax < e:
				var t := ax / e
				lo = TUNNEL_WALL + TUNNEL_ROOF * sqrt(maxf(1.0 - t * t, 0.0)) if ax > 0.0 else TUNNEL_WALL + TUNNEL_ROOF
				lo = minf(lo, TUNNEL_WALL + TUNNEL_ROOF)
			var w := p + r * xx
			var hill := lay.natural(w.x, w.z) - p.y
			var hi := maxf(hill, TUNNEL_WALL + TUNNEL_ROOF + 2.0) + 1.0
			bottom.append(w + u * lo)
			top.append(Vector3(w.x, p.y + hi, w.z))
		_face(st, [bottom[0], bottom[1], top[1], top[0]], front)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	solid(root, mi.mesh)
	mi.material_override = concrete
	root.add_child(mi)


# --- Bridges ---------------------------------------------------------------------------------

static func _bridges(root: Node3D, lay: ProceduralTrack.Layout, concrete: Material, ground_mat: Material) -> void:
	for run in ProceduralTrack._runs(lay.kind, ProceduralTrack.Kind.BRIDGE):
		var a: int = lay.idx(run[0] - 1)
		var count: int = run[1] + 2
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in count - 1:
			var i := lay.idx(a + k)
			var j := lay.idx(i + 1)
			var below := (lay.pts[i] + lay.pts[j]) * 0.5 + Vector3.DOWN * 30.0
			for s: float in [-1.0, 1.0]:
				# Parapet (inner face, top, outer face down past the deck) then the soffit.
				var prof := [Vector2(lay.edge[i], 0.0), Vector2(lay.edge[i], 1.05),
					Vector2(lay.edge[i] + 0.45, 1.05), Vector2(lay.edge[i] + 0.45, -DECK)]
				for m in prof.size() - 1:
					var q := [_at(lay, i, s, prof[m]), _at(lay, i, s, prof[m + 1]),
						_at(lay, j, s, prof[m + 1]), _at(lay, j, s, prof[m])]
					var inward := lay.pts[i] + lay.up[i] * 5.0 if m == 0 else \
						(lay.pts[i] + lay.right[i] * s * 60.0 + lay.up[i] * (20.0 if m == 1 else 0.0))
					_face(st, q, inward, Color(0.8, 0.8, 0.8) if m == 2 else Color.WHITE)
			var ee := lay.edge[i] + 0.45
			_face(st, [_at(lay, i, -1.0, Vector2(ee, -DECK)), _at(lay, i, 1.0, Vector2(ee, -DECK)),
				_at(lay, j, 1.0, Vector2(ee, -DECK)), _at(lay, j, -1.0, Vector2(ee, -DECK))], below, Color(0.6, 0.6, 0.6))
			# Piers down to the valley floor every 30 m.
			if k % 5 == 3 and k < count - 3:
				var foot := lay.natural(lay.pts[i].x, lay.pts[i].z) - 3.0
				for s: float in [-1.0, 1.0]:
					var c := lay.pts[i] + lay.flat_right[i] * s * (ProceduralTrack.ROAD_HALF - 2.0)
					_box(st, c + Vector3.DOWN * DECK, foot, 1.0, lay.fwd[i], lay.flat_right[i])
				_box(st, lay.pts[i] + Vector3.DOWN * (DECK + 0.1), lay.pts[i].y - DECK - 1.6, ProceduralTrack.ROAD_HALF + 0.5,
					lay.fwd[i], lay.flat_right[i], 1.0)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		solid(root, mi.mesh)
		mi.material_override = concrete
		root.add_child(mi)
		# The banks' ends facing the gap.
		_abutment(root, lay, lay.idx(run[0]), 1.0, ground_mat)
		_abutment(root, lay, lay.idx(run[0] + run[1] - 1), -1.0, ground_mat)


static func _at(lay: ProceduralTrack.Layout, i: int, s: float, q: Vector2) -> Vector3:
	return lay.pts[i] + lay.right[i] * s * q.x + lay.up[i] * q.y


## A vertical box from `top` down to height `foot`, `half` wide across the road and
## `half_along` along it.
static func _box(st: SurfaceTool, top: Vector3, foot: float, half: float, fwd: Vector3, right: Vector3,
		half_along := 0.8) -> void:
	var c := [top - right * half - fwd * half_along, top + right * half - fwd * half_along,
		top + right * half + fwd * half_along, top - right * half + fwd * half_along]
	var centre := Vector3(top.x, (top.y + foot) * 0.5, top.z)
	for k in 4:
		var a: Vector3 = c[k]
		var b: Vector3 = c[(k + 1) % 4]
		var q := [a, b, Vector3(b.x, foot, b.z), Vector3(a.x, foot, a.z)]
		_face(st, q, centre, Color.WHITE, true)
	_face(st, [c[0], c[1], c[2], c[3]], centre, Color.WHITE, true)


## Closes the end of the embankment at node `i`, the bridge's first or last, from the
## road's cross-section down to the ground; `dir` points out over the gap.
static func _abutment(root: Node3D, lay: ProceduralTrack.Layout, i: int, dir: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := lay.pts[i]
	var front := p + lay.fwd[i] * dir * 30.0
	var span := lay.edge[i] + REACH
	var x := -span
	const STEP_X := 2.0
	while x < span - 0.01:
		var t := []
		var b := []
		for xx: float in [x, x + STEP_X]:
			var s := signf(xx) if xx != 0.0 else 1.0
			var d := absf(xx)
			var w := p + lay.flat_right[i] * xx
			var y := lay.side_y(i, s, maxf(d, lay.edge[i])) if d > lay.edge[i] else lay.road_y(i, s, d) - 0.1
			t.append(Vector3(w.x, y, w.z))
			b.append(Vector3(w.x, minf(lay.natural(w.x, w.z), y) - 3.0, w.z))
		_face(st, [t[0], t[1], b[1], b[0]], front, Color(0, 0, 0))
		x += STEP_X
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	solid(root, mi.mesh)
	mi.material_override = mat
	root.add_child(mi)

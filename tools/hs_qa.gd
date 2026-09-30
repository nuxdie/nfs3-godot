extends Node
## Visual QA of a High Stakes track: `godot --path . -- --hsqa <track id> [--n=K] [--noshots]`
## Photographs K points round the lap three ways (clean road view, the same with collision
## overlaid, and overhead with collision overlaid) into shots/qa/, and prints what stands in
## the drivable corridor: invisible walls, solid scenery, posts, props.
## Overlay colours: red = invisible walls, cyan = solid scenery collision, green = drivable
## road collision, magenta = knockable props, orange = guardrails, yellow = HS physics props.

var w: TrackWorld
var overlay := Node3D.new()
var tinted: Array[GeometryInstance3D] = []
var tints: Array[Material] = []
var node_grid := {}


func _ready() -> void:
	_run.call_deferred()


func _mat(c: Color, depth := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.no_depth_test = not depth
	m.render_priority = 10
	return m


func _faces_mesh(faces: PackedVector3Array, m: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	for p in faces:
		v.append(xf * p)
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _body_overlay(body: Node, c: Color) -> void:
	if body == null:
		return
	for cs in body.get_children():
		if cs is CollisionShape3D and cs.shape is ConcavePolygonShape3D:
			overlay.add_child(_faces_mesh(cs.shape.get_faces(), _mat(c), cs.global_transform))
		elif cs is CollisionShape3D and cs.shape is BoxShape3D:
			var bm := BoxMesh.new()
			bm.size = cs.shape.size
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = _mat(c)
			mi.global_transform = cs.global_transform
			overlay.add_child(mi)


func _tint_tree(n: Node, c: Color) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			tinted.append(ch)
			tints.append(_mat(c))
		_tint_tree(ch, c)


func _set_overlay(on: bool) -> void:
	overlay.visible = on
	for i in tinted.size():
		tinted[i].material_overlay = tints[i] if on else null


func _run() -> void:
	get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var id: String = pos[0]
	var n_shots := 10
	var at := []
	for a: String in args:
		if a.begins_with("--n="):
			n_shots = int(a.get_slice("=", 1))
		if a.begins_with("--at="):
			for s in a.get_slice("=", 1).split(","):
				at.append(int(s))
	w = TrackWorld.load_track(id)
	if w.track == null:
		print("QA %s: failed to load" % id)
		get_tree().quit(1)
		return
	add_child(w.root)
	add_child(overlay)
	w.light(self, false, false, get_viewport())
	for k in 3:
		await get_tree().physics_frame
	_build_grid()

	_body_overlay(w.root.get_node_or_null("Walls"), Color(1, 0, 0, 0.35))
	_body_overlay(w.root.get_node_or_null("Scenery"), Color(0, 1, 1, 0.3))
	_body_overlay(w.root.get_node_or_null("Road"), Color(0, 1, 0, 0.12))
	var props := w.root.get_node_or_null("Props")
	if props:
		_tint_tree(props, Color(1, 0, 1, 0.55))
	var rails := w.root.get_node_or_null("Guardrails")
	if rails:
		_tint_tree(rails, Color(1, 0.5, 0, 0.5))

	_report_walls()
	_report_scenery()
	_report_props(props)
	_report_physics_props()
	_report_textures()
	_report_seams()
	_scan_surface()
	for v in 3:
		_seam_variant(v)

	if "--noshots" in args:
		get_tree().quit()
		return
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var dir := "res://shots/qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := w.path
	var spots := at if at.size() > 0 else range(n_shots).map(
			func(s: int) -> int: return int((s + 0.5) / n_shots * path.size()) % path.size())
	var bg := w.env.background_mode
	for s in spots.size():
		var i: int = spots[s]
		var f := float(i) / path.size()
		cam.far = 6000.0
		w.env.background_mode = bg
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 70.0
		cam.global_position = path.points[path.idx(i - 1)] + Vector3.UP * 2.2
		cam.look_at(path.points[path.idx(i + 7)] + Vector3.UP * 1.0, Vector3.UP)
		for on in [false, true]:
			_set_overlay(on)
			await _settle()
			_save("%s/%s_%s%02d_%s.png" % [dir, id, "at" if at.size() > 0 else "", s, "road_qa" if on else "road"])
		# Overhead, the road running up the picture.
		var fwd := path.points[path.idx(i + 2)] - path.points[path.idx(i - 2)]
		fwd.y = 0.0
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 110.0
		cam.far = 300.0
		w.env.background_mode = Environment.BG_COLOR
		w.env.background_color = Color(0.1, 0.1, 0.12)
		cam.global_position = path.points[path.idx(i + 5)] + Vector3.UP * 150.0
		cam.look_at(path.points[path.idx(i + 5)], fwd.normalized())
		_set_overlay(true)
		await _settle()
		_save("%s/%s_%s%02d_top.png" % [dir, id, "at" if at.size() > 0 else "", s])
		print("QA shot %d at node %d (%.3f)" % [s, i, f])
	get_tree().quit()


func _settle() -> void:
	for k in 6:
		await get_tree().process_frame


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(file)


# ------------------------------------------------------------------ geometry helpers

func _build_grid() -> void:
	for i in w.path.size():
		var c := Vector2i(floori(w.path.points[i].x / 25.0), floori(w.path.points[i].z / 25.0))
		if not node_grid.has(c):
			node_grid[c] = []
		node_grid[c].append(i)


## [node, lateral, height over the node] for a point, the nearest node in 3D.
func _locate(p: Vector3) -> Array:
	var best := -1
	var bd := INF
	var c := Vector2i(floori(p.x / 25.0), floori(p.z / 25.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i: int in node_grid.get(c + Vector2i(dx, dz), []):
				var d := w.path.points[i].distance_squared_to(p)
				if d < bd:
					bd = d
					best = i
	if best < 0:
		return [-1, INF, INF]
	var d := p - w.path.points[best]
	return [best, d.dot(w.path.rights[best]), d.dot(w.path.ups[best])]


func _inside(loc: Array, margin: float) -> bool:
	var i: int = loc[0]
	return i >= 0 and loc[1] > -w.path.left_width[i] + margin and loc[1] < w.path.right_width[i] - margin


func _where(i: int) -> String:
	return "node %4d (%.3f)" % [i, float(i) / w.path.size()]


## Prints clusters of hits (by node) as runs.
func _print_runs(tag: String, hits: Dictionary) -> void:
	var nodes := hits.keys()
	nodes.sort()
	var run: Array = []
	var runs := []
	for i: int in nodes:
		if run.size() > 0 and i - run[-1] > 3:
			runs.append(run)
			run = []
		run.append(i)
	if run.size() > 0:
		runs.append(run)
	print("QA %s %s: %d spots" % [w.id, tag, runs.size()])
	for r: Array in runs:
		var lats := []
		for i: int in r:
			lats.append_array(hits[i])
		var lo: float = lats.min()
		var hi: float = lats.max()
		print("   %s..%d  lateral %.1f..%.1f m  (walls -%.1f/+%.1f)" % [_where(r[0]), r[-1], lo, hi,
			w.path.left_width[r[0]], w.path.right_width[r[0]]])


# ------------------------------------------------------------------ reports

## Invisible wall faces standing well inside the virtual road's own walls.
func _report_walls() -> void:
	var body := w.root.get_node_or_null("Walls")
	var hits := {}
	var total := 0
	if body:
		for cs in body.get_children():
			if not cs.shape is ConcavePolygonShape3D:
				continue
			var f: PackedVector3Array = cs.shape.get_faces()
			for k in range(0, f.size(), 6):
				total += 1
				# Bottom edge a..b, at the road's level plus the wall depth.
				var m := (f[k] + f[k + 1]) * 0.5 + Vector3.UP * Nfs3TrackBuilder.WALL_DEPTH
				var loc := _locate(m)
				if _inside(loc, 1.5) and absf(loc[2]) < 4.0:
					if not hits.has(loc[0]):
						hits[loc[0]] = []
					hits[loc[0]].append(loc[1])
	print("QA %s walls: %d segments" % [w.id, total])
	_print_runs("wall segments inside the road (>1.5 m in from the vroad walls)", hits)


## Solid scenery (car collision) inside the corridor at car height.
func _report_scenery() -> void:
	var body := w.root.get_node_or_null("Scenery")
	var hits := {}
	var posts := {}
	if body == null:
		return
	for cs in body.get_children():
		if cs.shape is ConcavePolygonShape3D:
			var f: PackedVector3Array = cs.shape.get_faces()
			for k in range(0, f.size(), 3):
				for p in [f[k], f[k + 1], f[k + 2], (f[k] + f[k + 1] + f[k + 2]) / 3.0]:
					var loc := _locate(p)
					if _inside(loc, 0.5) and loc[2] > 0.15 and loc[2] < 2.0:
						if not hits.has(loc[0]):
							hits[loc[0]] = []
						hits[loc[0]].append(loc[1])
						break
		elif cs.shape is BoxShape3D:
			var loc := _locate(cs.global_position)
			if _inside(loc, 0.5) and absf(loc[2]) < 3.0:
				if not posts.has(loc[0]):
					posts[loc[0]] = []
				posts[loc[0]].append(loc[1])
	_print_runs("solid scenery faces inside the road at car height", hits)
	_print_runs("trunk/post boxes inside the road", posts)


func _report_props(props: Node) -> void:
	if props == null:
		return
	var n := 0
	var inside := {}
	for p in props.get_children():
		if p is Node3D:
			n += 1
			var loc := _locate(p.global_position)
			if _inside(loc, 0.0):
				if not inside.has(loc[0]):
					inside[loc[0]] = []
				inside[loc[0]].append(loc[1])
	print("QA %s knockable props: %d" % [w.id, n])
	_print_runs("knockable props inside the road", inside)


## Walks the FRD again for the type-6 (physics) extra objects the loader skips the details
## of: where they are, their mass, orientation and size, and what the builder made of them.
func _report_physics_props() -> void:
	var d := FileAccess.get_file_as_bytes(DataPath.find_ci(Game.track_dir(w.id), "tr.frd"))
	var n_blocks := d.decode_u32(28) + 1
	var n_vroad := d.decode_u32(32)
	var p := 36 + n_vroad * Nfs4Track.VROAD_SIZE
	var heads := []
	for bi in n_blocks:
		var h := {"sz": [], "nv": d.decode_u32(p + 88), "nobj": [], "np": d.decode_u32(p + 1412),
			"nx": d.decode_u32(p + 1448), "npo": d.decode_u32(p + 1456), "ns": d.decode_u32(p + 1464),
			"nl": d.decode_u32(p + 1472)}
		for c in 11:
			h.sz.append(d.decode_u32(p + c * 4))
		for c in 4:
			h.nobj.append(d.decode_u32(p + 1380 + c * 8))
		heads.append(h)
		p += Nfs4Track.BLOCK_HEADER_SIZE
	var types := {}
	var phys := []
	for h in heads:
		p += h.nv * 16 + h.np * 24 + h.nx * 20 + h.npo * 20 + h.ns * 16 + h.nl * 16
		for c in 11:
			p += h.sz[c] * Nfs4Track.POLY_SIZE
		for c in 4:
			p = _walk_xobjs(d, p, h.nobj[c], types, phys, false)
	for g in 2:
		p = _walk_xobjs(d, p + 4, d.decode_u32(p), types, phys, true)
	print("QA %s xobj types: %s" % [w.id, types])
	print("QA %s physics props: %d" % [w.id, phys.size()])
	var space := get_viewport().world_3d.direct_space_state
	var props := w.root.get_node_or_null("Props")
	var kinds := {}
	for x in phys:
		var loc := _locate(x.pos)
		var q := PhysicsRayQueryParameters3D.create(x.pos + Vector3.UP * 20.0, x.pos + Vector3.DOWN * 40.0, 1)
		var hit := space.intersect_ray(q)
		var ground: float = hit.position.y if hit else NAN
		var foot: float = x.pos.y + x.min_y
		# What the builder made of it: a knockable prop standing there, solid scenery, or nothing.
		var centre: Vector3 = x.pos + Vector3.UP * (x.min_y + x.h * 0.5)
		var kind := "no collision"
		for pr in props.get_children() if props else []:
			if Vector2(pr.position.x - x.pos.x, pr.position.z - x.pos.z).length() < 1.0:
				kind = "knockable"
		if kind != "knockable":
			var sq := PhysicsShapeQueryParameters3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 0.3
			sq.shape = sph
			sq.transform = Transform3D(Basis(), centre)
			sq.collision_mask = Nfs3TrackBuilder.SCENERY_LAYER
			if space.intersect_shape(sq, 1).size() > 0:
				kind = "SOLID"
		kinds[kind] = kinds.get(kind, 0) + 1
		var tilt := rad_to_deg(x.basis.y.angle_to(Vector3.UP))
		var yaw := rad_to_deg(atan2(x.basis.z.x, x.basis.z.z))
		print("   %s lat %+6.1f  mass %6.1f  size %s  yaw %4.0f tilt %3.0f  mesh h %.2f  foot-ground %+.2f  %s %s" % [
			_where(loc[0]), loc[1], x.mass, x.dims, yaw, tilt, x.h, foot - ground,
			"IN ROAD" if _inside(loc, 0.0) else "", kind])
	print("QA %s physics props became: %s" % [w.id, kinds])


func _walk_xobjs(d: PackedByteArray, p: int, n: int, types: Dictionary, phys: Array, global: bool) -> int:
	var heads := []
	for i in n:
		var q := p + i * Nfs4Track.XOBJ_HEADER_SIZE
		heads.append([d.decode_u32(q), d.decode_u32(q + 32), d.decode_u32(q + 44)])
	p += n * Nfs4Track.XOBJ_HEADER_SIZE
	for hd in heads:
		var key := "%s%d" % ["g" if global else "", hd[0]]
		types[key] = types.get(key, 0) + 1
		var x := {}
		if hd[0] == 3:
			p += 8 + d.decode_u16(p + 4) * 20
		elif hd[0] == 6:
			x.pos = Nfs4Track._point(d, p)
			x.mass = d.decode_float(p + 12)
			var m := []
			for k in 9:
				m.append(d.decode_float(p + 16 + k * 4))
			# Rows as stored, X mirrored like the points.
			x.basis = Basis(Vector3(m[0], -m[1], -m[2]), Vector3(-m[3], m[4], m[5]), Vector3(-m[6], m[7], m[8]))
			x.dims = Vector3(d.decode_float(p + 52), d.decode_float(p + 56), d.decode_float(p + 60)) * Nfs4Track.SCALE
			p += 72
		var verts := Nfs3Track.read_vec3s(d, p, hd[1])
		if hd[0] == 6:
			var lo := INF
			var hi := -INF
			for v in verts:
				lo = minf(lo, v.y * Nfs4Track.SCALE)
				hi = maxf(hi, v.y * Nfs4Track.SCALE)
			x.min_y = lo
			x.h = hi - lo
			phys.append(x)
		p += hd[1] * 16 + hd[2] * Nfs4Track.POLY_SIZE
	return p


## Texture sanity: polys whose texture is stretched far off its image's aspect (a sign the
## uv flags or corner order are wrong), per texture, and texture ids past the archive.
func _report_textures() -> void:
	var t := w.track
	var bad_ids := 0
	var stretch := {}   # qfs index -> [count, worst ratio, example pos]
	var total := 0
	for b in t.blocks:
		var sets := [[b.road, b.verts, Vector3.ZERO]]
		for o in b.objects:
			sets.append([o, b.verts, Vector3.ZERO])
		for x in b.xobjs:
			sets.append([x.polys, x.verts, x.ref])
		for s in sets:
			var verts: PackedVector3Array = s[1]
			for poly: Nfs3Track.Poly in s[0]:
				if poly.tex >= t.textures.size():
					bad_ids += 1
					continue
				var ti: Nfs3Track.TexInfo = t.textures[poly.tex]
				if ti.is_lane:
					continue
				if ti.qfs_index >= t.images.size():
					bad_ids += 1
					continue
				if poly.v[0] >= verts.size() or poly.v[1] >= verts.size() or poly.v[2] >= verts.size() or poly.v[3] >= verts.size():
					continue
				total += 1
				# Edge lengths along the texture's u and v, from the corner uvs.
				var a := verts[poly.v[0]]
				var bb := verts[poly.v[1]]
				var c := verts[poly.v[2]]
				var e01 := a.distance_to(bb)
				var e12 := bb.distance_to(c)
				var du := absf(ti.uv[1].x - ti.uv[0].x) + absf(ti.uv[2].x - ti.uv[1].x)
				if e01 < 0.2 or e12 < 0.2:
					continue
				# Which world edge carries u: the one whose uv changes in x.
				var u_len := e01 if absf(ti.uv[1].x - ti.uv[0].x) > 0.5 else e12
				var v_len := e12 if u_len == e01 else e01
				if du < 0.5:
					continue
				var ratio := (u_len / v_len) / (float(ti.width) / maxf(ti.height, 1))
				var r := maxf(ratio, 1.0 / ratio)
				var e: Array = stretch.get(ti.qfs_index, [0, 0, 1.0, Vector3.ZERO])
				e[1] += 1
				if r > 4.0:
					e[0] += 1
					if r > e[2]:
						e[2] = r
						e[3] = a + s[2]
				stretch[ti.qfs_index] = e
	print("QA %s textures: %d polys, %d with bad texture ids" % [w.id, total, bad_ids])
	var rows := []
	for k in stretch:
		var e: Array = stretch[k]
		if e[0] >= 4 and float(e[0]) / e[1] > 0.5:
			rows.append([k, e])
	rows.sort_custom(func(x, y): return x[1][0] > y[1][0])
	for r in rows.slice(0, 12):
		var e: Array = r[1]
		var loc := _locate(e[3])
		print("   tex %3d (%dx%d): %d/%d polys stretched >4x (worst %.1fx at %s)" % [r[0],
			t.images[r[0]].get_width(), t.images[r[0]].get_height(), e[0], e[1], e[2], _where(loc[0])])


## Texture seams: two polys with the same texture sharing an edge should map it the same way
## along the edge; flipped or turned across it the texture breaks there. Tallied by the pair
## of uv flag sets, so a wrongly decoded flag shows up as one dominant pair.
func _report_seams() -> void:
	var t := w.track
	var by_pair := {}
	var spots := {}
	var shared := 0
	var bad := 0
	for b in t.blocks:
		var chunks := [b.road]
		chunks.append_array(b.objects)
		for polys in chunks:
			var edges := {}
			for poly: Nfs3Track.Poly in polys:
				if poly.tex >= t.textures.size() or t.textures[poly.tex].is_lane:
					continue
				for k in 4:
					var va := poly.v[k]
					var vb := poly.v[(k + 1) % 4]
					if va == vb or va >= b.verts.size() or vb >= b.verts.size():
						continue
					var key := Vector2i(mini(va, vb), maxi(va, vb))
					var ti: Nfs3Track.TexInfo = t.textures[poly.tex]
					var ua: Vector2 = ti.uv[k] if va < vb else ti.uv[(k + 1) % 4]
					var ub: Vector2 = ti.uv[(k + 1) % 4] if va < vb else ti.uv[k]
					if not edges.has(key):
						edges[key] = []
					edges[key].append([ti.qfs_index, ub - ua, poly.flags & Nfs4Track.UV_BITS, b.verts[va]])
			for key in edges:
				var e: Array = edges[key]
				if e.size() != 2 or e[0][0] != e[1][0]:
					continue
				shared += 1
				if (e[0][1] - e[1][1]).length() > 0.01:
					bad += 1
					var pair := "%02x/%02x" % [mini(e[0][2], e[1][2]), maxi(e[0][2], e[1][2])]
					by_pair[pair] = by_pair.get(pair, 0) + 1
					var loc := _locate(e[0][3])
					if loc[0] >= 0:
						if not spots.has(loc[0]):
							spots[loc[0]] = []
						spots[loc[0]].append(loc[1])
	print("QA %s seams: %d of %d shared same-texture edges mismatched; by flag pair %s" % [w.id, bad, shared, by_pair])
	_print_runs("texture seams", spots)


## Uv corners under alternative readings of UV_INVERT: 0 half turn (as the loader), 1 vertical
## flip, 2 horizontal flip.
static func _uvs(flags: int, variant: int) -> PackedVector2Array:
	var c := PackedVector2Array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
	for k in 4:
		var uv := c[k]
		if flags & Nfs4Track.UV_ROTATE:
			uv = Vector2(1.0 - uv.y, uv.x)
		if flags & Nfs4Track.UV_INVERT:
			uv = [Vector2.ONE - uv, Vector2(uv.x, 1.0 - uv.y), Vector2(1.0 - uv.x, uv.y)][variant]
		if flags & Nfs4Track.UV_MIRROR_X:
			uv.x = 1.0 - uv.x
		if flags & Nfs4Track.UV_MIRROR_Y:
			uv.y = 1.0 - uv.y
		c[k] = uv
	return PackedVector2Array([c[1], c[0], c[3], c[2]])


func _seam_variant(variant: int) -> void:
	var t := w.track
	var bad := 0
	var with_inv := 0
	for b in t.blocks:
		var chunks := [b.road]
		chunks.append_array(b.objects)
		for polys in chunks:
			var edges := {}
			for poly: Nfs3Track.Poly in polys:
				if poly.tex >= t.textures.size() or t.textures[poly.tex].is_lane:
					continue
				var uv := _uvs(poly.flags, variant)
				for k in 4:
					var va := poly.v[k]
					var vb := poly.v[(k + 1) % 4]
					if va == vb:
						continue
					var key := Vector2i(mini(va, vb), maxi(va, vb))
					var d: Vector2 = uv[(k + 1) % 4] - uv[k] if va < vb else uv[k] - uv[(k + 1) % 4]
					if not edges.has(key):
						edges[key] = []
					edges[key].append([t.textures[poly.tex].qfs_index, d, poly.flags & Nfs4Track.UV_INVERT])
			for key in edges:
				var e: Array = edges[key]
				if e.size() == 2 and e[0][0] == e[1][0] and (e[0][2] or e[1][2]):
					with_inv += 1
					if (e[0][1] - e[1][1]).length() > 0.01:
						bad += 1
	print("QA %s invert-as-%s: %d of %d edges touching an inverted poly mismatch" % [w.id,
		["half-turn", "v-flip", "h-flip"][variant], bad, with_inv])


## Casts rays down across the road at every node, out to 12 m past the virtual road's walls:
## R where it lands on the drivable surface, T on terrain. Reports
##  - holes: terrain strips between drivable ones inside the walls (walled islands mid-road),
##  - walled asphalt: terrain whose texture is one the road itself uses near its centre,
##    joined to the drivable edge (paved ground the invisible wall shuts off).
func _scan_surface() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var road_body: CollisionObject3D = w.root.get_node("Road")
	var excl := [w.root.get_node("Walls").get_rid()]
	var path := w.path
	var rows := []
	var centre_tex := {}
	for i in path.size():
		var row := []
		var lo := -int(path.left_width[i]) - 12
		var hi := int(path.right_width[i]) + 12
		for lat in range(lo, hi + 1):
			var p := path.points[i] + path.rights[i] * lat
			var q := PhysicsRayQueryParameters3D.create(p + path.ups[i] * 3.0, p - path.ups[i] * 5.0, 1, excl)
			var hit := space.intersect_ray(q)
			var kind := "."
			var tex := -1
			if hit:
				kind = "R" if hit.collider == road_body else "T"
				var cs = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
				if cs and cs.has_meta("texture") and hit.face_index >= 0 and hit.face_index < cs.get_meta("texture").size():
					tex = cs.get_meta("texture")[hit.face_index]
				if kind == "R" and absf(lat) <= 3:
					centre_tex[tex] = centre_tex.get(tex, 0) + 1
			row.append([lat, kind, tex])
		rows.append(row)
	# Road textures: the ones under the middle of the road on at least 2% of the samples.
	var total := 0
	for k in centre_tex:
		total += centre_tex[k]
	var road_tex := {}
	for k in centre_tex:
		if centre_tex[k] > total * 0.02:
			road_tex[k] = true
	print("QA %s road textures: %s" % [w.id, road_tex.keys()])
	var holes := {}
	var walled := {}
	for i in rows.size():
		var row: Array = rows[i]
		var kinds := ""
		for c in row:
			kinds += c[1]
		# Holes: T runs with R on both sides, within the walls.
		var re := RegEx.create_from_string("R(T+)R")
		for m in re.search_all(kinds):
			var a: int = row[m.get_start(1)][0]
			var b: int = row[m.get_end(1) - 1][0]
			if a > -path.left_width[i] and b < path.right_width[i] and b - a + 1 >= 3:
				if not holes.has(i):
					holes[i] = []
				holes[i].append_array([a, b])
		# Walled asphalt: from each outermost R, count road-textured T continuing outwards.
		for dir: int in [-1, 1]:
			var edge := -1
			# the outermost R on this side
			var idxs := range(row.size()) if dir == 1 else range(row.size() - 1, -1, -1)
			for n: int in idxs:
				if row[n][1] == "R":
					edge = n
					break
			if edge < 0:
				continue
			var run := 0
			var n2: int = edge - dir
			while n2 >= 0 and n2 < row.size() and row[n2][1] == "T" and road_tex.has(row[n2][2]):
				run += 1
				n2 -= dir
			if run >= 2:
				if not walled.has(i):
					walled[i] = []
				walled[i].append(float(row[edge][0]) - dir * run)
	_print_runs("holes in the drivable surface (terrain strips >= 3 m wide mid-road)", holes)
	_print_runs("asphalt walled off (road texture past the drivable edge, >= 2 m)", walled)

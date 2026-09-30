extends Node
## Collision QA of a Porsche Unleashed track, headless:
## `godot --headless --path . -s tools/_tmp/pu_probe.gd -- <track id>`
## Scans every virtual road node across its corridor (between its walls) for: wall widths
## that collapse, jump or balloon; holes in the ground collision; steps in it; solid scenery
## at car height; drivable road just past a wall; and gaps under the walls.

var w: TrackWorld
var space: PhysicsDirectSpaceState3D
var wall_rid: RID
var solid_faces := {}   # grid cell -> [[a, b, c, tex name]]
var tex_names: PackedStringArray


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	w = TrackWorld.load_track(id)
	if w.track == null:
		print("PUQA %s: failed to load" % id)
		get_tree().quit(1)
		return
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	space = get_viewport().world_3d.direct_space_state
	wall_rid = (w.root.get_node("Walls") as StaticBody3D).get_rid()
	tex_names = Fsh.load_file(Game.track_dir(id).get_basename() + ".fsh").names

	var path := w.path
	var n := path.size()
	print("PUQA %s: %d nodes, %s, %.0f m, start %d finish %d" % [id, n, "closed" if path.closed else "open",
		path.length, path.start_node, path.finish_node])
	_widths()
	var lane_off := {}
	var buried := {}
	var gapped := {}
	var obstacle := {}
	var past_wall := {}
	var walls := _wall_spans()
	for i in n:
		var p := path.points[i]
		var r := path.rights[i]
		var u := path.ups[i]
		var lw := path.left_width[i]
		var rw := path.right_width[i]
		# The lanes' part of the corridor: is there ground under it, level with the node?
		var ll: float = path.lane_count(i, -1) * path.lane_width_left[i]
		var lr: float = path.lane_count(i, 1) * path.lane_width_right[i]
		var bad := 0
		var tot := 0
		var lat := -maxf(ll, 1.0)
		while lat <= maxf(lr, 1.0):
			tot += 1
			var g := _ray(p + r * lat + u * 3.0, p + r * lat - u * 6.0, 1)
			if g.is_empty() or absf((g.position - p).dot(u)) > 1.0:
				bad += 1
			lat += 1.0
		if bad * 2 > tot:
			_add(lane_off, i, 0.0, float(bad) / tot)
		# Obstacles: collision (other than the walls) in a car-sized box standing on the ground.
		lat = -lw + 0.6
		while lat <= rw - 0.6:
			var top := p + r * lat
			var g := _ray(top + u * 3.0, top - u * 6.0, 1)
			if not g.is_empty():
				var q := PhysicsShapeQueryParameters3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(0.8, 1.0, 0.8)
				q.shape = box
				q.transform = Transform3D(Basis(r, u, r.cross(u)), g.position + u * 1.05)
				q.collision_mask = 1 | Nfs3TrackBuilder.SCENERY_LAYER
				q.exclude = [wall_rid]
				for h in space.intersect_shape(q, 4):
					_add(obstacle, i, lat, 1.0 if h.collider.name == "Terrain" else (2.0 if h.collider.name == "Road" else 3.0))
					break
			lat += 1.0
		# Each wall against the ground just inside it: buried (a car goes over), or a gap under.
		for side in [0, 1]:
			var sg: float = 1.0 if side == 1 else -1.0
			var wd := rw if side == 1 else lw
			var span: Vector2 = walls[side][i]
			var inner := p + r * (wd - 0.5) * sg
			var g := _ray(inner + u * 3.0, inner - u * 20.0, 1)
			if not g.is_empty():
				var gy: float = g.position.y
				if span.y < gy + 1.2:
					_add(buried, i, sg * wd, span.y - gy)
				elif span.x > gy + 0.25:
					_add(gapped, i, sg * wd, span.x - gy)
			var out := p + r * (wd + 2.5) * sg
			var o := _ray(out + u * 2.0, out - u * 2.0, 1)
			if not o.is_empty() and o.collider.name == "Road":
				_add(past_wall, i, sg * (wd + 2.5))
	_runs("lane area not on ground within 1 m of the vroad (vroad off the road)", lane_off)
	_runs("walls buried: top <1.2 m over the ground inside them", buried)
	_runs("walls with a gap under them >0.25 m", gapped)
	_runs("obstacles at car height in the corridor (1 terrain, 2 road, 3 scenery)", obstacle)
	_runs("road surface 2.5 m past a wall", past_wall)
	get_tree().quit()


## Per side (0 left, 1 right), per node: the wall's (bottom, top) y there, from the Walls body.
func _wall_spans() -> Array:
	var out := [[], []]
	var body := w.root.get_node("Walls")
	var n := w.path.size()
	for side in 2:
		var f: PackedVector3Array = body.get_child(side).shape.get_faces()
		for i in n:
			var k: int = mini(i, (f.size() / 6) - 1 if w.path.closed else n - 2) * 6
			var bottom: float = f[k].y if i == k / 6 else f[k + 1].y
			var top: float = f[k + 5].y if i == k / 6 else f[k + 2].y
			out[side].append(Vector2(bottom, top))
	return out


func _ray(a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.exclude = [wall_rid]
	q.hit_back_faces = true
	return space.intersect_ray(q)


func _add(d: Dictionary, i: int, lat: float, v := NAN) -> void:
	if not d.has(i):
		d[i] = []
	d[i].append(Vector2(lat, v))


func _widths() -> void:
	var path := w.path
	var n := path.size()
	var collapsed := {}
	var huge := {}
	var jumps := {}
	var gaps := {}
	var lo := INF
	var hi := 0.0
	for i in n:
		var lw := path.left_width[i]
		var rw := path.right_width[i]
		lo = minf(lo, minf(lw, rw))
		hi = maxf(hi, maxf(lw, rw))
		if lw < 1.0 or rw < 1.0:
			_add(collapsed, i, -lw, rw)
		if lw + rw > 40.0:
			_add(huge, i, -lw, rw)
		if i + 1 < n or path.closed:
			var j := (i + 1) % n
			var dl := absf(path.left_width[j] - lw)
			var dr := absf(path.right_width[j] - rw)
			if dl > 2.0 or dr > 2.0:
				_add(jumps, i, dl, dr)
			var d := path.points[i].distance_to(path.points[j])
			if d > 12.0 or d < 0.2:
				_add(gaps, i, d)
	print("PUQA %s wall widths: %.1f..%.1f m" % [w.id, lo, hi])
	_runs("walls under 1 m from the line", collapsed)
	_runs("corridor over 40 m wide", huge)
	_runs("wall width jumps >2 m node to node", jumps)
	_runs("node spacing outside 0.2..12 m", gaps)


## The opaque scenery triangles (as the builder made them solid), bucketed for lookups.
func _index_solid() -> void:
	var t: Nfs5Track = w.track
	var see := Nfs5TrackBuilder._see_through(t)
	var groups := t.chunks.map(func(c: Dictionary) -> Nfs5Track.Piece: return c.pieces[Nfs5Track.Kind.SCENERY])
	for pc: Nfs5Track.Piece in groups:
		for tri in pc.tex.size():
			if see[pc.tex[tri]] != 0:
				continue
			var a := pc.pos[tri * 3]
			var b := pc.pos[tri * 3 + 1]
			var c := pc.pos[tri * 3 + 2]
			var box := AABB(a, Vector3.ZERO).expand(b).expand(c)
			if box.size.x > 200 or box.size.z > 200:
				continue
			var nm: String = tex_names[pc.tex[tri]] if pc.tex[tri] < tex_names.size() else "#%d" % pc.tex[tri]
			for x in range(floori(box.position.x / 10.0), floori(box.end.x / 10.0) + 1):
				for z in range(floori(box.position.z / 10.0), floori(box.end.z / 10.0) + 1):
					solid_faces.get_or_add(Vector2i(x, z), []).append([a, b, c, nm])


func _solid_tex_near(p: Vector3, reach: float) -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in solid_faces.get(Vector2i(floori(p.x / 10.0), floori(p.z / 10.0)), []):
		var q := Geometry3D.get_closest_point_to_segment(p, f[0], f[1])
		var dd := minf(q.distance_to(p), Geometry3D.get_closest_point_to_segment(p, f[1], f[2]).distance_to(p))
		dd = minf(dd, Geometry3D.get_closest_point_to_segment(p, f[2], f[0]).distance_to(p))
		var plane := Plane(f[0], f[1], f[2])
		var proj := plane.project(p)
		if Geometry3D.ray_intersects_triangle(proj + plane.normal, -plane.normal, f[0], f[1], f[2]) != null:
			dd = minf(dd, absf(plane.distance_to(p)))
		if dd < reach and not f[3] in out:
			out.append(f[3])
	return out


## Hits clustered into runs of nodes (gaps of up to 3), with their lateral spread and value.
func _runs(tag: String, hits: Dictionary) -> void:
	var nodes := hits.keys()
	nodes.sort()
	var runs := []
	var run: Array = []
	for i: int in nodes:
		if run.size() > 0 and i - run[-1] > 3:
			runs.append(run)
			run = []
		run.append(i)
	if run.size() > 0:
		runs.append(run)
	var count := 0
	for i in nodes:
		count += hits[i].size()
	print("PUQA %s %s: %d runs, %d samples" % [w.id, tag, runs.size(), count])
	for r: Array in runs.slice(0, 25):
		var lats := []
		var vals := []
		for i: int in r:
			for v: Vector2 in hits[i]:
				lats.append(v.x)
				if not is_nan(v.y):
					vals.append(v.y)
		var s := "   nodes %4d..%-4d (%3d) lat %+6.1f..%+6.1f  walls -%.1f/+%.1f" % [r[0], r[-1], r.size(),
			lats.min(), lats.max(), w.path.left_width[r[0]], w.path.right_width[r[0]]]
		if vals.size() > 0:
			s += "  val %+.2f..%+.2f" % [vals.min(), vals.max()]
		print(s)
	if runs.size() > 25:
		print("   … %d more" % (runs.size() - 25))

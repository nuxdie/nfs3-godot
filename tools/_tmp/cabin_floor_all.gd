extends SceneTree
# Every car with an in-car view: rays down over the cabin (seats and footwells, both sides).
# Per ray the lowest surface = the floor. Holes = rays hitting nothing; "low" = floor within
# 3 cm of the wheel bottoms (the road) or under it.
const CELL := 0.1
func _init():
	await process_frame
	var g = root.get_node("/root/Game")
	var filt = Array(OS.get_cmdline_user_args())
	for c in g.cars:
		if not filt.any(func(f): return (c.id as String).begins_with(f)): continue
		var car = g.load_car(c.path)
		if car == null or car.dash.is_empty(): continue
		var own = car.dash.get("own_cabin", false)
		var src = car.body_parts if own else car.dash.parts
		var tris = PackedVector3Array()
		for p in src:
			if typeof(p.get("glass", false)) != TYPE_BOOL or p.get("glass", false) or not p.mesh is Mesh: continue
			for v in (p.mesh as Mesh).get_faces(): tris.append(v + (p.center as Vector3))
		var grid = {}
		for i in range(0, tris.size(), 3):
			var lo = tris[i].min(tris[i+1]).min(tris[i+2]); var hi = tris[i].max(tris[i+1]).max(tris[i+2])
			for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for gz in range(floori(lo.z / CELL), floori(hi.z / CELL) + 1):
					var k = Vector2i(gx, gz)
					if not grid.has(k): grid[k] = []
					grid[k].append(i)
		var wlo = INF
		for w in car.wheels:
			for v in (w.mesh as Mesh).get_faces(): wlo = min(wlo, v.y + (w.center as Vector3).y)
		var eye: Vector3 = car.dash.eye
		var holes = []; var low = []; var n = 0; var fmin = INF
		var half = absf(eye.x) + 0.25
		var x = -half
		while x <= half + 0.001:
			var z = eye.z - 0.3
			while z <= eye.z + 0.95:
				var o = Vector3(x + 0.013, eye.y, z + 0.017)
				n += 1
				var lowest = INF
				for i in grid.get(Vector2i(floori(o.x / CELL), floori(o.z / CELL)), []):
					var h = Geometry3D.ray_intersects_triangle(o, Vector3.DOWN, tris[i], tris[i+1], tris[i+2])
					if h != null: lowest = min(lowest, h.y)
				if lowest == INF: holes.append(Vector2(o.x, o.z).snappedf(0.05))
				else:
					fmin = min(fmin, lowest)
					if lowest < wlo + 0.03: low.append(Vector2(o.x, o.z).snappedf(0.05))
				z += 0.1
			x += 0.1
		var line = "%-16s %-4s wheel %.2f floor-min %.2f  holes %d/%d %s  low %d %s" % [c.id, "own" if own else "dash", wlo, fmin, holes.size(), n, holes.slice(0, 4), low.size(), low.slice(0, 4)]
		print(line)
		var f = FileAccess.open("user://cabin_scan.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://cabin_scan.txt") else FileAccess.WRITE)
		f.seek_end(); f.store_line(line); f.close()
	quit()

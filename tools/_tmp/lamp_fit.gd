extends Node
## For every car, how far each lamp dummy (and the glow Car puts there) sits from the bodywork:
## gap = along the car's length, lamp z minus the skin's z at the lamp's x,y (+ = out in front
## of the skin, - = buried), and near = distance to the nearest body triangle.
##   godot --headless --path . tools/_tmp/lamp_fit.tscn [-- set ... -v]

const GLOW_DZ := {"H": 0.08, "T": 0.06, "P": 0.06, "B": -0.08, "R": -0.07}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = Game
	var sets := {"cars": game.cars.map(func(c): return c.path), "cops": game.cop_cars,
		"traffic": game.traffic_cars, "hscops": game.hs_cop_cars, "hstraffic": game.hs_traffic_cars,
		"pucops": game.pu_cop_cars, "putraffic": game.pu_traffic_cars}
	var want := Array(OS.get_cmdline_user_args())
	var verbose := "-v" in want
	want.erase("-v")
	for sname: String in sets:
		if not want.is_empty() and not sname in want:
			continue
		for path: String in sets[sname]:
			if path == "":
				continue
			var d = game.load_car(path)
			var faces := PackedVector3Array()
			for p in d.body_parts:
				if p.get("driver", false):
					continue
				for v in p.mesh.get_faces():
					faces.append(v + p.center)
			for p in d.popup_lights:
				for v in p.mesh.get_faces():
					faces.append(v + p.center)
			var worst := 0.0
			var lines: Array[String] = []
			var t0 := Time.get_ticks_msec()
			var car := Car.new()
			car.setup(d)
			var ms := Time.get_ticks_msec() - t0
			var glows: Array = car._lamps + car._brake_lights + car._reverse_lights
			var n := 0
			for g in glows:
				if not g is MeshInstance3D:
					continue
				n += 1
				var l: Dictionary = g.get_meta("lamp")
				var p: Vector3 = g.position
				var outz := signf(p.z)
				var skin := _skin_z(faces, p, outz)
				var gap: float = (p.z - skin) * outz if skin != INF else INF
				var near := _nearest(faces, p)
				var bad := near > 0.03 or absf(gap) > 0.03
				if bad:
					worst = maxf(worst, maxf(near, absf(gap) if gap != INF else 9.0))
				if bad or verbose:
					lines.append("    %s%s%s  glow %s  gap %s  near %.3f" % [l.kind, l.colour, l.intensity, _v3(p), _f(gap), near])
			car.free()
			d.lights.size()
			print("%-9s %-40s glows %2d %4d ms  %s" % [sname, "%s (%s)" % [d.display_name, path.get_file()],
				n, ms, "OK" if lines.is_empty() or (verbose and worst == 0.0) else "WORST %.2f" % worst])
			for s in lines:
				print(s)
	get_tree().quit()


static func _f(x: float) -> String:
	return "  miss" if x == INF else "%+.3f" % x


static func _v3(v: Vector3) -> String:
	return "(%+.2f %+.2f %+.2f)" % [v.x, v.y, v.z]


## The outermost skin z (towards `outz`) at the lamp's x, y.
static func _skin_z(faces: PackedVector3Array, p: Vector3, outz: float) -> float:
	var from := Vector3(p.x, p.y, outz * 10.0)
	var best := INF
	for i in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, -outz), faces[i], faces[i + 1], faces[i + 2])
		if hit == null:
			hit = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, -outz), faces[i], faces[i + 2], faces[i + 1])
		if hit != null and (best == INF or hit.z * outz > best * outz):
			best = hit.z
	return best


static func _nearest(faces: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for i in range(0, faces.size(), 3):
		var dd := p.distance_to(_closest_on_tri(p, faces[i], faces[i + 1], faces[i + 2]))
		if dd < best:   # a degenerate triangle gives NaN, which minf() would keep
			best = dd
	return best


## Ericson's closest point on a triangle.
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)

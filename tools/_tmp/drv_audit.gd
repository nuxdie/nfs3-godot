extends SceneTree
# driver-anim agent's audit: seams and hands-on-rim for every PU driver in every steer pose.
var done := false
func _seam(a: PackedVector3Array, b: PackedVector3Array, k := 3) -> float:
	if a.is_empty() or b.is_empty(): return -1.0
	var ds: Array[float] = []
	for p in a:
		var m := INF
		for q in b: m = minf(m, p.distance_squared_to(q))
		ds.append(sqrt(m))
	ds.sort()
	var s := 0.0
	for i in mini(k, ds.size()): s += ds[i]
	return s / mini(k, ds.size())
func _rot(p: Vector3, piv: Vector3, axis: Vector3, ang: float) -> Vector3:
	return piv + Basis(axis, ang) * (p - piv)
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var N5 = load("res://scripts/io/nfs5_car.gd")
	var models := {}
	for c in g.cars:
		if g.is_pu_path(c.path):
			var rec: Dictionary = g._pu_cars[c.path]
			if not models.has(rec.model.to_lower()): models[rec.model.to_lower()] = [c.id, rec]
	var only := OS.get_cmdline_user_args()
	for m in models:
		if not only.is_empty() and not m in only: continue
		var rec: Dictionary = models[m][1]
		for who in (range(1, 11) if OS.get_environment("WHO") == "" else [int(OS.get_environment("WHO"))]):
			var data = N5.load_car(g.pu_root, rec, who)
			var dp = null
			var hb = null
			for p in data.body_parts:
				if p.get("driver", false): dp = p
				if p.name == ":hb": hb = p
			if dp == null or not dp.has("steer_shapes"):
				print("%-8s d%2d  NO SWEEP (dp %s)" % [m, who, dp != null])
				continue
			var names: PackedStringArray = dp.part_names
			var mesh: ArrayMesh = dp.mesh
			var arr := mesh.surface_get_arrays(0)
			var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs := mesh.surface_get_blend_shape_arrays(0)
			var piv: Vector3 = dp.steering.pivot
			var axis: Vector3 = dp.steering.axis
			var hba := (hb.mesh as ArrayMesh).surface_get_arrays(0)
			var rim := PackedVector3Array()
			var hv: PackedVector3Array = hba[Mesh.ARRAY_VERTEX]
			var huv: PackedVector2Array = hba[Mesh.ARRAY_TEX_UV2]
			for i in hv.size():
				if huv[i].x > 0.9: rim.append(hv[i])
			var groups := {}
			for i in names.size():
				var n: String = names[i]
				var key := "body" if n.begins_with("DriverBody") else "legs" if n.begins_with("Legs") \
					else "la" if n.begins_with("LeftArm") else "ra" if n.begins_with("RightArm") \
					else "lh" if n.begins_with("LeftHand") else "rh" if n.begins_with("RightHand") else n
				if not groups.has(key): groups[key] = []
				groups[key].append(i)
			var angles: PackedFloat32Array = dp.steer_shapes
			var worst := {}
			var line := ""
			for k in bs.size():
				var sp: PackedVector3Array = bs[k][Mesh.ARRAY_VERTEX]
				var pts := {}
				for key in groups:
					var v := PackedVector3Array()
					for i in groups[key]: v.append(sp[i])
					pts[key] = v
				var rimk := PackedVector3Array()
				for r in rim: rimk.append(_rot(r, piv, axis, angles[k]))
				var vals := {
					"la-body": _seam(pts.get("la", PackedVector3Array()), pts.body),
					"ra-body": _seam(pts.get("ra", PackedVector3Array()), pts.body),
					"lh-body": _seam(pts.get("lh", PackedVector3Array()), pts.body),
					"rh-body": _seam(pts.get("rh", PackedVector3Array()), pts.body),
					"legs-body": _seam(pts.get("legs", PackedVector3Array()), pts.body),
					"la-rim": _seam(pts.get("la", PackedVector3Array()), rimk, 1),
					"ra-rim": _seam(pts.get("ra", PackedVector3Array()), rimk, 1),
					"lh-rim": _seam(pts.get("lh", PackedVector3Array()), rimk, 1),
					"rh-rim": _seam(pts.get("rh", PackedVector3Array()), rimk, 1)}
				if OS.get_environment("DETAIL") != "":
					print("   %+.2f la %.3f ra %.3f legs %.3f" % [angles[k], vals["la-body"], vals["ra-body"], vals["legs-body"]])
				for key in vals:
					if not worst.has(key) or vals[key] > worst[key][0]:
						worst[key] = [vals[key], angles[k]]
			for key in worst:
				line += " %s %.3f@%+.2f" % [key, worst[key][0], worst[key][1]]
			print("%-8s d%2d limbs %d n%2d reach %+.2f..%+.2f |%s" % [m, who, data._geometry.get(43, 0), angles.size(), angles[0], angles[angles.size() - 1], line])
	quit()
	return true

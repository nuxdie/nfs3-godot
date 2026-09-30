extends SceneTree
# driver-anim agent: legs vs body per model (car space as the loader builds it, minus centring).
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var cdir := DataPath.find_ci(g.pu_root, "Carmodel")
	var N5 = load("res://scripts/io/nfs5_car.gd")
	var c = N5.new()
	for model in OS.get_cmdline_user_args():
		var crp := Crp.load_file(DataPath.find_ci(cdir, model + ".crp"))
		var by := {}
		for art in crp.articles: by[art.name] = art
		var line := model
		for n in ["DriverBody2", "Legs2", "DriverBody7", "Legs4", "LeftArm2"]:
			var art = by[n]
			var tr := crp.sub(art, "tr", 1)
			var xf: Transform3D = c._transform(crp, tr) if tr != null else Transform3D.IDENTITY
			var v := crp.vec3s(crp.sub(art, "vt", 1 | (2 if n.begins_with("Driver") else 0) << 4))
			var b := AABB(xf * v[0], Vector3.ZERO)
			for p in v: b = b.expand(xf * p)
			line += "  %s o%s min%s max%s" % [n, str(xf.origin), str(b.position), str(b.end)]
		print(line)
	quit()
	return true

extends SceneTree
# driver-anim agent: each body's frames, how far they move from the middle lean frame.
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var cdir := DataPath.find_ci(g.pu_root, "Carmodel")
	for model in OS.get_cmdline_user_args():
		var crp := Crp.load_file(DataPath.find_ci(cdir, model + ".crp"))
		for art in crp.articles:
			var base := crp.sub(art, "Base")
			if base == null or not art.name.begins_with("DriverBody"): continue
			var nf := crp.data[base.offset + 76]
			var mid := crp.vec3s(crp.sub(art, "vt", 1 | 2 << 4))
			var line := "%-6s %-13s" % [model, art.name]
			for f in nf:
				var v := crp.vec3s(crp.sub(art, "vt", 1 | f << 4))
				var mx := 0.0
				var c := Vector3.ZERO
				for i in v.size():
					mx = maxf(mx, v[i].distance_to(mid[i]))
					c += v[i] - mid[i]
				c /= v.size()
				var bad := 0
				for i in v.size():
					if v[i].distance_to(mid[i]) > 0.15: bad += 1
				line += " f%d %.3f/%d" % [f, mx, bad]
			print(line)
	quit()
	return true

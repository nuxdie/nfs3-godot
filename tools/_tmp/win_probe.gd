extends SceneTree
# Lists a PU car's door-group articles: the window (slot 35) and what's round it (win probe).
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	if g.pu_root == "": g.scan_data()
	var cdir := DataPath.find_ci(g.pu_root, "Carmodel")
	var crp := Crp.load_file(DataPath.find_ci(cdir, OS.get_cmdline_user_args()[0]))
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null: continue
		var bi := crp.data.slice(base.offset + 68, base.offset + 84)
		if bi[7] != 6 and bi[0] != 35: continue
		var nf := 0
		for f in 64:
			if crp.sub(art, "vt", 1 | f << 4) != null: nf = f + 1
		var vt := crp.sub(art, "vt", 1)
		if vt == null:
			print("%-20s slot %2d var %2d grp %d lvl %02x (no vt) bi %s" % [art.name, bi[0], bi[1], bi[7], bi[10], bi])
			continue
		var v := crp.vec3s(vt)
		var box := AABB(v[0], Vector3.ZERO)
		for p in v: box = box.expand(p)
		var subs := []
		for s in art.subs if "subs" in art else []: subs.append(s.id if "id" in s else s)
		print("%-20s slot %2d var %2d grp %d lvl %02x fr %d/%d nvt %4d box %s..%s bi %s" % [art.name, bi[0], bi[1], bi[7], bi[10], bi[8], nf, v.size(), box.position.snapped(Vector3.ONE*0.001), box.end.snapped(Vector3.ONE*0.001), bi])
	quit()
	return true

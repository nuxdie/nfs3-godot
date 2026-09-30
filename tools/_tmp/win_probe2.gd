extends SceneTree
# Prints the left door's window, skin and trim vertices (door-local) (win probe).
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
		if bi[7] != 6 or bi[1] != 0 or art.name != "DoorWindow": continue
		var vt := crp.sub(art, "vt", 1)
		var tr := crp.sub(art, "tr", 1)
		print("== ", art.name, " tr ", tr != null)
		for p in crp.vec3s(vt):
			print("  %7.3f %7.3f %7.3f" % [p.x, p.y, p.z])
	quit()
	return true

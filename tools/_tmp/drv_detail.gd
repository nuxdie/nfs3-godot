extends SceneTree
# driver-anim agent: raw frame data of the people articles in one model.
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var cdir := DataPath.find_ci(g.pu_root, "Carmodel")
	var args := OS.get_cmdline_user_args()
	var crp := Crp.load_file(DataPath.find_ci(cdir, args[0] + ".crp"))
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null: continue
		var bi := crp.data.slice(base.offset + 68, base.offset + 84)
		if bi[10] != 0x81 or art.name.to_lower().begins_with("lod"): continue
		var sizes := []
		for f in bi[8]:
			var vt := crp.sub(art, "vt", 1 | f << 4)
			sizes.append(crp.vec3s(vt).size() if vt != null else -1)
		print("%-14s slot %2d var %2d frames %2d rest %2d sizes %s" % [art.name, bi[0], bi[1], bi[8], bi[9], sizes])
	quit()
	return true

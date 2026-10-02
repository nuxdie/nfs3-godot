extends SceneTree
func _process(_d):
	var g = root.get_node("Game")
	for id in OS.get_cmdline_user_args():
		var t: Gt2Track = Gt2Track.load_dir("gt2:" + (g._gt2_tracks[id].course as String))
		var grid := t._tri_grid()
		var s := ""
		for i in t.vroad.size():
			if t._tri_at(grid, t.vroad[i].pos) < 0:
				s += "%d " % i
		print(id, " n=", t.vroad.size(), " sprint=", t.sprint, " off: ", s)
	quit()
	return true

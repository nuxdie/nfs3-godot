extends SceneTree
## Per course: share of centre-line nodes off the tarmac (and off any road), line path vs chunk path.
func _process(_d):
	var g = root.get_node("Game")
	var ids = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = g._gt2_tracks.keys()
	for id in ids:
		var s := ""
		for fc in [false, true]:
			Gt2Track.force_chunks = fc
			var t: Gt2Track = Gt2Track.load_dir("gt2:" + (g._gt2_tracks[id].course as String))
			var grid := t._tri_grid()
			var off := 0
			var offt := 0
			var narrow := 0
			for v in t.vroad:
				var k := t._tri_at(grid, v.pos, 1.5)
				if k < 0:
					off += 1
				elif not t._tarmac.has(t._road_tris[k][3]):
					offt += 1
				if v.left_wall + v.right_wall < 8.0:
					narrow += 1
			s += "  %s: n=%d offroad=%.1f%% offtarmac=%.1f%% narrow=%.1f%%" % ["chunks" if fc else "line  ", t.vroad.size(), 100.0 * off / t.vroad.size(), 100.0 * offt / t.vroad.size(), 100.0 * narrow / t.vroad.size()]
		print(id, s)
	quit()
	return true

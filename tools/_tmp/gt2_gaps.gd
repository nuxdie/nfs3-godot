extends SceneTree
func _process(_d):
	var g = root.get_node("Game")
	for id in OS.get_cmdline_user_args():
		var t := Gt2Track.new()
		t.course = g._gt2_tracks[id].course
		t._d = Gt2Track.vol.read("crsobj/%s.tro.gz" % t.course)
		t._read_header()
		var n := t._chunk_at.size()
		var s := ""
		for c in n:
			var nx := t._d.decode_u16(t._chunk_at[c] + 2)
			var pv := t._d.decode_u16(t._chunk_at[c])
			var gap := t._centre(c).distance_to(t._centre(nx)) if nx < n else -1.0
			s += "%d:%d<%d>%d %.0f | " % [c, pv, c, nx, gap]
		print(id, " n=", n, " start=", t._start, "\n", s)
		var ln := 0.0
		for i in t._line.size() - 1:
			ln += t._line[i].distance_to(t._line[i + 1])
		print("line pts ", t._line.size(), " len ", ln, " ends ", t._line[0], t._line[t._line.size()-1])
	quit()
	return true

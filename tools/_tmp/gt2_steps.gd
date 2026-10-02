extends SceneTree
## Low steep faces (kerb sides) near a point: their heights.
func _process(_d):
	var g = root.get_node("Game")
	var a := OS.get_cmdline_user_args()
	var t := Gt2Track.new()
	t.course = g._gt2_tracks[a[0]].course
	t._d = Gt2Track.vol.read("crsobj/%s.tro.gz" % t.course)
	var trp := Gt2Track.vol.read("crsobj/%s.trp.gz" % t.course)
	t._read_textures(trp)
	t._read_header()
	t._read_chunks()
	var at := Vector3(float(a[1]), 0, float(a[2]))
	var hist := {}
	for c in t.chunks:
		var pc = c.pieces[0]
		for i in range(0, pc.pos.size(), 3):
			var p0: Vector3 = pc.pos[i]; var p1: Vector3 = pc.pos[i+1]; var p2: Vector3 = pc.pos[i+2]
			var n := (p1 - p0).cross(p2 - p0).normalized()
			if absf(n.y) < 0.8:
				var h := maxf(maxf(p0.y, p1.y), p2.y) - minf(minf(p0.y, p1.y), p2.y)
				var k := snappedf(h, 0.05)
				hist[k] = hist.get(k, 0) + 1
				if Vector2(p0.x - at.x, p0.z - at.z).length() < 15:
					print("near: h=%.2f ny=%.2f at %s" % [h, n.y, p0])
	var ks := hist.keys(); ks.sort()
	for k in ks: print("h %.2f: %d" % [k, hist[k]])
	quit()
	return true

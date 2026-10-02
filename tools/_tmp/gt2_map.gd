extends SceneTree
## Top-down map per GT2 course: flat faces grey (tarmac darker), the centre line red (node 0 green),
## the driving line blue. shots/gt2qa/map_<id>.png.  -s tools/_tmp/gt2_map.gd -- [ids]
func _process(_d):
	var g = root.get_node("Game")
	var ids = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = g._gt2_tracks.keys()
	for id in ids:
		var t: Gt2Track = Gt2Track.load_dir("gt2:" + (g._gt2_tracks[id].course as String))
		var lo := Vector2(INF, INF); var hi := -lo
		for tr in t._road_tris:
			for k in 3:
				lo = lo.min(Vector2(tr[k].x, tr[k].z)); hi = hi.max(Vector2(tr[k].x, tr[k].z))
		var S := 1400.0
		var sc: float = S / maxf(hi.x - lo.x, hi.y - lo.y)
		var img := Image.create(int((hi.x - lo.x) * sc) + 4, int((hi.y - lo.y) * sc) + 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.1, 0.12, 0.1))
		var P := func(v: Vector3) -> Vector2i: return Vector2i(int((v.x - lo.x) * sc) + 2, int((v.z - lo.y) * sc) + 2)
		for tr in t._road_tris:
			var c := Color(0.45, 0.45, 0.45) if t._tarmac.has(tr[3]) else Color(0.25, 0.3, 0.25)
			var a: Vector2i = P.call(tr[0]); var b: Vector2i = P.call(tr[1]); var cc: Vector2i = P.call(tr[2])
			var mn := Vector2i(mini(a.x, mini(b.x, cc.x)), mini(a.y, mini(b.y, cc.y)))
			var mx := Vector2i(maxi(a.x, maxi(b.x, cc.x)), maxi(a.y, maxi(b.y, cc.y)))
			for x in range(mn.x, mx.x + 1):
				for y in range(mn.y, mx.y + 1):
					var p := Vector2(x, y)
					if Geometry2D.point_is_inside_triangle(p, Vector2(a), Vector2(b), Vector2(cc)) and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
						img.set_pixel(x, y, c)
		for i in t._line.size():
			var q: Vector2i = P.call(Vector3(t._line[i].x, 0, t._line[i].y))
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var r := q + Vector2i(dx, dy)
					if r.x >= 0 and r.y >= 0 and r.x < img.get_width() and r.y < img.get_height():
						img.set_pixel(r.x, r.y, Color(0.3, 0.5, 1))
		for i in t.vroad.size():
			var q: Vector2i = P.call(t.vroad[i].pos)
			var col := Color.GREEN if i < 5 else Color.RED
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var r := q + Vector2i(dx, dy)
					if r.x >= 0 and r.y >= 0 and r.x < img.get_width() and r.y < img.get_height():
						img.set_pixel(r.x, r.y, col)
		img.save_png("res://shots/gt2qa/map_%s.png" % id)
		print("%s: %d nodes closed=%s open=%s line=%d line_closed=%s tarmac=%d misses=%d err=%s" % [id, t.vroad.size(), t.closed, t._open, t._line.size(), t._line_closed, t._tarmac.size(), t.misses, t.error])
	quit()
	return true

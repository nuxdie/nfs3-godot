extends Node
## `-- <track>`: the SimT segments: slices, ends, flatness, widths, and which segments
## start or end near each one's end (the junction candidates), and the route taken.
func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var crp := Crp.load_file(Game.track_dir(id))
	var simd := Nfs5Track._read_simd(crp)
	var simt: Array[Crp.Entry] = crp.misc_of("SimT")
	var segs := []
	var at := 0
	for k in simt[0].count:
		var n := crp.data.decode_u32(simt[0].offset + k * 4)
		segs.append(Vector2i(at, at + n - 1))
		at += n
	print("%s: %d slices, %d segments, SimT entries %d (len %d)" % [id, simd.size(), segs.size(), simt.size(), simt[0].length])
	for m in crp.misc:
		if m.id.begins_with("Sim"):
			print("  misc %s idx %d count %d len %d" % [m.id, m.index, m.count, m.length])
	for j in segs.size():
		var s: Vector2i = segs[j]
		if s.y < s.x:
			print("  seg %2d empty" % j)
			continue
		var flat := 0
		var wl := {}
		for i in range(s.x, s.y + 1):
			if simd[i].up == Vector3.UP:
				flat += 1
			wl["%d/%d" % [simd[i].left, simd[i].right_w]] = true
		var a: Vector3 = simd[s.x].pos
		var b: Vector3 = simd[s.y].pos
		var near := []
		for k in segs.size():
			if k == j or segs[k].y < segs[k].x:
				continue
			var d0: float = b.distance_to(simd[segs[k].x].pos)
			var d1: float = b.distance_to(simd[segs[k].y].pos)
			if d0 < 40.0:
				near.append("→%d(%.0fm)" % [k, d0])
			if d1 < 40.0:
				near.append("end%d(%.0fm)" % [k, d1])
		print("  seg %2d slices %4d..%-4d (%4d) %s→%s flat %3d%% lanes %d/%d widths %s  near end: %s" % [j, s.x, s.y, s.y - s.x + 1,
			a.round(), b.round(), 100 * flat / (s.y - s.x + 1), simd[s.x].lanes_l, simd[s.x].lanes_r, wl.keys().slice(0, 4), " ".join(near)])
	var t := Nfs5Track.new()
	var order := t._route(crp, simd)
	var used := []
	for i in order:
		for j in segs.size():
			if i >= segs[j].x and i <= segs[j].y and (used.is_empty() or used[-1] != j):
				used.append(j)
	print("route segments: %s  closed %s sprint %s" % [used, t.closed, t.sprint])
	get_tree().quit()

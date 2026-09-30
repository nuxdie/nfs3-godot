extends Node
## `-- <track>`: per SimT segment, how many of its slices have road collision within 1.5 m
## (vertically) of them, and the median offset to the nearest road above/below.
func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var w := TrackWorld.load_track(id)
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var crp := Crp.load_file(Game.track_dir(id))
	var simd := Nfs5Track._read_simd(crp)
	var t: Crp.Entry = crp.misc_of("SimT")[0]
	var road: StaticBody3D = w.root.get_node("Road")
	var at := 0
	for k in t.count:
		var n := crp.data.decode_u32(crp.misc_of("SimT")[0].offset + k * 4)
		var on := 0
		var offs := []
		for i in range(at, at + n):
			var p: Vector3 = simd[i].pos
			var best := INF
			for from in [1.5, 12.0]:
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * from, p + Vector3.DOWN * 12.0, 1)
				var hits := space.intersect_ray(q)
				if not hits.is_empty() and hits.collider == road and absf(hits.position.y - p.y) < absf(best):
					best = hits.position.y - p.y
			if absf(best) <= 1.5:
				on += 1
			if best < INF:
				offs.append(best)
		offs.sort()
		print("seg %2d n %4d lanes %d/%d  on road %3d%%  median road dy %s" % [k, n, simd[at].lanes_l, simd[at].lanes_r,
			100 * on / n, "%+.1f" % offs[offs.size() / 2] if offs.size() > 0 else "none"])
		at += n
	get_tree().quit()

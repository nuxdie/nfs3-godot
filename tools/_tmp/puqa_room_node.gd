extends Node
## `-- <track>...`: per node and side, how far out from the line a car could really go:
## walking out in 0.5 m steps until solid (scenery/terrain face at car height), a drop or
## rise over 1.5 m, or no ground. Prints its spread against the vroad walls.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var w := TrackWorld.load_track(id)
		add_child(w.root)
		for k in 3:
			await get_tree().physics_frame
		var space := get_viewport().world_3d.direct_space_state
		var ex: Array[RID] = [(w.root.get_node("Walls") as StaticBody3D).get_rid()]
		var p := w.path
		var extra := []   # room past the wall, m
		var lane_edge := []   # wall past the outer lane edge, m
		var why := {}
		for i in range(0, p.size(), 4):
			for side: float in [-1.0, 1.0]:
				var wall: float = p.right_width[i] if side > 0 else p.left_width[i]
				var lanes: float = p.lane_count(i, int(side)) * (p.lane_width_right[i] if side > 0 else p.lane_width_left[i])
				lane_edge.append(wall - lanes)
				var prev_h := 0.0
				var d := 0.0
				var stop := "far"
				while d < 40.0:
					d += 0.5
					var at: Vector3 = p.points[i] + p.rights[i] * d * side
					var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * (prev_h + 2.0), at + Vector3.DOWN * (4.0 - prev_h), 1 | Nfs3TrackBuilder.SCENERY_LAYER)
					q.exclude = ex
					var h := space.intersect_ray(q)
					if h.is_empty():
						stop = "drop"
						break
					var hy: float = h.position.y - p.points[i].y
					if hy - prev_h > 0.6:
						stop = "rise/solid"
						break
					if prev_h - hy > 1.5:
						stop = "drop"
						break
					prev_h = hy
				why[stop] = why.get(stop, 0) + 1
				extra.append(d - 0.5 - wall)
		extra.sort()
		lane_edge.sort()
		var n := extra.size()
		print("%s: room past the wall (m) p10 %.1f  median %.1f  p90 %.1f;  wall past the lanes' edge median %.1f;  stops %s" % [id,
			extra[n / 10], extra[n / 2], extra[n * 9 / 10], lane_edge[n / 2], why])
		w.root.queue_free()
	get_tree().quit()

extends Node
## `-- <track>...`: drives a ray at 1 m along each side road's centre, from the lap's
## nearest node through its slices and back to the lap, and reports where walls block it.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var w := TrackWorld.load_track(id)
		add_child(w.root)
		for k in 3:
			await get_tree().physics_frame
		var space := get_viewport().world_3d.direct_space_state
		var walls: StaticBody3D = Nfs3TrackBuilder.make_walls(w.path)
		w.root.get_node("Walls").free()
		w.root.add_child(walls)
		for k in 3:
			await get_tree().physics_frame
		var t: Nfs5Track = w.track
		var blocked := 0
		for r in t.side_roads.size():
			var road: Array = t.side_roads[r]
			var pts: Array[Vector3] = []
			var a0: Vector3 = road[0].pos
			var n0 := w.path.closest(a0)
			if w.path.points[n0].distance_to(a0) < 30.0:
				pts.append(w.path.points[n0])
			for vr: Nfs3Track.VRoad in road:
				pts.append(vr.pos)
			var a1: Vector3 = road[-1].pos
			var n1 := w.path.closest(a1)
			if w.path.points[n1].distance_to(a1) < 30.0:
				pts.append(w.path.points[n1])
			var hits := []
			for k in pts.size() - 1:
				var q := PhysicsRayQueryParameters3D.create(pts[k] + Vector3.UP, pts[k + 1] + Vector3.UP, 1)
				q.hit_back_faces = true
				var h := space.intersect_ray(q)
				if not h.is_empty() and h.collider == walls:
					hits.append("step %d/%d (%s)" % [k, pts.size() - 1, h.shape])
			blocked += hits.size()
			if not hits.is_empty():
				print("%s side road %d blocked at %s" % [id, r, ", ".join(hits.slice(0, 6))])
		print("%s: %d side roads, %d blocked steps" % [id, t.side_roads.size(), blocked])
		w.root.queue_free()
	get_tree().quit()

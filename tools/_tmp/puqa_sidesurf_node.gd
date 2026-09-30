extends Node
## `-- <track>...`: what's under each side road's slices (Road / Terrain / nothing), and how
## far the furthest is from the lap's walls.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var w := TrackWorld.load_track(id)
		add_child(w.root)
		for k in 3:
			await get_tree().physics_frame
		var space := get_viewport().world_3d.direct_space_state
		var t: Nfs5Track = w.track
		var kinds := {}
		var far := 0.0
		for road: Array in t.side_roads:
			for vr: Nfs3Track.VRoad in road:
				var q := PhysicsRayQueryParameters3D.create(vr.pos + Vector3.UP * 2, vr.pos + Vector3.DOWN * 3, 1)
				q.exclude = [(w.root.get_node("Walls") as StaticBody3D).get_rid()]
				var h := space.intersect_ray(q)
				var k: String = "none" if h.is_empty() else String(h.collider.name)
				kinds[k] = kinds.get(k, 0) + 1
				var n := w.path.closest(vr.pos)
				far = maxf(far, absf(w.path.lateral(vr.pos, n)) - maxf(w.path.left_width[n], w.path.right_width[n]))
		print("%s: side road slices over %s; furthest %.0f m outside the lap's walls" % [id, kinds, far])
		w.root.queue_free()
	get_tree().quit()

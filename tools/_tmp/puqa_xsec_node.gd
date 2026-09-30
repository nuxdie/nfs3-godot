extends Node
## `-- <track> node [node...]`: cross-section: every collision surface (top-down, all hits)
## under each lateral metre of the corridor and 4 m past each wall, relative to the node.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0])
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var p := w.path
	for s in a.slice(1):
		var i := int(s)
		print("node %d walls -%.1f/+%.1f lanes %d/%d" % [i, p.left_width[i], p.right_width[i], p.lane_count(i, -1), p.lane_count(i, 1)])
		var lat := -p.left_width[i] - 4.0
		while lat <= p.right_width[i] + 4.0:
			var top := p.points[i] + p.rights[i] * lat + Vector3.UP * 12.0
			var ex: Array[RID] = []
			var hits := []
			for k in 6:
				var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 30.0, 1)
				q.exclude = ex
				var h := space.intersect_ray(q)
				if h.is_empty():
					break
				hits.append("%+.1f%s" % [h.position.y - p.points[i].y, (h.collider.name as String).left(1)])
				top = h.position + Vector3.DOWN * 0.05
			print("  %+5.1f %s" % [lat, " ".join(hits)])
			lat += 1.0
	get_tree().quit()

extends Node
## `-- <track> from to`: per node, spacing to the next, the widths, and where the ground
## collision is over/under the node (first hit coming down from 30 m above, and from 1 m).
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(args[0])
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var ex := [(w.root.get_node("Walls") as StaticBody3D).get_rid()]
	var p := w.path
	for i in range(int(args[1]), int(args[2]) + 1):
		var s := ""
		for from in [30.0, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(p.points[i] + Vector3.UP * from, p.points[i] + Vector3.DOWN * 40.0, 1)
			q.exclude = ex
			var h := space.intersect_ray(q)
			s += "  %s" % ("none" if h.is_empty() else "%+6.2f %s" % [h.position.y - p.points[i].y, h.collider.name])
		print("%4d y %7.2f step %5.1f  L %4.1f R %4.1f  up %s%s" % [i, p.points[i].y, p.points[i].distance_to(p.points[p.idx(i + 1)]),
			p.left_width[i], p.right_width[i], p.ups[i].snappedf(0.01), s])
	get_tree().quit()

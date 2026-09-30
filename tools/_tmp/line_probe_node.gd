extends Node

func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var w := TrackWorld.load_track(id)
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var path := w.path
	var space := get_viewport().world_3d.direct_space_state
	var n := path.size()
	for which in ["centre", "racing"]:
		var nodes := []
		var rl: PackedFloat32Array = path.racing_line[0]
		if which == "racing" and rl.size() != n:
			continue
		for i in n:
			var j := (i + 1) % n
			var a := path.points[i] + path.ups[i] * 0.6
			var b := path.points[j] + path.ups[j] * 0.6
			if which == "racing":
				a += path.rights[i] * rl[i]
				b += path.rights[j] * rl[j]
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, Nfs3TrackBuilder.SCENERY_LAYER))
			if not hit.is_empty():
				nodes.append(i)
		print("%s %s line blocked at %d nodes: %s" % [id, which, nodes.size(), nodes.slice(0, 30)])
	get_tree().quit()

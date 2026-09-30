extends Node

func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var w := TrackWorld.load_track(id)
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var path := w.path
	var rails: Guardrails = w.root.get_node("Guardrails")
	var space := get_viewport().world_3d.direct_space_state
	var n := path.size()
	var total := 0
	var inside := 0
	var stopped := 0
	var missed := []
	for ch in rails._chunks:
		var rest: PackedVector3Array = ch.rest
		var lean: PackedFloat32Array = ch.lean
		for i in range(0, rest.size(), 6):
			if lean[i] > 0.01:
				continue
			var p := rest[i]
			var best := -1
			var bd := INF
			for k in n:
				var d := path.points[k].distance_squared_to(p)
				if d < bd:
					bd = d
					best = k
			var lat := (p - path.points[best]).dot(path.rights[best])
			var wall: float = path.right_width[best] if lat > 0 else path.left_width[best]
			total += 1
			if wall - absf(lat) <= 1.0:
				continue
			inside += 1
			# From 3 m inside the rail, straight out at bumper height.
			var out := path.rights[best] * signf(lat)
			var target := p + Vector3.UP * 0.5
			var q := PhysicsRayQueryParameters3D.create(target - out * 3.0, target + out * 0.5, Nfs3TrackBuilder.SCENERY_LAYER)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.position.distance_to(target) < 0.6 + 0.0:
				stopped += 1
			else:
				missed.append(best)
				if missed.size() <= 6:
					var alt := space.intersect_ray(PhysicsRayQueryParameters3D.create(target - out * 3.0, target + out * 0.5, Nfs3TrackBuilder.SCENERY_LAYER))
					var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1))
					print("node %d lat %.1f wall %.1f hit %s scen %s ground_dy %s" % [best, lat, wall,
						"none" if hit.is_empty() else "%.2f %s" % [hit.position.distance_to(target), hit.collider.name],
						"none" if alt.is_empty() else "%.2f" % alt.position.distance_to(target),
						"none" if down.is_empty() else "%.2f" % (down.position.y - p.y)])
	print("rail feet: %d, >1m inside the wall: %d, stopped at the rail: %d" % [total, inside, stopped])
	print("missed at nodes: ", missed.slice(0, 40))
	get_tree().quit()

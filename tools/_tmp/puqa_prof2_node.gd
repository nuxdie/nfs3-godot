extends Node
## `-- pu_<track> x0,z0 x1,z1`: the ground height (down-ray) every 0.5 m from one point to the other, and what it is.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0])
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var p0 := a[1].split_floats(",")
	var p1 := a[2].split_floats(",")
	var A := Vector2(p0[0], p0[1])
	var B := Vector2(p1[0], p1[1])
	var n := int(A.distance_to(B) / 0.5)
	var prev := NAN
	for i in n + 1:
		var p := A.lerp(B, float(i) / n)
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200, p.y), Vector3(p.x, -200, p.y), 1 | 2 | Nfs3TrackBuilder.SCENERY_LAYER)
		var h := space.intersect_ray(q)
		var y: float = h.position.y if not h.is_empty() else NAN
		if i % 2 == 0 or absf(y - prev) > 0.3:
			print("%5.1f m  y %.2f  %s  n.y %.2f%s" % [i * 0.5, y, h.collider.name if not h.is_empty() else "-", h.normal.y if not h.is_empty() else 0.0, "  STEP %.2f" % (y - prev) if absf(y - prev) > 0.3 else ""])
		prev = y
	get_tree().quit()

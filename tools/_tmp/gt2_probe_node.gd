extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0], false, 0)
	add_child(w.root)
	for k in 4:
		await get_tree().physics_frame
	var at := Vector3(float(a[1]), float(a[2]), float(a[3]))
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = float(a[4]) if a.size() > 4 else 2.5
	q.shape = sp
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 0xFFFFFFFF
	var space := get_viewport().world_3d.direct_space_state
	for hit in space.intersect_shape(q, 64):
		var o: CollisionObject3D = hit.collider
		print("hit %s layer %d shape %d" % [o.get_path(), o.collision_layer, hit.shape])
	for dx in range(-4, 5, 2):
		for dz in range(-4, 5, 2):
			var rq := PhysicsRayQueryParameters3D.create(at + Vector3(dx, 5, dz), at + Vector3(dx, -5, dz))
			var r := space.intersect_ray(rq)
			if r:
				print("ray %d,%d hit %s y %.2f n %s" % [dx, dz, r.collider.name, r.position.y, r.normal.snapped(Vector3.ONE * 0.01)])
	var path: TrackPath = w.path
	for i in path.size():
		for side in [-1.0, 1.0]:
			var f: Vector3 = path.points[i] + path.rights[i] * path.wall_width(i, side) * side
			if Vector2(f.x - at.x, f.z - at.z).length() < 8.0:
				print("wall foot node %d side %d at %s (w %.1f, centre %s)" % [i, side, f.snapped(Vector3.ONE * 0.1), path.wall_width(i, side), path.points[i].snapped(Vector3.ONE * 0.1)])
	print("path nodes ", path.size())
	get_tree().quit()

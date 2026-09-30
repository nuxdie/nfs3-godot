extends "res://tools/hs_qa.gd"
## hs_qa's pictures for a Porsche Unleashed track: `-- <track> --at=n,n,... [--size=m]`.
## Red = vroad walls, green = road collision, yellow = terrain collision (ground kind).

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var id: String = args[0]
	var at := []
	var size := 110.0
	for a: String in args:
		if a.begins_with("--at="):
			for s in a.get_slice("=", 1).split(","):
				at.append(int(s))
		if a.begins_with("--size="):
			size = float(a.get_slice("=", 1))
	w = TrackWorld.load_track(id)
	add_child(w.root)
	add_child(overlay)
	w.light(self, false, false, get_viewport())
	for k in 3:
		await get_tree().physics_frame
	_body_overlay(w.root.get_node_or_null("Walls"), Color(1, 0, 0, 0.35))
	_body_overlay(w.root.get_node_or_null("Road"), Color(0, 1, 0, 0.18))
	_body_overlay(w.root.get_node_or_null("Terrain"), Color(1, 0.9, 0, 0.12))
	_body_overlay(w.root.get_node_or_null("Scenery"), Color(0, 1, 1, 0.3))
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var dir := "res://shots/qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := w.path
	for i: int in at:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 70.0
		cam.far = 3000.0
		cam.global_position = path.points[path.idx(i - 3)] + path.ups[i] * 2.2
		cam.look_at(path.points[path.idx(i + 5)] + Vector3.UP * 1.0, Vector3.UP)
		for on in [false, true]:
			_set_overlay(on)
			await _settle()
			_save("%s/%s_n%04d_%s.png" % [dir, id, i, "road_qa" if on else "road"])
		var fwd := path.points[path.idx(i + 2)] - path.points[path.idx(i - 2)]
		fwd.y = 0.0
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
		cam.far = 400.0
		cam.global_position = path.points[i] + Vector3.UP * 200.0
		cam.look_at(path.points[i], fwd.normalized())
		_set_overlay(true)
		await _settle()
		_save("%s/%s_n%04d_top.png" % [dir, id, i])
		print("shot node %d" % i)
	get_tree().quit()

extends Node
## -- <track> <frac>: shots with groups of meshes hidden, to find what's in view.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var id: String = args[1]
	var f := float(args[2])
	var w := TrackWorld.load_track(id, false, 0)
	add_child(w.root)
	w.light(self, false, false, get_viewport())
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var path := w.path
	var i := int(f * path.size()) % path.size()
	cam.global_position = path.points[path.idx(i - 1)] + Vector3.UP * 2.2
	cam.look_at(path.points[path.idx(i + 7)] + Vector3.UP, Vector3.UP)
	var geo := w.root.get_node("Geometry")
	var names := []
	for n in geo.get_children():
		names.append(n.name)
	print(names)
	# Hide one kind at a time: chunks by distance bands, groups.
	var tests := {"all": func(n: Node) -> bool: return false,
		"noobjects": func(n: Node) -> bool: return String(n.name).begins_with("Objects"),
		"nochunks": func(n: Node) -> bool: return String(n.name).begins_with("Chunk"),
		"nobackdrop": func(n: Node) -> bool: return String(n.name).begins_with("Backdrop")}
	for t in tests:
		for n in geo.get_children():
			if n is GeometryInstance3D:
				n.set_meta("was", n.visible) if not n.has_meta("was") else null
				n.visible = n.get_meta("was") and not tests[t].call(n)
		for k in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("shots/iso_%s_%s.png" % [id, t])
	# Which chunks: find those whose AABB is above the camera and near.
	for n in geo.get_children():
		if n is MeshInstance3D:
			var bb: AABB = n.global_transform * n.get_aabb()
			if bb.position.y + bb.size.y > cam.global_position.y + 10 and bb.grow(5).has_point(Vector3(cam.global_position.x, bb.get_center().y, cam.global_position.z)):
				print("over cam: ", n.name, " ", bb)
	get_tree().quit()

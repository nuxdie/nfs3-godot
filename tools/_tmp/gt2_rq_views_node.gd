extends Node
## -- <track> <tag> [n]: n views round the lap, saved shots/vw_<tag>_<track>_<k>.png
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var id: String = args[1]
	var tag: String = args[2]
	var views := int(args[3]) if args.size() > 3 else 16
	var w := TrackWorld.load_track(id, false, 0)
	add_child(w.root)
	w.light(self, false, false, get_viewport())
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var path := w.path
	for v in views:
		var i := int(float(v) / views * path.size()) % path.size()
		for back in [false, true]:
			var dir := -1 if back else 1
			cam.global_position = path.points[path.idx(i - dir)] + Vector3.UP * 2.2
			cam.look_at(path.points[path.idx(i + 7 * dir)] + Vector3.UP, Vector3.UP)
			for f in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("shots/vw/%s_%s_%d%s.png" % [tag, id, v, "b" if back else ""])
	get_tree().quit()

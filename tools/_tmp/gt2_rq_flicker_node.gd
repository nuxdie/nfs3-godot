extends Node
## -- <track> [n views]: per view, pixels that flip when the camera moves 3 mm (z-fighting).
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var id: String = args[1]
	var views := int(args[2]) if args.size() > 2 else 12
	var w := TrackWorld.load_track(id, false, 0)
	add_child(w.root)
	w.light(self, false, false, get_viewport())
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	var path := w.path
	var total := 0
	var worst := []
	for v in views:
		var i := int(float(v) / views * path.size()) % path.size()
		var at: Vector3 = path.points[path.idx(i - 1)] + Vector3.UP * 2.2
		var look: Vector3 = path.points[path.idx(i + 7)] + Vector3.UP
		var imgs: Array[Image] = []
		for s in 2:
			cam.global_position = at + Vector3(0.003, 0.002, 0.003) * s
			cam.look_at(look + Vector3(0.003, 0.002, 0.003) * s, Vector3.UP)
			for f in 4:
				await get_tree().process_frame
			imgs.append(get_viewport().get_texture().get_image())
		var a := imgs[0].get_data()
		var b := imgs[1].get_data()
		var n := 0
		var bpp := 4 if imgs[0].get_format() == Image.FORMAT_RGBA8 else 3
		for p in range(0, a.size(), bpp * 2):
			if absi(a[p] - b[p]) + absi(a[p + 1] - b[p + 1]) + absi(a[p + 2] - b[p + 2]) > 90:
				n += 1
		total += n
		worst.append([n, v])
		if n > 200:
			imgs[0].save_png("shots/flk_%s_%d_a.png" % [id, v])
			imgs[1].save_png("shots/flk_%s_%d_b.png" % [id, v])
	worst.sort()
	print("FLICKER %s total %d worst %s" % [id, total, str(worst.slice(-4))])
	get_tree().quit()

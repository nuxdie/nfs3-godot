extends Node
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var id: String = OS.get_cmdline_user_args()[1]
	for msaa in [Viewport.MSAA_DISABLED, Viewport.MSAA_4X]:
		var w := TrackWorld.load_track(id, false, 0)
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.own_world_3d = true
		vp.msaa_3d = msaa
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		vp.add_child(w.root)
		var cam := Camera3D.new()
		cam.fov = 55.0
		cam.far = 2500.0
		vp.add_child(cam)
		cam.global_transform = TrackPostcards.pose(w.path)
		w.light(vp, false, false)
		print("nodes in vp: ", vp.get_children().map(func(n): return n.name))
		for k in 4:
			await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("shots/pc_test_%s_%d.png" % [id, msaa])
		vp.queue_free()
	get_tree().quit()

extends Node
## -- <track>: the sky alone, then with the race's environment, then + apply_quality.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var id: String = OS.get_cmdline_user_args()[1]
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	cam.rotation_degrees = Vector3(15, 0, 0)
	var dome := Gt2Sky.build(Game.gt2_sky(id))
	add_child(dome)
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("shots/sk2_a.png")
	dome.queue_free()
	var w := TrackWorld.load_track(id, false, 0)
	w.light(self, false, false)
	cam.global_position = Vector3(0, 3000, 0)
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("shots/sk2_b.png")
	w.light(self, false, false, get_viewport())
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("shots/sk2_c.png")
	get_tree().quit()

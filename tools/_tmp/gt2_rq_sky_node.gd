extends Node
## Renders a GT2 course's sky dome alone: -- --gt2sky <track>
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if get_tree().current_scene: get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var id: String = args[1]
	var dome := Gt2Sky.build(Game.gt2_sky(id))
	add_child(dome)
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 90
	add_child(cam)
	cam.make_current()
	var k := 0
	for yaw in [0, 90, 180, 270]:
		for pitch in [0, 40]:
			cam.rotation_degrees = Vector3(pitch, yaw, 0)
			for f in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("shots/sky_%s_%d.png" % [id, k])
			k += 1
	get_tree().quit()

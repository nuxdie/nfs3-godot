extends Node
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().current_scene.queue_free()
	get_window().size = Vector2i(400, 300)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var fx := CarEffects.new(null)
	var s: CPUParticles3D = fx._smoke_emitter(null)
	var o := OS.get_environment("OVR").split(",")
	if "amount" in o: s.amount = 1
	if "oneshot" in o: s.one_shot = true
	if "ramp" in o: s.color_ramp = null
	if "scale" in o: s.scale_amount_curve = null
	if "vel" in o:
		s.initial_velocity_min = 0.0
		s.initial_velocity_max = 0.0
	if "grav" in o: s.gravity = Vector3.ZERO
	if "damp" in o:
		s.damping_min = 0.0
		s.damping_max = 0.0
	add_child(s)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, 0, 5)
	for f in 30:
		await get_tree().process_frame
	s.emitting = true
	for f in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/one_%s_%d.png" % [OS.get_environment("S"), OS.get_environment("TAG"), f])
	get_tree().quit()

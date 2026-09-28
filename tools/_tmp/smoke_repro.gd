extends Node
# Temporary repro: one smoke emitter moving along a grey wall, toggled like CarEffects does.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().current_scene.queue_free()
	get_window().size = Vector2i(800, 450)
	var mode := OS.get_environment("MODE")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor.mesh = pm
	add_child(floor)
	if mode != "nowall":
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 1.2, 80)
		wall.mesh = bm
		wall.position = Vector3(2, 0.6, 0)
		add_child(wall)
	var fx := CarEffects.new(null)
	var sfx := Nfs3Sfx.shared(Game.data_root) if mode != "proc" else null
	var s: CPUParticles3D = fx._smoke_emitter(sfx)
	add_child(s)
	var v := OS.get_environment("VAR")
	if v == "noramp":
		s.color_ramp = null
	elif v == "alpha":
		s.color_ramp.set_color(0, Color(0.85, 0.85, 0.85, 0.3))
	elif v == "noscale":
		s.scale_amount_curve = null
	elif v == "nodamp":
		s.damping_min = 0.0
		s.damping_max = 0.0
	elif v == "nointerp":
		s.interpolate = false
	elif v == "nofract":
		s.fract_delta = false
	elif v == "fps":
		s.fixed_fps = 60
	elif v == "noangle":
		s.angle_max = 0.0
	print(v, " ramp ", s.color_ramp.offsets if s.color_ramp else [], " ", s.color_ramp.colors if s.color_ramp else [])
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(-3, 2.5, -12)
	cam.look_at(Vector3(1, 0.5, 0))
	var z := -8.0
	for f in 90:
		await get_tree().physics_frame
		z += float(OS.get_environment("STEP"))
		if true:
			s.global_position = Vector3(1.4, 0.4, z)
		s.emitting = f > 10 and OS.get_environment("VAR") != "never"
		if f in [5, 14, 30, 60]:
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/repro_%s_%s_%d.png" % [OS.get_environment("S"), mode, OS.get_environment("VAR"), f])
	get_tree().quit()

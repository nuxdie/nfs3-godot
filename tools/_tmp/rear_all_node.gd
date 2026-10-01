extends Node
## Which cars' in-car view gets a rear-view mirror: id, MIRROR/none, share of the view back, ms.
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var only := Array(OS.get_cmdline_user_args())
	var i := 0
	for c0 in Game.cars:
		i += 1
		var id: String = c0.id
		if not only.is_empty() and not only.any(func(p: String) -> bool: return id.begins_with(p)):
			continue
		var data: Object = Game.load_car(c0.path, i, 0)
		if data == null or data.error != "":
			continue
		var car := Car.new()
		car.setup(data)
		add_child(car)
		var t0 := Time.get_ticks_msec()
		if car.set_cockpit(true):
			var ms := Time.get_ticks_msec() - t0
			var rm: Node3D = car.get("_rear_mirror")
			var dd: Dictionary = car.get("_dash_data")
			var space: Node3D = car.get("_body_tilt") if dd.get("own_cabin", false) else car
			var eye: Vector3 = dd.eye if dd.get("own_cabin", false) else car.cockpit_eye()
			var mg: Dictionary = car._model_rear_glass(car._rear_mirror_tris(space, eye), eye)
			if not mg.is_empty():
				print("   model glass at ", mg.point, " eye ", eye, " box ", mg.box)
			print("%-14s %-34s %s share %.2f  %d ms" % [id, data.display_name, "MIRROR" if rm else "none", car._rear_view_share(space, eye), ms])
		car.free()
	get_tree().quit()

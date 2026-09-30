extends Node
## Renders a PU car's "driver" part alone, from outside, at a few steer angles:
##   godot --path . -s tools/_tmp/pu_arms.gd -- <car id> [--steer=-1,0,1] [--tag=NAME]
func _opt(args: Array, name: String, default: String) -> String:
	for a: String in args:
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return default

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var ids := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var steers := Array(_opt(args, "steer", "0").split(",")).map(func(s: String) -> float: return float(s))
	var tag := _opt(args, "tag", "arms")
	Game.scan_data()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.make_current()
	var w := 480
	var h := 480
	var _v0 := 0
	var views := [Vector3(0, 0.3, 1.3)]  # front, left side, above-behind
	var sheet := Image.create(w * views.size() * steers.size(), h * ids.size(), false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var i := Game.cars.find_custom(func(c: Dictionary) -> bool: return c.id == ids[row])
		if i < 0:
			print("no car ", ids[row]); continue
		var data: Object = Game.load_car(Game.cars[i].path, i)
		for bp in data.body_parts:
			if bp.has("steer_shapes"): print("shapes ", bp.steer_shapes)
		print("  pick ", data._geometry.get(9), " ", data._geometry.get(43), " ", data._geometry.get(56))
		var car := Car.new()
		car.setup(data)
		add_child(car)
		car.freeze = true
		car.set_physics_process(false)
		# hide everything except the driver
		var drv: MeshInstance3D = null
		for n in car.find_children("*", "MeshInstance3D", true, false):
			if n.material_override != null and n.material_override == car._driver_mat:
				drv = n
			else:
				n.visible = false
		if drv == null:
			print("no driver"); continue
		var c := drv.global_transform * drv.get_aabb().get_center() + Vector3(0, float(_opt(args, "dy", "0.25")), 0)
		print(ids[row], " driver aabb ", drv.get_aabb())
		var col := 0
		for s: float in steers:
			car.steer_angle = -s / 2.4 * car.max_steer * car.low_turn
			print("turn ", car.wheel_turn())
			for v: Vector3 in views:
				cam.global_position = c + v
				cam.look_at(c)
				for k in 6:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(w, h)
				sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * col, h * row))
				col += 1
		car.queue_free()
		await get_tree().process_frame
	sheet.save_png("res://shots/arms_%s.png" % tag)
	print("saved")
	get_tree().quit()

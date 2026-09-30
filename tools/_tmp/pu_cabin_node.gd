extends Node
## Photographs cars' in-car views in a plain studio, a row per car:
##   godot --path . -s tools/_tmp/pu_cabin.gd -- <car id> ... [--paints=0,3] [--looks=0,-60]
##       [--kmh=K] [--rpm=R] [--steer=-1..1] [--tag=NAME] [--pitch=DEG]
## Each shot: one paint (its index in the car's colours) and one head turn (+ left). --kmh and
## --rpm hold the dials there. Saves shots/cabin_<tag>.png.
func _ready() -> void:
	_run.call_deferred()


func _opt(args: Array, name: String, default: String) -> String:
	for a: String in args:
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return default


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var ids := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var paints := Array(_opt(args, "paints", "0").split(",")).map(func(s: String) -> int: return int(s))
	var looks := Array(_opt(args, "looks", "0").split(",")).map(func(s: String) -> float: return float(s))
	var kmh := float(_opt(args, "kmh", "0"))
	var rpm := float(_opt(args, "rpm", "0"))
	var steer := float(_opt(args, "steer", "0"))
	var pitch := float(_opt(args, "pitch", "-6"))
	var tag := _opt(args, "tag", "pu")
	Game.scan_data()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.36, 0.33)
	plane.material = fmat
	fm.mesh = plane
	floor.add_child(fm)
	add_child(floor)
	# Things to see in the mirrors: posts behind the car, a pole to each side.
	for p in [Vector3(-3, 1, -8), Vector3(0, 1, -12), Vector3(3, 1, -8), Vector3(-6, 1, -3), Vector3(6, 1, -3)]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 2.0, 0.6)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color.from_hsv(randf(), 0.8, 0.9)
		bm.material = pm
		post.mesh = bm
		post.position = p
		add_child(post)
	var cam := Camera3D.new()
	cam.fov = float(_opt(args, "fov", "72"))
	cam.cull_mask &= ~Car.OWN_VIEW_LAYER
	add_child(cam)
	cam.make_current()
	var w := 640
	var h := 360
	var sheet := Image.create(w * paints.size() * looks.size(), h * ids.size(), false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var i := Game.cars.find_custom(func(c: Dictionary) -> bool: return c.id == ids[row])
		if i < 0:
			print("no car ", ids[row])
			continue
		var data: Object = Game.load_car(Game.cars[i].path, i)
		if data == null:
			print("can't load ", ids[row])
			continue
		for bp in data.body_parts:
			if bp.has("needle"):
				print("  needle ", bp.name, " center ", bp.center, " axis ", bp.axis, " aabb ", (bp.mesh as Mesh).get_aabb())
		var car := Car.new()
		car.setup(data)
		car.handbrake = true
		add_child(car)
		car.reset_to(Transform3D(Basis(), Vector3(0, 0.05, 0)), 0.05)
		for k in 60:
			await get_tree().physics_frame
		car.freeze = true
		car.set_physics_process(false)
		car.steer = steer
		car.speed = kmh / 3.6
		car.rpm = rpm if rpm >= 0.0 else car.redline
		print("%s cockpit %s eye %s" % [ids[row], car.has_cockpit(), car.cockpit_eye()])
		car.set_cockpit(true)
		var col := 0
		for p: int in paints:
			if p < data.colours.size():
				car.set_paint(data.colours[p])
			for look: float in looks:
				cam.global_position = car.global_transform * car.cockpit_eye()
				cam.global_basis = car.global_basis * Basis(Vector3.UP, PI + deg_to_rad(look)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
				for k in 6:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(w, h)
				sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * col, h * row))
				col += 1
		car.queue_free()
		await get_tree().process_frame
	var file := "res://shots/cabin_%s.png" % tag
	sheet.save_png(file)
	print("saved ", file)
	get_tree().quit()

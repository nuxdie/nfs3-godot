extends Node
## Photographs cars in a plain studio, parked on their springs:
##   godot --path . -- --carshots [traffic|cops|cars|hstraffic|hscops|pu] [id ...] [--lights] [--big] [--low]
##       [--yaw=DEG ...] [--dist=M] [--wire] [--track=ID [--at=LAP FRACTION] [--night] [--weather]]
##       [--tag=NAME] [--siren] [--steer=-1..1]
## Each car is shot from the front and rear three-quarters (or from each --yaw, 0 = dead
## ahead); saves shots/cars_<tag>.png, a contact sheet with one row per car, and prints what
## the loader found in each model. Ids (folder names) pick cars from the set; --big shoots
## larger and closer, --low from near the ground, --wire adds a wireframe of each shot.
## --track parks the cars on that track's road instead, in its own light and conditions.
## --dent crashes each car into a front and a side corner first; --officer stands a High
## Stakes cruiser's officer beside it; --siren sets the light bar going. The set "heli" is High Stakes' helicopter.

var W := 480
var H := 300


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var set_name: String = pos[0] if pos.size() > 0 else "traffic"
	var tag := set_name
	var yaws: Array[float] = []
	var dist_opt := 0.0
	var track_id := ""
	var at := 0.05
	for a: String in args:
		if a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
		elif a.begins_with("--yaw="):
			yaws.append(float(a.get_slice("=", 1)))
		elif a.begins_with("--dist="):
			dist_opt = float(a.get_slice("=", 1))
		elif a.begins_with("--track="):
			track_id = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			at = float(a.get_slice("=", 1))
	if yaws.is_empty():
		yaws = [35.0, 215.0]
	var paths: Array = []
	match set_name:
		"cops": paths = Game.cop_cars
		"hscops": paths = Game.hs_cop_cars
		"hstraffic": paths = Game.hs_traffic_cars
		"heli": paths = [Game.hs_helicopter] if Game.hs_helicopter != "" else []
		"cars": paths = Game.cars.map(func(c): return c.path)
		"pu": paths = Game.cars.filter(func(c): return Game.is_pu_path(c.path)).map(func(c): return c.path)
		"pucops": paths = Game.pu_cop_cars
		"putraffic": paths = Game.pu_traffic_cars
		_: paths = Game.traffic_cars
	var ids := pos.slice(1)
	if not ids.is_empty():
		# Porsche Unleashed cars go by their car id (pu_993coupe36), the others by folder.
		var id_of := {}
		for c in Game.cars:
			id_of[c.path] = c.id
		paths = paths.filter(func(p: String) -> bool: return p.get_file() in ids or id_of.get(p, "") in ids)
	var lights := "--lights" in args
	var big := "--big" in args
	var low := "--low" in args
	var wire := "--wire" in args
	var night := "--night" in args
	if big:
		W = 1280
		H = 800

	get_window().size = Vector2i(W, H)
	# Where the car parks: the studio floor's origin, or a node on the track's road.
	var park := Transform3D()
	if track_id != "":
		Game.night = night
		Game.weather = "--weather" in args
		var w := TrackWorld.load_track(track_id, night)
		add_child(w.root)
		w.light(self, Game.night, Game.weather, get_viewport())
		var n := int(at * w.path.size()) % w.path.size()
		park = w.path.transform_at(n, 0.0, 0.0)
	else:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.42, 0.45, 0.5)
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.55, 0.65, 0.85)
		sky_mat.sky_horizon_color = Color(0.75, 0.78, 0.82)
		sky_mat.ground_horizon_color = Color(0.4, 0.4, 0.4)
		sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.2)
		env.sky = Sky.new()
		env.sky.sky_material = sky_mat
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.8
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 35, 0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		add_child(sun)
		var floor := StaticBody3D.new()
		floor.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40, 1, 40)
		cs.shape = box
		cs.position.y = -0.5
		floor.add_child(cs)
		var fm := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(40, 40)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.32)
		mat.roughness = 0.9
		plane.material = mat
		fm.mesh = plane
		floor.add_child(fm)
		add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 32
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()

	var cols := yaws.size() * (2 if wire else 1)
	var sheet := Image.create(W * cols, H * paths.size(), false, Image.FORMAT_RGBA8)
	for i in paths.size():
		if set_name == "heli":
			var heli := Helicopter.new()
			add_child(heli)
			heli.setup(Fce4.load_helicopter(paths[i]), null, park.origin + Vector3.UP * 2.5, night)
			heli.set_physics_process(false)
			var hd := 16.0 if dist_opt <= 0.0 else dist_opt
			var hcol := 0
			for yaw_deg in yaws:
				var yaw := deg_to_rad(yaw_deg)
				cam.global_position = heli.global_position + Vector3(sin(yaw), 0.25, cos(yaw)) * hd
				cam.look_at(heli.global_position, Vector3.UP)
				for k in 4:
					await get_tree().process_frame
				var himg := get_viewport().get_texture().get_image()
				himg.convert(Image.FORMAT_RGBA8)
				himg.resize(W, H)
				sheet.blit_rect(himg, Rect2i(0, 0, W, H), Vector2i(W * hcol, H * i))
				hcol += 1
			heli.queue_free()
			continue
		var data: Object = Game.load_car(paths[i], i)
		print("%-6s %-22s parts %d wheels %d popups %d lights %d colours %d tex %s half %s%s" % [
			paths[i].get_file(), data.display_name, data.body_parts.size(), data.wheels.size(),
			data.popup_lights.size(), data.lights.size(), data.colours.size(),
			data.texture.get_size() if data.texture else "none", data.half_size,
			"  ERROR " + data.error if data.error != "" else ""])
		var car := Car.new()
		car.setup(data)
		car.handbrake = true
		add_child(car)
		car.set_headlight_beam(night)
		car.reset_to(park, 0.05)
		car.set_headlights(lights or night)
		for k in 90:
			await get_tree().physics_frame
		car.freeze = true
		for a: String in args:
			if a.begins_with("--steer="):
				car.steer = float(a.get_slice("=", 1))
		if "--siren" in args:
			car.enable_siren(true)
		var hs: Vector3 = data.half_size
		if "--dent" in args:
			var dmg := CarDamage.new()
			car.add_child(dmg)
			await get_tree().physics_frame
			var xf := car.global_transform
			dmg.hit(xf * Vector3(hs.x * 0.7, 0.1, hs.z), xf.basis * Vector3(-0.3, 0, -1).normalized(), CarDamage.FULL_HIT)
			dmg.hit(xf * Vector3(-hs.x, 0.1, -hs.z * 0.4), xf.basis * Vector3.RIGHT, CarDamage.FULL_HIT)
			for k in 6:
				await get_tree().process_frame
		if "--officer" in args and car.officer_mesh:
			var off := MeshInstance3D.new()
			off.mesh = car.officer_mesh
			car.add_child(off)
			off.position = Vector3(hs.x + 0.8, 0.0, 0.3)
			off.global_position.y = park.origin.y
			off.rotation.y = -PI / 2
		var dist := dist_opt if dist_opt > 0.0 else hs.z * (2.2 if big else 3.4) + 3.0
		var col := 0
		for yaw_deg in yaws:
			var yaw := deg_to_rad(yaw_deg)
			var dir := car.global_basis * Vector3(sin(yaw), 0.0, cos(yaw))
			dir = Vector3(dir.x, 0.0, dir.z).normalized()
			cam.global_position = car.global_position + dir * dist + Vector3.UP * (0.3 if low else hs.y * 2.0 + 0.6)
			cam.look_at(car.global_position + Vector3.UP * 0.15, Vector3.UP)
			for mode in ([Viewport.DEBUG_DRAW_DISABLED, Viewport.DEBUG_DRAW_WIREFRAME] if wire else [Viewport.DEBUG_DRAW_DISABLED]):
				get_viewport().debug_draw = mode
				for k in 4:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(W, H)
				sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(W * col, H * i))
				col += 1
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
		car.queue_free()
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var file := "shots/cars_%s.png" % tag
	sheet.save_png(file)
	print("saved ", file)
	get_tree().quit()

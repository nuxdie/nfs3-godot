extends Node
## Photographs cars in a plain studio, parked on their springs:
##   godot --path . -- --carshots [traffic|cops|cars|hstraffic|hscops|pu|hp2|hp2cops|hp2traffic] [id ...] [--lights] [--big] [--low]
##       [--yaw=DEG ...] [--dist=M] [--wire] [--track=ID [--at=LAP FRACTION] [--night] [--weather]]
##       [--tag=NAME] [--siren] [--steer=-1..1]
## Each car is shot from the front and rear three-quarters (or from each --yaw, 0 = dead
## ahead); saves shots/cars_<tag>.png, a contact sheet with one row per car, and prints what
## the loader found in each model. Ids (folder names) pick cars from the set; --big shoots
## larger and closer, --low from near the ground, --wire adds a wireframe of each shot.
## --track parks the cars on that track's road instead, in its own light and conditions.
## --topup raises a Porsche Unleashed cabriolet's hood, --topat=T poses it mid-fold, --popat=T the pop-up headlamps mid-rise (0 down .. 1 up). --dent crashes each car into a front and a side corner first; --officer stands a High
## Stakes cruiser's officer beside it; --siren sets the light bar going. The set "heli" is High Stakes' helicopter.
## --wipeat=T, --spoilerat=T hold a Porsche Unleashed car's wipers or spoiler part-way (0 .. 1); --indicate=-1|1|2
## lights its left, right or all indicators. --open=6,7,8,9 opens its doors, bonnet, boot; --windows winds them down. --camy=M, --looky=M, --fov=DEG place the camera;
## --dent=N hits it N rounds (parts tear off), --tear=6,8,30 tears those groups off (Nfs5Car's).
## --eye=x,y,z:tx,ty,tz (car frame) puts it anywhere, looking at a point; --paint=N the car's colour N.
## --wheel=RAD holds the steering wheel turned; --cockpit shoots the in-car view (--rearmirror close on its rear-view mirror). --driver=N seats Porsche Unleashed driver N; --onlydriver hides all but the people.
## --dumpskin=PATH saves the car's skin as a PNG; --skin=PATH draws it with that one instead.
## --aa=msaa2|msaa4|msaa8|fxaa|smaa|none (comma-separated) overrides the view's antialiasing.

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
		"hp2": paths = Game.cars.filter(func(c): return Game.is_hp2_path(c.path)).map(func(c): return c.path)
		"hp2cops": paths = Game.hp2_cop_cars
		"hp2traffic": paths = Game.hp2_traffic_cars
		"proc": paths = ProceduralCar.PRESETS.map(func(_p): return "")
		_: paths = Game.traffic_cars
	var ids := pos.slice(1)
	if not ids.is_empty():
		# Porsche Unleashed cars go by their car id (pu_993coupe36), the others by folder.
		var id_of := {}
		for c in Game.cars:
			id_of[c.path] = c.id
		paths = paths.filter(func(p: String) -> bool: return p.get_file() in ids or id_of.get(p, "") in ids \
			or p.get_slice(":", 1) in ids)
	var lights := "--lights" in args
	var big := "--big" in args
	var low := "--low" in args
	var wire := "--wire" in args
	var night := "--night" in args
	if big:
		W = 1280
		H = 800

	get_window().size = Vector2i(W, H)
	for a: String in args:
		if a.begins_with("--aa="):   # msaa2|msaa4|msaa8|fxaa|smaa|none, comma-separated
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			for m in a.get_slice("=", 1).split(","):
				match m:
					"msaa2": get_viewport().msaa_3d = Viewport.MSAA_2X
					"msaa4": get_viewport().msaa_3d = Viewport.MSAA_4X
					"msaa8": get_viewport().msaa_3d = Viewport.MSAA_8X
					"fxaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
					"smaa": get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
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
		var who := 0
		for a: String in args:
			if a.begins_with("--driver="):   # Porsche Unleashed: that driver in the seat (1..10)
				who = int(a.get_slice("=", 1))
		var data: Object = Game.load_car(paths[i], i, who)
		print("%-6s %-22s parts %d wheels %d popups %d lights %d colours %d tex %s half %s%s" % [
			paths[i].get_file(), data.display_name, data.body_parts.size(), data.wheels.size(),
			data.popup_lights.size(), data.lights.size(), data.colours.size(),
			data.texture.get_size() if data.texture else "none", data.half_size,
			"  ERROR " + data.error if data.error != "" else ""])
		for a: String in args:
			if a.begins_with("--dumpskin=") and data.texture:
				data.texture.get_image().save_png(a.get_slice("=", 1))
			elif a.begins_with("--skin=") and data.texture:
				# A replacement skin (an upscale of a --dumpskin, any size), mipmapped as the loader does.
				var img := Image.load_from_file(a.get_slice("=", 1))
				img.convert(Image.FORMAT_RGBA8)
				img.generate_mipmaps()
				data.texture = ImageTexture.create_from_image(img)
		var car := Car.new()
		car.setup(data)
		car.handbrake = true
		add_child(car)
		car.set_headlight_beam(night)
		car.reset_to(park, 0.05)
		car.set_headlights(lights or night)
		for a: String in args:
			if a.begins_with("--shader="):   # draws the car with another copy of car.gdshader (experiments)
				var sh: Shader = load(a.get_slice("=", 1))
				for mi in car.find_children("*", "MeshInstance3D", true, false):
					var m := (mi as MeshInstance3D).material_override as ShaderMaterial
					if m and m.shader and m.shader.resource_path.ends_with("car.gdshader"):
						m.shader = sh
		for a: String in args:
			if a.begins_with("--paint=") and int(a.get_slice("=", 1)) < data.colours.size():   # a colour by index
				car.set_paint(data.colours[int(a.get_slice("=", 1))])
		for a: String in args:
			if a.begins_with("--hidehood="):   # hides a cabriolet's hood parts: up, down or top
				var which: String = a.get_slice("=", 1)
				for mi in (car._hood_up if which == "up" else car._hood_folded if which == "down" else car._hood_top):
					mi.visible = false
					mi.set_meta("hidden_probe", true)
		if "--topup" in args:
			car.set_top_down(false, true)
		for a: String in args:
			if a.begins_with("--topat="):   # a cabriolet's top mid-fold: 0 up .. frames - 1 folded
				car.fold_speed = 0.0
				car._top_t = float(a.get_slice("=", 1))
				car._pose_top()
		for k in 90:
			await get_tree().physics_frame
		car.freeze = true
		for a: String in args:
			if a.begins_with("--popat="):   # the pop-ups held part-way up
				car.set_process(false)
				car._popup_t = float(a.get_slice("=", 1))
				car._pose_popups()
				car._show_lamps()
		for a: String in args:
			# Porsche Unleashed's moving parts held part-way: the wipers (0 parked .. 1 top of the
			# sweep), the Carreras' spoiler (0 down .. 1 up); the indicators (-1, 1 a side, 2 all).
			if a.begins_with("--wipeat="):
				car.set_process(false)
				for w in car._wipers:
					Car._pose_frames(w[0], float(a.get_slice("=", 1)) * (w[1] - 1))
			elif a.begins_with("--spoilerat="):
				car.set_process(false)
				car._spoiler_t = float(a.get_slice("=", 1))
				car._pose_spoiler()
			elif a.begins_with("--open="):   # Porsche Unleashed: doors and lids open (6 left door, 7 right, 8 bonnet, 9 boot)
				for g in a.get_slice("=", 1).split(","):
					car.set_open(int(g), true, true)
			elif a == "--windows":
				for side in [6, 7]:
					car.set_window_down(side, true, true)
			elif a.begins_with("--indicate="):
				car.set_process(false)
				var side := int(a.get_slice("=", 1))
				for sg in car._signals:
					sg[0].visible = side == 2 or side == sg[1]
		for a: String in args:
			if a.begins_with("--steer="):
				car.steer = float(a.get_slice("=", 1))
			elif a.begins_with("--wheel="):   # the steering wheel and the driver's hands held turned (radians, + clockwise)
				car.set_process(false)
				for m in car._steer_mats:
					m.set_shader_parameter("steer_angle", float(a.get_slice("=", 1)))
				for sh in car._steer_shapes:
					Car._pose_steer_shapes(sh[0], sh[1], float(a.get_slice("=", 1)))
		if "--siren" in args:
			car.enable_siren(true)
		if "--onlydriver" in args:   # hides all but the people (their material is car_driver's)
			for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
				var m := mi.get_active_material(0) as ShaderMaterial
				if m == null or not m.shader.resource_path.ends_with("car_driver.gdshader"):
					mi.visible = false
		var hs: Vector3 = data.half_size
		var dents := 0
		for a: String in args:
			if a == "--dent":
				dents = 1
			elif a.begins_with("--dent="):   # that many rounds of the two hits (parts tear off)
				dents = int(a.get_slice("=", 1))
		if dents > 0:
			var dmg := CarDamage.new()
			car.add_child(dmg)
			await get_tree().physics_frame
			var xf := car.global_transform
			for k in dents:
				dmg.hit(xf * Vector3(hs.x * 0.7, 0.1, hs.z), xf.basis * Vector3(-0.3, 0, -1).normalized(), CarDamage.FULL_HIT)
				dmg.hit(xf * Vector3(-hs.x, 0.1, -hs.z * 0.4), xf.basis * Vector3.RIGHT, CarDamage.FULL_HIT)
				dmg._cooldown = 0.0
			for k in 6 if dents == 1 else 90:   # (what tore off, time to land)
				await get_tree().physics_frame
		for a: String in args:
			if a.begins_with("--tear="):   # Porsche Unleashed: tear these groups off (Car.tear_off)
				for g in a.get_slice("=", 1).split(","):
					car.tear_off(int(g))
				for k in 90:
					await get_tree().physics_frame
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
			var cam_y := 0.3 if low else hs.y * 2.0 + 0.6
			var look_y := 0.15
			for a: String in args:
				if a.begins_with("--camy="):   # the camera's height over the car's origin (m)
					cam_y = float(a.get_slice("=", 1))
				elif a.begins_with("--looky="):   # the height it looks at
					look_y = float(a.get_slice("=", 1))
				elif a.begins_with("--fov="):
					cam.fov = float(a.get_slice("=", 1))
			cam.global_position = car.global_position + dir * dist + Vector3.UP * cam_y
			cam.look_at(car.global_position + Vector3.UP * look_y, Vector3.UP)
			if "--cockpit" in args and car.set_cockpit(true):   # the in-car view, from the driver's eye
				var ce := car.cockpit_eye()
				cam.global_position = car.global_transform * ce
				cam.look_at(car.global_transform * (ce + Vector3(0.0, -0.3, 1.0)), Vector3.UP)
				var rm: Node3D = car.get("_rear_mirror")
				if "--rearmirror" in args and rm:   # close on the rear-view mirror
					var glass := rm.find_children("*", "MeshInstance3D", false, false)
					if not glass.is_empty():
						cam.fov = 14.0
						cam.look_at((glass[0] as MeshInstance3D).global_transform * (glass[0] as MeshInstance3D).get_aabb().get_center(), Vector3.UP)
			for a: String in args:
				if a.begins_with("--eye="):   # --eye=x,y,z:tx,ty,tz in the car's own frame (+z ahead, +x left)
					var ab := a.get_slice("=", 1).split(":")
					var e := ab[0].split_floats(","); var t := ab[1].split_floats(",")
					cam.global_position = car.global_transform * Vector3(e[0], e[1], e[2])
					cam.look_at(car.global_transform * Vector3(t[0], t[1], t[2]), Vector3.UP)
			for mode in ([Viewport.DEBUG_DRAW_DISABLED, Viewport.DEBUG_DRAW_WIREFRAME] if wire else [Viewport.DEBUG_DRAW_DISABLED]):
				get_viewport().debug_draw = mode
				for k in 4:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				for pa: String in args:
					if pa.begins_with("--pick="):   # names the parts under a pixel (x,y of the shot)
						_pick(cam, car, data, pa.get_slice("=", 1).split_floats(","))
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


## Prints the body parts a ray through pixel (x, y) crosses, nearest first, and the UV there.
func _pick(cam: Camera3D, car: Node3D, data: Object, xy: PackedFloat64Array) -> void:
	var px := Vector2(xy[0], xy[1]) * Vector2(get_viewport().get_visible_rect().size) / Vector2(W, H)
	var from := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px)
	var hits := []
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or mi.mesh == null:
			continue
		var pname := "?"
		for bp in data.body_parts:
			if bp.mesh == mi.mesh:
				pname = str(bp.name)
		var xf: Transform3D = mi.global_transform
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(pos.size()))
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		for t in range(0, idx.size() - 2, 3):
			var a := xf * pos[idx[t]]
			var b := xf * pos[idx[t + 1]]
			var c := xf * pos[idx[t + 2]]
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if hit != null:
				var uv := uvs[idx[t]] if not uvs.is_empty() else Vector2.ZERO
				hits.append([from.distance_to(hit), pname, t / 3, uv, car.to_local(hit)])
	hits.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var tex: Image = data.texture.get_image() if data.texture else null
	for h in hits:
		var texel := Color()
		if tex:
			texel = tex.get_pixelv(Vector2i((h[3] as Vector2) * Vector2(tex.get_size() - Vector2i.ONE)))
		print("pick %.3f m  %s  tri %d  uv %s  at %s  texel %s" % (h + [texel]))


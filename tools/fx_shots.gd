extends Node
## Photographs a car's effects in staged moments on a track, without a race:
##   godot --path . -- --fxshots [track] [--at=FRACTION] [--car=N] [--night] [--weather]
##       [--only=NAME,...] [--tag=NAME]
## Scenes: "slide" (a handbrake turn on the road: smoke and rubber), "marks" (the rubber it
## left, from above), "dust" (driving on the verge), "scrape" (along a wall: sparks), "crash"
## (nose into it). Saves shots/fx_<tag><scene>_<k>.png, a few frames apart.

const W := 960
const H := 540

var _world: TrackWorld
var _marks: SkidMarks
var _cam: Camera3D
var _tag := ""
var _car_index := 0
var _only: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().current_scene.queue_free()
	get_window().size = Vector2i(W, H)
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var id: String = pos[0] if pos.size() > 0 else Game.tracks[0]
	var at := 0.05
	for a: String in args:
		if a.begins_with("--at="):
			at = float(a.get_slice("=", 1))
		elif a.begins_with("--car="):
			_car_index = int(a.get_slice("=", 1))
		elif a.begins_with("--tag="):
			_tag = a.get_slice("=", 1) + "_"
		elif a.begins_with("--only="):
			_only = a.get_slice("=", 1).split(",")
	Game.night = "--night" in args
	Game.weather = "--weather" in args
	_world = TrackWorld.load_track(id)
	add_child(_world.root)
	_world.light(self, Game.night, Game.weather, get_viewport())
	var sfx := Nfs3Sfx.shared(Game.data_root)
	_marks = SkidMarks.new(2048, sfx.skid_atlas if sfx else null)
	add_child(_marks)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))

	var n := int(at * _world.path.size()) % _world.path.size()
	if _want("slide") or _want("marks"):
		await _slide(n)
	if _want("dust"):
		await _dust(n)
	if _want("scrape"):
		await _wall(n, false)
	if _want("crash"):
		await _wall(n, true)
	get_tree().quit()


func _want(scene: String) -> bool:
	return _only.is_empty() or scene in _only


func _make_car(xf: Transform3D, speed: float) -> Car:
	var c := Car.new()
	c.setup(Game.load_car(Game.cars[_car_index].path, _car_index))
	c.is_player = true
	c.set_headlight_beam(Game.night)
	add_child(c)
	c.add_child(CarEffects.new(_marks))
	for p: CPUParticles3D in c.find_children("*", "CPUParticles3D", true, false):
		if OS.get_environment("FXHIDE") == "all" or String(p.name) in OS.get_environment("FXHIDE").split(",") or p.name.trim_prefix("@").get_slice("@", 0).rstrip("0123456789") in OS.get_environment("FXHIDE").split(","):
			p.visible = false
			print("hidden ", p.name)
	if Game.damage:
		c.add_child(CarDamage.new())
	c.reset_to(xf, 0.05)
	c.set_headlights(Game.night)
	for k in 30:
		await get_tree().physics_frame
	c.linear_velocity = c.global_basis.z * speed
	c.gear = 3
	return c


## Chase view from `back` m behind and `side` m to the right of the car's heading, `up` m up.
func _frame(c: Car, back: float, side: float, up: float) -> void:
	var fwd := c.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	_cam.global_position = c.global_position - fwd * back + right * side + Vector3.UP * up
	_cam.look_at(c.global_position + Vector3.UP * 0.4, Vector3.UP)


func _shoot(scene: String, k: int, c: Car = null) -> void:
	await get_tree().process_frame
	if c:
		print("  %s_%d  %d km/h  slip %s" % [scene, k, c.kmh(),
			" ".join(c.wheel_states().map(func(w): return "%.2f" % w.slip))])
	var file := "shots/fx_%s%s_%d.png" % [_tag, scene, k]
	get_viewport().get_texture().get_image().save_png(file)
	print("shot ", file)


## Run the car for `frames` physics frames, framing it each one.
func _roll(c: Car, frames: int, back: float, side: float, up: float) -> void:
	for f in frames:
		await get_tree().physics_frame
		if OS.has_environment("FXDEBUG"):
			for p: CPUParticles3D in c.find_children("*", "CPUParticles3D", true, false):
				if p.emitting:
					print("    emit %s amount %d color %s at %s" % [p.name, p.amount, p.color, p.global_position])
		_frame(c, back, side, up)


func _slide(n: int) -> void:
	var c := await _make_car(_world.path.transform_at(n, 0.0, 0.3), 26.0)
	c.throttle = 0.6
	await _roll(c, 20, 6.2, 1.5, 1.9)
	c.handbrake = true
	c.steer = 1.0
	for k in 4:
		await _roll(c, 14, 6.2, 1.5, 1.9)
		if _want("slide"):
			await _shoot("slide", k, c)
	c.handbrake = false
	c.throttle = 1.0
	c.steer = -0.3
	await _roll(c, 30, 6.2, 1.5, 1.9)
	if _want("slide"):
		await _shoot("slide", 4, c)
	if _want("marks"):
		# The rubber, from above and from low down the road behind.
		var p := _world.path.points[n] + _world.path.forward(n) * 18.0
		_cam.global_position = p + Vector3.UP * 14.0 - _world.path.forward(n) * 10.0
		_cam.look_at(p, Vector3.UP)
		c.visible = false
		await _shoot("marks", 0)
		_cam.global_position = p - _world.path.forward(n) * 12.0 + Vector3.UP * 1.6
		_cam.look_at(p + _world.path.forward(n) * 6.0, Vector3.UP)
		await _shoot("marks", 1)
	c.queue_free()


func _dust(n: int) -> void:
	# The verge: past whichever edge of the road has loose ground under it.
	var side := 0.0
	for s in [1.0, -1.0]:
		for extra in [1.5, 3.0, 5.0]:
			var off: float = s * ((_world.path.right_width[n] if s > 0 else _world.path.left_width[n]) - extra)
			var p := _world.path.transform_at(n, off, 1.0).origin
			var q := PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 4.0)
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			if not hit.is_empty() and TrackSurface.dust(hit.collider, hit.shape, hit.get("face_index", -1)).a > 0.0:
				side = off
				break
		if side != 0.0:
			break
	print("dust: verge at ", side)
	var c := await _make_car(_world.path.transform_at(n, side, 0.3), 18.0)
	c.throttle = 0.8
	for k in 3:
		await _roll(c, 25, 6.2, -1.5, 1.9)
		await _shoot("dust", k, c)
	c.steer = 0.6
	await _roll(c, 20, 6.2, -1.5, 1.9)
	await _shoot("dust", 3, c)
	c.queue_free()


## A wall along the road's right edge; `crash` drives into it head on rather than along it.
func _wall(n: int, crash: bool) -> void:
	var fwd := _world.path.forward(n)
	var right := _world.path.rights[n]
	var xf := _world.path.transform_at(n, 0.0, 0.0)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.2, 80.0)
	cs.shape = box
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	wall.add_child(mi)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), xf.origin + right * 3.0 + fwd * 36.0 + Vector3.UP * 0.6)
	var c: Car
	if crash:
		var cx := Transform3D(Basis.looking_at(-right, Vector3.UP), xf.origin + fwd * 20.0 - right * 6.0 + Vector3.UP * 0.3)
		c = await _make_car(cx, 18.0)
		c.throttle = 0.5
		for k in 4:
			await _roll(c, 3 if k > 0 else 17, 7.0, -3.0, 2.0)
			await _shoot("crash", k, c)
	else:
		c = await _make_car(_world.path.transform_at(n, 1.2, 0.3), 24.0)
		c.throttle = 0.8
		c.steer = 0.35
		await _roll(c, 20, 9.0, -3.0, 2.2)
		for k in 4:
			await _roll(c, 8, 9.0, -3.0, 2.2)
			await _shoot("scrape", k, c)
	c.queue_free()
	wall.queue_free()

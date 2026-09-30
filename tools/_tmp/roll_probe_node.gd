extends Node
## Body roll probe: skidpad at 30 m/s, then a lane flick, then hard braking from 35 m/s.
## Per car: physical roll/pitch of the rigid body, visual sway on top, their sum, and the
## worst arch gap per wheel (negative = tyre through the body; big = wheel hangs "lifted").

var runs: Array = []
var t := 0.0

func _ready() -> void:
	process_physics_priority = -20
	_start.call_deferred()

func _start() -> void:
	print("start ", get_node("/root/Game").cars.size())
	var game: Node = get_node("/root/Game")
	var args := Array(OS.get_cmdline_user_args())
	var world := Node3D.new()
	add_child(world)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20000, 1, 20000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(-9000, 5, -9000)
	cam.current = true
	var col := 0
	for c: Dictionary in game.cars:
		var name: String = c.name
		if args.size() > 0 and not args.any(func(f: String) -> bool: return name.to_lower().contains(f.to_lower())):
			continue
		var data: Object = game.load_car(c.path)
		for test in ["skid", "flick", "brake"]:
			var car := Car.new()
			car.setup(data)
			world.add_child(car)
			var p := Vector3(-9000 + col * 300, 0, -9000 + ["skid", "flick", "brake"].find(test) * 3000)
			car.reset_to(Transform3D(Basis.IDENTITY, p))
			runs.append({"car": car, "name": name, "test": test, "phase": 0, "t0": 0.0,
				"phys": 0.0, "vis": 0.0, "tot": 0.0, "gmin": INF, "gmax": -INF, "g0": INF, "lat": 0.0, "sink": 0.0})
		col += 1

func _gap(car: Car, w: Dictionary) -> float:
	# Room over the tyre in the model, less the wheel's rise above where it's modelled,
	# plus how far the arch moved with the visual tilt.
	var r0: float = w.lift_max - Car.STATIC_SAG
	var rise: float = w.visual.position.y - (w.center.y + Car.STATIC_SAG)
	var arch: Vector3 = Vector3(w.center.x, w.center.y + w.radius, w.center.z)
	var moved: Vector3 = car._body_tilt.transform * arch
	return r0 - rise + (moved.y - arch.y)

func _physics_process(dt: float) -> void:
	if runs.is_empty():
		return
	t += dt
	var done := true
	for r in runs:
		if r.phase >= 99:
			continue
		done = false
		var car: Car = r.car
		if r.t0 == 0.0 and r.phase == 0:
			r.t0 = -1.0
			print("run ", r.name, " ", r.test)
			t = 0.0
			car.freeze = false
		# keep the camera near so the car isn't "far"
		get_viewport().get_camera_3d().global_position = car.global_position + Vector3(0, 5, 10)
		_one(r, dt)
		break
	if done:
		_report()

func _one(r: Dictionary, dt: float) -> void:
		var car: Car = r.car
		var lt: float = t - r.t0
		var b := car.global_basis
		var roll := rad_to_deg(asin(clampf(b.x.y, -1, 1)))
		var pitch := rad_to_deg(asin(clampf(b.z.y, -1, 1)))
		var vroll := rad_to_deg(car._tilt.y)
		var vpitch := rad_to_deg(car._tilt.x)
		var measure := false
		match r.test:
			"skid", "flick":
				if r.phase == 0:
					car.steer = 0.0
					car.throttle = clampf((31.0 - car.speed) * 0.6, 0, 1)
					if car.speed > 29.0 and t > 1.0 or t > 25.0:
						r.phase = 1; r.t0 = t
						for w in car._wheels:
							r.g0 = minf(r.g0, _gap(car, w))
				else:
					car.throttle = clampf((30.0 - car.speed) * 0.6, 0, 1)
					if r.test == "skid":
						car.steer = 1.0
						measure = lt > 3.0
						if lt > 3.0:
							r.lat = maxf(r.lat, car.linear_velocity.length() * absf(car.angular_velocity.y) / 9.81)
					else:
						car.steer = 1.0 if lt < 0.6 else (-1.0 if lt < 1.2 else 0.0)
						measure = true
					if lt > 5.0: r.phase = 99
				if measure:
					r.phys = maxf(r.phys, absf(roll)); r.vis = maxf(r.vis, absf(vroll)); r.tot = maxf(r.tot, absf(roll + vroll))
			"brake":
				if r.phase == 0:
					car.steer = 0.0
					car.throttle = clampf((36.0 - car.speed) * 0.6, 0, 1)
					if car.speed > 35.0 and t > 1.0 or t > 30.0:
						r.phase = 1; r.t0 = t
				else:
					car.throttle = 0.0; car.brake = 1.0
					measure = true
					r.phys = maxf(r.phys, absf(pitch)); r.vis = maxf(r.vis, absf(vpitch)); r.tot = maxf(r.tot, absf(vpitch - pitch))
					if car.speed < 1.0 or lt > 5.0: r.phase = 99
		if measure:
			for w in car._wheels:
				var g := _gap(car, w)
				r.gmin = minf(r.gmin, g); r.gmax = maxf(r.gmax, g)
				r.sink = maxf(r.sink, w.center.y + w.compression - w.visual.position.y)

func _report() -> void:
		print("report")
		print("car                     test   latg  phys  vis   total   gap rest/min/max (cm)  sink")
		for r in runs:
			print("%-22s %-6s %4.2f %5.1f %5.1f %6.1f   %5.1f %5.1f %5.1f  %4.1f" % [r.name.substr(0, 22), r.test, r.lat, r.phys, r.vis, r.tot, r.g0 * 100, r.gmin * 100, r.gmax * 100, r.sink * 100])
		get_tree().quit()

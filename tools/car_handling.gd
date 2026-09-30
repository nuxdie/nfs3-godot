extends Node
## Handling tests of cars on an endless flat, all at once (a copy of each car per test):
##   skid V   holds V m/s on full lock for 6 s: lateral g, body slip (deg), speed kept
##   lane     a lane change at 30 m/s: the most body slip, the yaw rate left 2 s later
##   trail    full lock and full brakes from 35 m/s for 1.5 s, then off: most body slip
##   power    full lock and full throttle from 10 m/s for 3 s: most body slip
##   brake    100-0 km/h: metres, and the heading it wandered off (deg)
##   hand     full lock and the handbrake at 25 m/s for 1 s, then straight: most body slip,
##            and the yaw rate left 2 s after letting go
## --classic runs them on the plain NFS3 handling (see Car.progressive_grip).
## A body slip past 60 degrees counts as a spin ("SPIN").
##   godot --headless --path . -- --handling [name filter ...]

const TESTS := ["skid20", "skid40", "lane", "trail", "power", "brake", "hand"]

var _runs: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	process_physics_priority = -20
	_start.call_deferred()


func _start() -> void:
	var game := get_parent()
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	Car.progressive_grip = not "--classic" in args
	var filters := args.slice(args.find("--handling") + 1).filter(func(a: String) -> bool: return not a.begins_with("--"))
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
	var col := 0
	for c: Dictionary in game.cars:
		var name: String = c.name
		if not filters.is_empty() and not filters.any(func(f: String) -> bool: return name.to_lower().contains(f.to_lower())):
			continue
		var data: Object = game.load_car(c.path)
		for ti in TESTS.size():
			var car := Car.new()
			car.setup(data)
			world.add_child(car)
			car.reset_to(Transform3D(Basis.IDENTITY, Vector3(-9000 + col * 300, 0, -9000 + ti * 3000)))
			_runs.append({"car": car, "name": name, "test": TESTS[ti], "phase": 0, "t0": 0.0,
				"lat": 0.0, "n": 0, "beta": 0.0, "max_beta": 0.0, "v_end": 0.0, "yaw_end": 0.0,
				"x0": Vector3.ZERO, "dist": 0.0, "head0": Vector3.ZERO, "wander": 0.0, "spun": false})
		col += 1
		if col > 55:
			break


func _physics_process(dt: float) -> void:
	if _runs.is_empty():
		return
	_t += dt
	var done := true
	for r in _runs:
		if r.phase >= 99:
			continue
		done = false
		_step(r, dt)
	if done or _t > 60.0:
		_report()
		get_tree().quit()


func _beta(car: Car) -> float:
	var v := car.linear_velocity
	if v.length() < 2.0:
		return 0.0
	return rad_to_deg(atan2(v.dot(car.global_basis.x), absf(v.dot(car.global_basis.z))))


## Cruise control: throttle and brake towards v, straight ahead.
func _hold(car: Car, v: float) -> void:
	car.throttle = clampf((v + 1.0 - car.speed) * 0.6, 0.0, 1.0)
	car.brake = clampf((car.speed - v) * 0.3, 0.0, 1.0) if car.speed > v + 2.0 else 0.0


func _step(r: Dictionary, dt: float) -> void:
	var car: Car = r.car
	var t: float = _t - r.t0
	var b := _beta(car)
	if absf(b) > 60.0:
		r.spun = true
	match r.test:
		"skid20", "skid40":
			var v := 20.0 if r.test == "skid20" else 40.0
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, v)
				if car.speed >= v - 1.5 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
			else:
				car.steer = 1.0
				car.throttle = clampf((v - car.speed) * 0.6, 0.0, 1.0)
				car.brake = 0.0
				if t > 4.0:
					# Steady state: the lateral acceleration is the speed times the yaw rate.
					r.lat += car.linear_velocity.length() * absf(car.angular_velocity.y) / 9.81
					r.beta += absf(b)
					r.n += 1
				if t > 6.0:
					r.v_end = car.speed
					r.phase = 99
		"lane":
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, 30.0)
				if car.speed >= 30.0 - 1.5 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
			else:
				_hold(car, 30.0)
				car.steer = 1.0 if t < 0.6 else (-1.0 if t < 1.2 else 0.0)
				r.max_beta = maxf(r.max_beta, absf(b))
				if t > 3.2:
					r.yaw_end = rad_to_deg(absf(car.angular_velocity.y))
					r.phase = 99
		"trail":
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, 35.0)
				if car.speed >= 35.0 - 1.5 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
			else:
				car.throttle = 0.0
				car.brake = 1.0 if t < 1.5 else 0.0
				car.steer = 1.0
				r.max_beta = maxf(r.max_beta, absf(b))
				if t > 3.5:
					r.phase = 99
		"power":
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, 10.0)
				if car.speed >= 10.0 - 1.5 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
			else:
				car.throttle = 1.0
				car.brake = 0.0
				car.steer = 1.0
				r.max_beta = maxf(r.max_beta, absf(b))
				if t > 3.0:
					r.phase = 99
		"hand":
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, 25.0)
				if car.speed >= 25.0 - 1.5 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
			else:
				car.throttle = 0.0
				car.brake = 0.0
				car.handbrake = t < 1.0
				car.steer = 1.0 if t < 1.0 else 0.0
				r.max_beta = maxf(r.max_beta, absf(b))
				if t > 3.0:
					r.yaw_end = rad_to_deg(absf(car.angular_velocity.y))
					car.handbrake = false
					r.phase = 99
		"brake":
			if r.phase == 0:
				car.steer = 0.0
				_hold(car, 29.5)
				if car.speed >= 27.78 and _t > 1.0 or _t > 25.0:
					r.phase = 1
					r.t0 = _t
					r.x0 = car.global_position
					r.head0 = car.global_basis.z
			else:
				car.throttle = 0.0
				car.brake = 1.0
				car.steer = 0.0
				if car.speed < 0.3:
					r.dist = car.global_position.distance_to(r.x0)
					r.wander = rad_to_deg(r.head0.angle_to(car.global_basis.z))
					r.phase = 99


func _report() -> void:
	var by_car := {}
	for r in _runs:
		if not by_car.has(r.name):
			by_car[r.name] = {}
		by_car[r.name][r.test] = r
	for r in _runs:
		if r.phase < 99:
			print("unfinished %s %s phase %d speed %.1f gear %d rpm %d grounded %d pos %s" % [r.name, r.test, r.phase, r.car.speed, r.car.gear, r.car.rpm, r.car.grounded_wheels, r.car.global_position])
	print("car                    skid20 g/slip/v/ai    skid40 g/slip/v/ai      lane slip/yaw  trail slip  power slip  brake m/deg  hand slip/yaw")
	for n: String in by_car:
		var d: Dictionary = by_car[n]
		var line := "%-22s" % n.substr(0, 22)
		for k in ["skid20", "skid40"]:
			var r: Dictionary = d[k]
			var cnt := maxi(r.n, 1)
			# Against what the AI takes the car to hold (see AIController._corner_speed).
			var c: Car = r.car
			var v := 20.0 if k == "skid20" else 40.0
			var ai := 1.25 * c.corner_grip() * (1.0 + clampf(v * v * c.downforce_k, 0.0, 0.9) * 0.5)
			line += " %4.2f/%4.1f/%4.1f/%3d%%%s" % [r.lat / cnt, r.beta / cnt, r.v_end, roundi(r.lat / cnt / ai * 100.0), "S" if r.spun else " "]
		line += "   %5.1f/%5.1f%s" % [d.lane.max_beta, d.lane.yaw_end, "S" if d.lane.spun else " "]
		line += "   %5.1f%s" % [d.trail.max_beta, "S" if d.trail.spun else " "]
		line += "     %5.1f%s" % [d.power.max_beta, "S" if d.power.spun else " "]
		line += "     %5.1f/%4.1f" % [d.brake.dist, d.brake.wander]
		line += "   %5.1f/%5.1f%s" % [d.hand.max_beta, d.hand.yaw_end, "S" if d.hand.spun else " "]
		print(line)
		var c0: Car = d.skid20.car
		print("  spec %s grip=%.4f wf=%.4f dk=%.7f fg=%.4f" % [n, c0.grip, c0.weight_front, c0.downforce_k, c0.front_grip])

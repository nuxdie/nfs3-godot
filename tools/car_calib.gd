extends SceneTree
## Flat-out drag test of every car on an endless flat, set against the original game's own
## acceleration table (carp.txt fields 67..74, m/s^2 at every 1 m/s): prints 0-100 km/h,
## 0-200 km/h and the top speed reached, then the acceleration at a few speeds, "sim/orig".
##   godot --headless --path . -s tools/car_calib.gd [-- name-filter]

const SECS := 70.0
const SPEEDS := [5, 15, 25, 35, 45, 55, 65, 75, 85]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = root.get_node("Game")
	var filter := ""
	if not OS.get_cmdline_user_args().is_empty():
		filter = OS.get_cmdline_user_args()[0].to_lower()
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 12000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 5900)
	ground.add_child(cs)
	world.add_child(ground)
	var runs := []
	for c in game.cars:
		if filter != "" and not c.name.to_lower().contains(filter):
			continue
		var car := Car.new()
		car.setup(game.load_car(c.path))
		world.add_child(car)
		car.global_position = Vector3(-900 + runs.size() * 40, 1.0, 0)
		runs.append({"car": car, "name": c.name, "t": PackedFloat32Array(), "t100": -1.0, "t200": -1.0})
	for k in 60:
		await physics_frame
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	while t < SECS:
		for r in runs:
			r.car.throttle = 1.0
			r.car.steer = 0.0
		await physics_frame
		t += dt
		for r in runs:
			var v: float = r.car.speed
			var times: PackedFloat32Array = r.t
			# Time the car first reached each whole m/s.
			while times.size() <= int(v):
				times.append(t)
			r.t = times
			if r.t100 < 0.0 and v >= 27.78:
				r.t100 = t
			if r.t200 < 0.0 and v >= 55.56:
				r.t200 = t
	for r in runs:
		var car: Car = r.car
		var times: PackedFloat32Array = r.t
		var line := "%-22s 0-100 %5.2fs (orig %5.2fs)  0-200 %5.2fs  top %3d/%3d km/h  drag %.2f |" % [
			r.name.substr(0, 22), r.t100, _orig_t(car.ai_accel, 27.78), r.t200,
			roundi(car.speed * 3.6), roundi(car.top_speed * 3.6), car.drag_k]
		for s in SPEEDS:
			var sim := 1.0 / (times[s + 1] - times[s]) if times.size() > s + 1 else 0.0
			var orig := car.ai_accel[s] if car.ai_accel.size() > s else 0.0
			line += " %d:%.1f/%.1f" % [s, sim, orig]
		print(line)
	quit()


## Time to `v` m/s by the original acceleration table.
static func _orig_t(acc: PackedFloat32Array, v: float) -> float:
	if acc.size() < ceili(v):
		return -1.0
	var t := 0.0
	for i in ceili(v):
		t += minf(v - i, 1.0) / maxf(acc[i], 0.3)
	return t

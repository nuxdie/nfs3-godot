class_name ParkedCars
extends RefCounted
## Real cars parked where the procedural track's places leave room for them (the root's
## "parking" meta: Transform3Ds on the ground, nose along +Z): the same cars and colours the
## traffic uses, handbrake on. So they cost next to nothing standing there, each settles on
## its springs, then is frozen until another car comes into touching distance, when it wakes
## as a car like any other, to be shunted, dented and knocked about.

const DRAW_DISTANCE := 300.0
const SETTLE := 2.0          # s on its springs before it's frozen where it stands
const WAKE_MARGIN := 0.6     # m round its body that another car wakes it from


## Parks a car at each spot, made by `make_car` (the race's: data, tint -> Car).
static func spawn(tree: SceneTree, make_car: Callable, spots: Array) -> Array[Car]:
	var out: Array[Car] = []
	for xf: Transform3D in spots:
		var data: Object
		var tint := Color(0, 0, 0, 0)
		if Game.traffic_cars.size() > 0:
			data = Game.load_car(Game.traffic_cars[randi() % Game.traffic_cars.size()], 4)
		else:
			# The traffic's stand-in: its sedan, in any colour.
			data = Game.load_car("", 4)
			tint = Color.from_hsv(randf(), 0.4, 0.8)
		var car: Car = make_car.call(data, tint)
		car.reset_to(xf, 0.05)
		car.handbrake = true
		car.brake = 1.0
		for g in car.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = DRAW_DISTANCE * (0.5 if Game.quality == Game.Quality.LOW else 1.0)
		_sleep_later(tree, car)
		out.append(car)
	return out


static func _sleep_later(tree: SceneTree, car: Car) -> void:
	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 2   # cars
	trigger.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = car._half_size * 2.0 + Vector3.ONE * WAKE_MARGIN * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	trigger.add_child(cs)
	car.add_child(trigger)
	var state := {"awake": false}
	trigger.body_entered.connect(func(body: Node3D) -> void:
		if body == car or not body is Car or state.awake:
			return
		state.awake = true
		trigger.queue_free.call_deferred()
		_wake.call_deferred(car))
	tree.create_timer(SETTLE, false, true).timeout.connect(func() -> void:
		if is_instance_valid(car) and not state.awake:
			car.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			car.freeze = true
			car.set_physics_process(false))


static func _wake(car: Car) -> void:
	if not is_instance_valid(car):
		return
	car.freeze = false
	car.set_physics_process(true)

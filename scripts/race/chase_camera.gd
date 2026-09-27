class_name ChaseCamera
extends Camera3D
## Follows a car. Modes cycle with the "camera" action: near chase, far chase,
## bumper. Hold "look_back" to look behind.

const MODES := [
	{"name": "Chase", "dist": 6.2, "height": 1.9, "look": 1.0, "fov": 68.0},
	{"name": "Far", "dist": 10.5, "height": 3.2, "look": 1.2, "fov": 64.0},
	{"name": "Bumper", "dist": -0.4, "height": 0.75, "look": 0.7, "fov": 75.0},
]

var target: Car
var mode := 0
var _pos := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _init_done := false


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("camera"):
		mode = (mode + 1) % MODES.size()
		_init_done = false


func _physics_process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var m: Dictionary = MODES[mode]
	var car_fwd := target.global_basis.z
	var vel := target.linear_velocity
	# Follow the velocity direction when moving so drifts are visible, like the classics.
	var flat_vel := Vector3(vel.x, 0, vel.z)
	var dir := car_fwd
	if flat_vel.length() > 6.0 and target.speed > 0.0 and m.dist > 0.0:
		dir = car_fwd.slerp(flat_vel.normalized(), 0.35).normalized()
	var back := Input.is_action_pressed("look_back")
	if back:
		dir = -dir
	if not _init_done:
		_fwd = dir
		_init_done = true
	_fwd = _fwd.slerp(dir, 1.0 - exp(-dt * (30.0 if m.dist < 0 or back else 6.0))).normalized()
	var up := Vector3.UP
	var desired: Vector3
	if m.dist < 0.0:
		desired = target.global_transform * Vector3(0, m.height, target.hood_z)
		_pos = desired
	else:
		desired = target.global_position - _fwd * m.dist + up * m.height
		_pos = desired if _pos == Vector3.ZERO else _pos.lerp(desired, 1.0 - exp(-dt * 14.0))
	global_position = _pos
	var look_at_pt: Vector3 = target.global_position + _fwd * 6.0 * m.look + up * 0.8
	if m.dist < 0.0:
		look_at_pt = _pos + _fwd * 10.0
	if global_position.distance_to(look_at_pt) > 0.1:
		look_at(look_at_pt, target.global_basis.y if m.dist < 0.0 else up)
	# Speed makes the view a touch wider.
	fov = lerpf(fov, m.fov + clampf(target.kmh() / 25.0, 0.0, 10.0), 1.0 - exp(-dt * 3.0))


func mode_name() -> String:
	return MODES[mode].name

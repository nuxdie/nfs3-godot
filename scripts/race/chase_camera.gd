class_name ChaseCamera
extends Camera3D
## Follows a car. Modes cycle with the "camera" action: near chase, far chase,
## bumper. Hold "look_back" to look behind. The mouse orbits the chase views and turns the head
## in the bumper view; the view drifts back behind the car once the mouse is left alone.

const MODES := [
	{"name": "Chase", "dist": 6.2, "height": 1.9, "look": 1.0, "fov": 68.0},
	{"name": "Far", "dist": 10.5, "height": 3.2, "look": 1.2, "fov": 64.0},
	{"name": "Bumper", "dist": -0.4, "height": 0.75, "look": 0.7, "fov": 75.0},
]
const MOUSE_SENS := 0.004     # radians per pixel
const RECENTER_DELAY := 1.2   # seconds without mouse movement before the view swings back

var target: Car
var mode := 0
var _pos := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _init_done := false

var mouse_look := true: set = set_mouse_look
var _yaw := 0.0
var _pitch := 0.0             # positive looks up
var _idle := RECENTER_DELAY


func _ready() -> void:
	mode = Game.camera_mode
	set_mouse_look(true)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Captures the mouse for looking around; off while menus are up so they can be clicked.
func set_mouse_look(on: bool) -> void:
	mouse_look = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("camera"):
		mode = (mode + 1) % MODES.size()
		_init_done = false
		Game.camera_mode = mode
		Game.save_settings()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw = wrapf(_yaw - e.relative.x * MOUSE_SENS, -PI, PI)
		_pitch = clampf(_pitch - e.relative.y * MOUSE_SENS, -1.2, 0.35)
		_idle = 0.0
	elif e is InputEventMouseButton and e.pressed and mouse_look \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the window after alt-tabbing out.
		set_mouse_look(true)


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
	_idle += dt
	if _idle > RECENTER_DELAY or back:
		var k := 1.0 - exp(-dt * (20.0 if back else 3.0))
		_yaw = lerpf(_yaw, 0.0, k)
		_pitch = lerpf(_pitch, 0.0, k)
	var view := _fwd.rotated(up, _yaw)
	var mouse_active := _idle < RECENTER_DELAY
	var desired: Vector3
	if m.dist < 0.0:
		# Looking back from the bumper view: sit on the rear bumper, not inside the car.
		desired = target.global_transform * Vector3(0, m.height, -target.hood_z if back else target.hood_z)
		_pos = desired
	else:
		# Orbit: looking down raises the camera over the car, looking up lowers it.
		var elev := clampf(-_pitch, -0.3, 1.2)
		# The car's camera arm [56] sets how far back the chase views sit.
		var arm: float = m.dist * target.camera_arm
		desired = target.global_position + (-view * cos(elev) + up * sin(elev)) * arm + up * m.height
		# Stay inside the track's walls and out of buildings: swinging wide on a hairpin or with
		# the car against a wall otherwise puts the camera inside the scenery.
		var from := target.global_position + up * 1.2
		var hit := get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, desired, 1 | Nfs3TrackBuilder.CAMERA_LAYER))
		var blocked := not hit.is_empty()
		if blocked:
			desired = hit.position + (from - desired).normalized() * 0.4
		_pos = desired if _pos == Vector3.ZERO else _pos.lerp(desired, 1.0 - exp(-dt * (40.0 if blocked or mouse_active else 14.0)))
	global_position = _pos
	var look_at_pt: Vector3 = target.global_position + view * 6.0 * m.look + up * 0.8
	if m.dist < 0.0:
		var head := view.rotated(view.cross(up).normalized(), _pitch) if absf(view.y) < 0.99 else view
		look_at_pt = _pos + head * 10.0
	if global_position.distance_to(look_at_pt) > 0.1:
		look_at(look_at_pt, target.global_basis.y if m.dist < 0.0 else up)
	# Speed makes the view a touch wider.
	fov = lerpf(fov, m.fov + clampf(target.kmh() / 25.0, 0.0, 10.0), 1.0 - exp(-dt * 3.0))


func mode_name() -> String:
	return MODES[mode].name

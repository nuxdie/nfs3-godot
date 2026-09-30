class_name ChaseCamera
extends Camera3D
## Follows a car. Modes cycle with the "camera" action: near chase, far chase,
## bumper, and in-car where the car has a dashboard (High Stakes cars). Hold "look_back" to
## look behind. The mouse orbits the chase views and turns the head
## in the bumper view; the view drifts back behind the car once the mouse is left alone.

const MODES := [
	{"name": "Chase", "dist": 6.2, "height": 1.9, "look": 1.0, "fov": 68.0},
	{"name": "Far", "dist": 10.5, "height": 3.2, "look": 1.2, "fov": 64.0},
	{"name": "Bumper", "dist": -0.4, "height": 0.75, "look": 0.7, "fov": 75.0},
	{"name": "In-car", "dist": -0.4, "height": 0.75, "look": 0.7, "fov": 72.0, "inside": true},
	{"name": "TV", "dist": 10.5, "height": 3.2, "look": 1.2, "fov": 64.0, "tv": true},
]
const TV_REACH := 160.0       # m: NFS3's cameras (no road stretch of their own) watch cars this near
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
var _inside_car: Car           # the car whose in-car view is showing
## Trackside TV cameras and the road they're placed along, set by the race (none: no TV view).
var tv: TvCameras
var tv_path: TrackPath
var _tv_cam := {}
var _tv_check := 0.0
var _tv_node := -1


func _ready() -> void:
	mode = Game.camera_mode
	set_mouse_look(true)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_inside(null)


## Captures the mouse for looking around; off while menus are up so they can be clicked.
func set_mouse_look(on: bool) -> void:
	mouse_look = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("camera"):
		mode = (mode + 1) % MODES.size()
		# The in-car view only where the car has a dashboard, the TV view where the track has cameras.
		for k in 2:
			if MODES[mode].get("inside", false) and target and not target.has_cockpit() \
					or MODES[mode].get("tv", false) and (tv == null or tv.cams.is_empty()):
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
	if m.get("tv", false) and _update_tv(dt):
		_show_inside(null)
		return
	var inside: bool = m.get("inside", false) and target.has_cockpit()
	_show_inside(target if inside else null)
	if m.get("inside", false) and not inside:
		m = MODES[2]   # a car without a dashboard: the bumper view
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
	if inside:
		desired = target.global_transform * target.cockpit_eye()
		_pos = desired
	elif m.dist < 0.0:
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


## The TV view: from the trackside camera covering the car, zoomed to keep it in frame.
## False when none does (the far chase view stands in).
func _update_tv(dt: float) -> bool:
	if tv == null or tv_path == null:
		return false
	_tv_node = tv_path.closest(target.global_position, _tv_node)
	_tv_check -= dt
	var look := target.global_position + Vector3.UP * 0.6
	if _tv_check <= 0.0 or _tv_cam.is_empty():
		_tv_check = 0.4
		var space := get_world_3d().direct_space_state
		var mask := 1 | Nfs3TrackBuilder.SCENERY_LAYER | Nfs3TrackBuilder.CAMERA_LAYER
		var picked := tv.pick(target.global_position, _tv_node, TV_REACH, func(at: Vector3) -> bool:
			return space.intersect_ray(PhysicsRayQueryParameters3D.create(at, look, mask)).is_empty())
		if picked != _tv_cam:
			_tv_cam = picked
			_init_done = false
	if _tv_cam.is_empty():
		return false
	global_position = _tv_cam.pos
	if global_position.distance_to(look) > 0.5:
		look_at(look, Vector3.UP)
	# The car about a sixth of the frame high, whatever the distance.
	var d := global_position.distance_to(look)
	fov = clampf(rad_to_deg(2.0 * atan(6.0 / maxf(d, 1.0))), 8.0, 70.0)
	_pos = global_position
	return true


func mode_name() -> String:
	return MODES[mode].name


## Puts `car` (or no car) in its in-car view, taking the last one out of it.
func _show_inside(car: Car) -> void:
	if car == _inside_car:
		return
	if is_instance_valid(_inside_car):
		_inside_car.set_cockpit(false)
	_inside_car = car
	if car:
		car.set_cockpit(true)

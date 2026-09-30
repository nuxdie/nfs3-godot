class_name Helicopter
extends Node3D
## High Stakes' police helicopter (hel.fce): joins a pursuit that's dragged on, flying ahead
## of the car it's after and off to one side (low enough to be seen from the car), rotors turning, lamps flashing and, by night,
## its searchlight on the car. Called off, it climbs away and goes.

const HEIGHT := 16.0        # m over the car
const LEAD := 1.2           # s of the car's travel it flies ahead by...
const MIN_AHEAD := 35.0     # ...but at least this far (m), so it hangs in view, not overhead
const OFFSET := 12.0        # m off to the side of the car's line
const MAX_SPEED := 85.0     # m/s
const ACCEL := 14.0         # m/s^2
const MAIN_RPM := 380.0
const TAIL_RPM := 1600.0
const CLEARANCE := 12.0     # m it keeps over whatever is under its rotor (ground, roofs, bridges)
const ROTOR_R := 7.0        # m, the footprint probed for that
const LOOKAHEAD := [0.0, 0.6, 1.3, 2.2]   # s along its flight where the ground is looked at
const PROBE_UP := 250.0     # m above it a probe starts, down through all of it
const PROBE_MASK := 1 | Nfs3TrackBuilder.SCENERY_LAYER | Nfs3TrackBuilder.CAMERA_LAYER

var target: Car
var _vel := Vector3.ZERO
var _main: Node3D
var _tail: Node3D
var _flashers: Array[Node3D] = []
var _flash_t := 0.0
var _search: SpotLight3D
var _leaving := false
var _leave_t := 0.0
var _probe: PhysicsShapeQueryParameters3D


## Builds it from Fce4.load_helicopter()'s data, at `at` (world), after `car`.
func setup(data: Dictionary, car: Car, at: Vector3, night: bool) -> void:
	target = car
	var mat := ShaderMaterial.new()
	mat.shader = Game.shader("res://shaders/car.gdshader")
	mat.set_shader_parameter("albedo_tex", data.texture)
	mat.set_shader_parameter("paint", Color(1, 1, 1))
	var body := _part(data.body, mat)
	add_child(body)
	if data.has("main"):
		_main = _part(data.main, mat)
		add_child(_main)
	if data.has("tail"):
		_tail = _part(data.tail, mat)
		add_child(_tail)
	for l: Dictionary in data.lights:
		var n: String = l.name
		if n.begins_with("S"):
			# Siren lamps, in their dummy's colour (see Nfs3Car.decode_light()), flashing in turn.
			var o := OmniLight3D.new()
			o.light_color = Car.LAMP_COLOURS[Nfs3Car.decode_light(n).colour]
			o.omni_range = 6.0
			o.light_energy = 3.0
			o.position = l.pos
			add_child(o)
			_flashers.append(o)
	if night:
		_search = SpotLight3D.new()
		_search.spot_range = 90.0   # it hangs ~40 m off, ahead and to the side
		_search.spot_angle = 9.0
		_search.light_energy = 16.0
		_search.light_color = Color(1.0, 0.97, 0.9)
		_search.shadow_enabled = false
		add_child(_search)
		for l: Dictionary in data.lights:
			if (l.name as String).begins_with("H"):
				_search.position = l.pos
	var sphere := SphereShape3D.new()
	sphere.radius = ROTOR_R
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = sphere
	_probe.collision_mask = PROBE_MASK
	_probe.motion = Vector3.DOWN * PROBE_UP * 2.0
	global_position = at


## The top of what's under a rotor's footprint at `at` (x, z): terrain, a roof, a bridge.
## -INF over nothing.
func _floor_at(at: Vector3) -> float:
	var top := at.y + PROBE_UP
	_probe.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, top, at.z))
	var r := get_world_3d().direct_space_state.cast_motion(_probe)
	if r[0] >= 1.0:
		return -INF
	return top + _probe.motion.y * r[0] - ROTOR_R


static func _part(p: Dictionary, mat: Material) -> Node3D:
	var holder := Node3D.new()
	holder.position = p.center
	var mi := MeshInstance3D.new()
	mi.mesh = p.mesh
	mi.material_override = mat
	holder.add_child(mi)
	return holder


## Called off the chase: climb away and go.
func leave() -> void:
	_leaving = true


func _physics_process(dt: float) -> void:
	var want: Vector3
	if _leaving or not is_instance_valid(target):
		_leave_t += dt
		want = global_position + (_vel.normalized() if _vel.length() > 1.0 else -global_basis.z) * 60.0 + Vector3.UP * 25.0
		if _leave_t > 10.0:
			queue_free()
			return
	else:
		var tv := Vector3(target.linear_velocity.x, 0, target.linear_velocity.z)
		var fwd := tv.normalized() if tv.length() > 3.0 else Vector3(target.global_basis.z.x, 0, target.global_basis.z.z).normalized()
		var right := fwd.cross(Vector3.UP)
		# A slow sweep so it isn't a fixed stare.
		var sway := Vector3(sin(Time.get_ticks_msec() * 0.00035), 0, cos(Time.get_ticks_msec() * 0.00029)) * 6.0
		want = target.global_position + fwd * maxf(tv.length() * LEAD, MIN_AHEAD) + right * OFFSET + Vector3.UP * HEIGHT + sway
	# Never down into the scenery: over the highest thing under the point it's making for
	# and under where it's heading, so it climbs over a hill or a block before it gets there.
	var ground := _floor_at(want)
	var flat_v := Vector3(_vel.x, 0, _vel.z)
	for t: float in LOOKAHEAD:
		ground = maxf(ground, _floor_at(global_position + flat_v * t))
	want.y = maxf(want.y, ground + CLEARANCE)
	# Arrive: speed toward the point falls off near it.
	var to := want - global_position
	var desired := to.normalized() * minf(MAX_SPEED, to.length() * 1.2)
	var dv := (desired - _vel).limit_length(ACCEL * dt)
	_vel += dv
	global_position += _vel * dt
	# Came in too fast to climb clear in time (or was called in inside a hill): lift it out.
	var under := _floor_at(global_position) + CLEARANCE * 0.5
	if global_position.y < under:
		global_position.y = under
		_vel.y = maxf(_vel.y, 0.0)
	# Nose into the flight (or along the car when hanging over it), banked into the turn.
	var flat := Vector3(_vel.x, 0, _vel.z)
	var fwd := flat.normalized() if flat.length() > 4.0 else (target.global_basis.z if is_instance_valid(target) else global_basis.z)
	fwd.y = 0
	if fwd.length() > 0.01:
		var yaw_b := Basis.looking_at(-fwd.normalized(), Vector3.UP)
		var side := dv.dot(yaw_b.x) / maxf(dt, 1e-4)
		var pitch := clampf(dv.dot(fwd.normalized()) / maxf(dt, 1e-4) * 0.02, -0.25, 0.25)
		var target_b := yaw_b * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, clampf(-side * 0.02, -0.35, 0.35))
		basis = basis.slerp(target_b.orthonormalized(), 1.0 - exp(-dt * 3.0)).orthonormalized()
	if _search and is_instance_valid(target):
		_search.look_at(target.global_position, Vector3.UP)


func _process(dt: float) -> void:
	if _main:
		_main.rotate_object_local(Vector3.UP, MAIN_RPM / 60.0 * TAU * dt)
	if _tail:
		_tail.rotate_object_local(Vector3.RIGHT, TAIL_RPM / 60.0 * TAU * dt)
	_flash_t += dt
	var phase := fmod(_flash_t * 2.5, 1.0)
	for i in _flashers.size():
		_flashers[i].visible = (phase < 0.5) == (i % 2 == 0)

class_name Helicopter
extends Node3D
## High Stakes' police helicopter (hel.fce): joins a pursuit that's dragged on, flying over
## and a little ahead of the car it's after, rotors turning, lamps flashing and, by night,
## its searchlight on the car. Called off, it climbs away and goes.

const HEIGHT := 26.0        # m over the car
const LEAD := 1.2           # s of the car's travel it flies ahead by
const MAX_SPEED := 85.0     # m/s
const ACCEL := 14.0         # m/s^2
const MAIN_RPM := 380.0
const TAIL_RPM := 1600.0

var target: Car
var _vel := Vector3.ZERO
var _main: Node3D
var _tail: Node3D
var _flashers: Array[Node3D] = []
var _flash_t := 0.0
var _search: SpotLight3D
var _leaving := false
var _leave_t := 0.0


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
		_search.spot_range = HEIGHT * 2.5
		_search.spot_angle = 9.0
		_search.light_energy = 16.0
		_search.light_color = Color(1.0, 0.97, 0.9)
		_search.shadow_enabled = false
		add_child(_search)
		for l: Dictionary in data.lights:
			if (l.name as String).begins_with("H"):
				_search.position = l.pos
	global_position = at


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
		var tv := target.linear_velocity
		# A slow sweep round over the car so it isn't a fixed stare.
		var sway := Vector3(sin(Time.get_ticks_msec() * 0.00035), 0, cos(Time.get_ticks_msec() * 0.00029)) * 8.0
		want = target.global_position + Vector3(tv.x, 0, tv.z) * LEAD + Vector3.UP * HEIGHT + sway
	# Arrive: speed toward the point falls off near it.
	var to := want - global_position
	var desired := to.normalized() * minf(MAX_SPEED, to.length() * 1.2)
	var dv := (desired - _vel).limit_length(ACCEL * dt)
	_vel += dv
	global_position += _vel * dt
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

class_name Officer
extends Node3D
## High Stakes' officer (its police cars' cop.fce): gets out of the cruiser that made a
## bust, walks up to the busted car's driver window, writes the ticket and walks back,
## then goes. The cruiser waits for him (see Race._send_officer).

signal done

const WALK_SPEED := 1.6     # m/s
const STAND_TIME := 2.5     # s at the window
const MAX_WALK := 9.0       # m: from further off he starts nearer the car
const STEP := 0.7          # m a step
const FOOT_APART := 0.12   # m from his middle to each foot as he walks
const KNEE_BEND := 0.6     # rad, the swinging leg's knee at most
const SHADER := preload("res://shaders/officer.gdshader")

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _phase := 0             # 0 walking up, 1 at the window, 2 walking back
var _t := 0.0
var _walked := 0.0
var _stride := 0.0          # 0 standing .. 1 walking, eased
var _mats: Array[ShaderMaterial] = []


## Off `cop`'s driver door to `busted`'s driver window.
func setup(mesh: Mesh, cop: Car, busted: Car) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	_rig(mi)
	# The driver sits on the car's left (+X).
	_from = cop.global_transform * Vector3(cop._half_size.x + 0.5, 0, 0.3)
	_to = busted.global_transform * Vector3(busted._half_size.x + 0.7, 0, 0.2)
	if _from.distance_to(_to) > MAX_WALK:
		_from = _to + (_from - _to).normalized() * MAX_WALK
	global_position = _ground(_from)


## His legs, found in the mesh (it has no parts for them): the officer shader on every
## surface, pivoting at hip and knee height, split where the lower legs are furthest apart,
## how far his feet are planted apart beyond a walker's, and how bent his knees already are.
func _rig(mi: MeshInstance3D) -> void:
	var faces := mi.mesh.get_faces()
	var h := 0.0
	for v in faces:
		h = maxf(h, v.y)
	var xs: Array[float] = []
	var z := 0.0
	var nz := 0
	for v in faces:
		if v.y > 0.02 * h and v.y < 0.3 * h:
			xs.append(v.x)
		if v.y > 0.3 * h and v.y < 0.5 * h:
			z += v.z
			nz += 1
	xs.sort()
	var split := 0.0
	var gap := -1.0
	for i in xs.size() - 1:
		if xs[i + 1] - xs[i] > gap:
			gap = xs[i + 1] - xs[i]
			split = (xs[i] + xs[i + 1]) * 0.5
	# Each foot's middle, from the soles.
	var feet := PackedFloat32Array([0.0, 0.0])
	var nf := PackedInt32Array([0, 0])
	for v in faces:
		if v.y < 0.08 * h:
			var k := 1 if v.x > split else 0
			feet[k] += v.x
			nf[k] += 1
	var apart := (feet[1] / maxi(nf[1], 1) - feet[0] / maxi(nf[0], 1)) * 0.5
	var splay := atan(maxf(apart - FOOT_APART, 0.0) / (0.48 * h))
	# Knees modelled bent (the knee ahead of the hip and ankle) bend that much less walking.
	var hip := _mean_z(faces, 0.42 * h, 0.52 * h)
	var knee := _mean_z(faces, 0.2 * h, 0.32 * h)
	var ankle := _mean_z(faces, 0.03 * h, 0.12 * h)
	var bent := atan((knee - hip) / (0.22 * h)) + atan((knee - ankle) / (0.19 * h))
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo_tex", src.albedo_texture if src else null)
		m.set_shader_parameter("hip_y", 0.48 * h)
		m.set_shader_parameter("knee_y", 0.26 * h)
		m.set_shader_parameter("leg_split", split)
		m.set_shader_parameter("pivot_z", z / nz if nz > 0 else 0.0)
		m.set_shader_parameter("splay", splay)
		m.set_shader_parameter("knee_bend", clampf(KNEE_BEND - bent, 0.0, KNEE_BEND))
		mi.set_surface_override_material(s, m)
		_mats.append(m)


## The mean Z of `faces`' vertices between heights `lo` and `hi`.
static func _mean_z(faces: PackedVector3Array, lo: float, hi: float) -> float:
	var z := 0.0
	var n := 0
	for v in faces:
		if v.y > lo and v.y < hi:
			z += v.z
			n += 1
	return z / n if n > 0 else 0.0


func _physics_process(dt: float) -> void:
	_t += dt
	var walking := _phase != 1
	match _phase:
		0:
			if _walk(_to, dt):
				_phase = 1
				_t = 0.0
		1:
			if _t > STAND_TIME:
				_phase = 2
		2:
			if _walk(_from, dt):
				done.emit()
				queue_free()
	_stride = move_toward(_stride, 1.0 if walking else 0.0, dt * 3.0)
	for m in _mats:
		m.set_shader_parameter("phase", _walked / STEP * PI)
		m.set_shader_parameter("stride", _stride)


## A step toward `goal`; true once there.
func _walk(goal: Vector3, dt: float) -> bool:
	var flat := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	if flat.length() < 0.15:
		return true
	var step := flat.normalized() * minf(WALK_SPEED * dt, flat.length())
	_walked += step.length()
	global_position = _ground(global_position + step)
	# Facing where he's going (the model faces +Z like the cars).
	basis = Basis.looking_at(-flat.normalized(), Vector3.UP)
	return false


## `p` put down on the road or ground below (or above) it.
func _ground(p: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 4.0, 1))
	return hit.position if not hit.is_empty() else p

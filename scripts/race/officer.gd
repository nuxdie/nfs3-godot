class_name Officer
extends Node3D
## High Stakes' officer (its police cars' cop.fce): gets out of the cruiser that made a
## bust, walks up to the busted car's driver window, writes the ticket and walks back,
## then goes. The cruiser waits for him (see Race._send_officer).

signal done

const WALK_SPEED := 1.6     # m/s
const STAND_TIME := 2.5     # s at the window
const MAX_WALK := 9.0       # m: from further off he starts nearer the car
const STEP_HZ := 1.8        # steps a second, for the bob

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _phase := 0             # 0 walking up, 1 at the window, 2 walking back
var _t := 0.0
var _walked := 0.0


## Off `cop`'s driver door to `busted`'s driver window.
func setup(mesh: Mesh, cop: Car, busted: Car) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	# The driver sits on the car's left (+X).
	_from = cop.global_transform * Vector3(cop._half_size.x + 0.5, 0, 0.3)
	_to = busted.global_transform * Vector3(busted._half_size.x + 0.7, 0, 0.2)
	if _from.distance_to(_to) > MAX_WALK:
		_from = _to + (_from - _to).normalized() * MAX_WALK
	global_position = _ground(_from)


func _physics_process(dt: float) -> void:
	_t += dt
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


## A step toward `goal`; true once there.
func _walk(goal: Vector3, dt: float) -> bool:
	var flat := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	if flat.length() < 0.15:
		return true
	var step := flat.normalized() * minf(WALK_SPEED * dt, flat.length())
	_walked += step.length()
	var p := _ground(global_position + step)
	# A little bob in his stride.
	p.y += absf(sin(_walked / WALK_SPEED * STEP_HZ * PI)) * 0.04
	global_position = p
	# Facing where he's going (the model faces +Z like the cars).
	basis = Basis.looking_at(-flat.normalized(), Vector3.UP)
	return false


## `p` put down on the road or ground below (or above) it.
func _ground(p: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 4.0, 1))
	return hit.position if not hit.is_empty() else p

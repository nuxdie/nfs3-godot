extends Node3D
## Loops a node through NFS3 animated-object keyframes (position and rotation): a plain
## node, or an AnimatableBody3D for a solid object.
## The last key is where the loop ends, not a step back to the first: it jumps from there
## to the first key. Spinning things end a symmetry turn on (a water wheel a spoke
## round, a two-sided sign half a turn), paths often far from where they began.

var keys: Array = []
var delay := 1
var _t := 0.0


func _ready() -> void:
	# A solid one (an AnimatableBody3D) moves with the physics, so it pushes cars smoothly.
	var body := is_class("PhysicsBody3D")
	set_process(not body)
	set_physics_process(body)


func _physics_process(dt: float) -> void:
	_process(dt)


func _process(dt: float) -> void:
	if keys.size() < 2:
		return
	var per_key := maxf(delay, 1) / 60.0
	_t = fmod(_t + dt / per_key, keys.size() - 1)
	var i := int(_t)
	var a: Vector3 = keys[i].pos
	var b: Vector3 = keys[i + 1].pos
	position = a.lerp(b, _t - i)
	var qa: Quaternion = keys[i].rot
	var qb: Quaternion = keys[i + 1].rot
	quaternion = qa.slerp(qb, _t - i)

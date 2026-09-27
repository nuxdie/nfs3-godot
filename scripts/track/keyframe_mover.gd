extends Node3D
## Loops a node through NFS3 animated-object keyframes (position and rotation).

var keys: Array = []
var delay := 1
var _t := 0.0


func _process(dt: float) -> void:
	if keys.size() < 2:
		return
	var per_key := maxf(delay, 1) / 60.0
	_t = fmod(_t + dt / per_key, keys.size())
	var i := int(_t)
	var a: Vector3 = keys[i].pos
	var b: Vector3 = keys[(i + 1) % keys.size()].pos
	position = a.lerp(b, _t - i)
	var qa: Quaternion = keys[i].rot
	var qb: Quaternion = keys[(i + 1) % keys.size()].rot
	quaternion = qa.slerp(qb, _t - i)

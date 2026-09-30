extends Node3D
## Loops a node through NFS3 animated-object keyframes (position and rotation).
## The last key is where the loop ends, not a step back to the first: it jumps from there
## to the first key. Spinning things end a symmetry turn on (a water wheel a spoke
## round, a two-sided sign half a turn), paths often far from where they began.

var keys: Array = []
var delay := 1                  # game ticks per key; the game takes 6 outside 1-400
var tick_rate := 60.0           # the game's ticks per second (High Stakes: 64)
var _t := 0.0


func _process(dt: float) -> void:
	if keys.size() < 2:
		return
	var per_key := (delay if delay >= 1 and delay <= 400 else 6) / tick_rate
	_t = fmod(_t + dt / per_key, keys.size() - 1)
	var i := int(_t)
	var a: Vector3 = keys[i].pos
	var b: Vector3 = keys[i + 1].pos
	position = a.lerp(b, _t - i)
	var qa: Quaternion = keys[i].rot
	var qb: Quaternion = keys[i + 1].rot
	quaternion = qa.slerp(qb, _t - i)

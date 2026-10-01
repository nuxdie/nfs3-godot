extends Node
## Loops MeshInstance3D siblings' meshes through frames (a Porsche Unleashed person's motion,
## Nfs5Track.props' frames): frames[f][k] is target k's mesh in frame f.

var targets: Array[MeshInstance3D] = []
var frames: Array = []
var fps := 15.0
var _t := 0.0
var _shown := -1


func _process(dt: float) -> void:
	if frames.size() < 2:
		return
	_t = fmod(_t + dt * fps, frames.size())
	var f := int(_t)
	if f == _shown:
		return
	_shown = f
	for k in targets.size():
		targets[k].mesh = frames[f][k]

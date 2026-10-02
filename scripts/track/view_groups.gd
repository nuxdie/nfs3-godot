class_name ViewGroups
extends Node
## Gran Turismo 2's placed objects come in lists, each drawn only from the stretches of the
## course that see it (a chunk's mask): the tree-covered hills of the infield aren't drawn
## from the road that runs under their edge, as they'd hang over it. Shows its parent's
## meshes of each group (meta "view_group") as the mask of the place nearest the camera has.

## [position, mask] per place (Nfs5Track.view_masks).
var masks: Array = []
var _meshes: Array[Array] = []   # [group, MeshInstance3D]
var _shown := -1


func _ready() -> void:
	for n in get_parent().get_children():
		if n is GeometryInstance3D and n.has_meta("view_group"):
			_meshes.append([int(n.get_meta("view_group")), n])
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or masks.is_empty():
		return
	var at := cam.global_position
	var mask := 0
	var best := INF
	for m: Array in masks:
		var d: float = at.distance_squared_to(m[0])
		if d < best:
			best = d
			mask = m[1]
	if mask == _shown:
		return
	_shown = mask
	for g: Array in _meshes:
		g[1].visible = (mask >> g[0]) & 1 == 1

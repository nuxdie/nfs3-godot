extends SceneTree
## `godot --headless --path . -s tools/_tmp/hp2_sounds_check.gd -- <out dir>` (hp2_sounds_check_node).
var started := false


func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/hp2_sounds_check_node.gd").new())
	return false

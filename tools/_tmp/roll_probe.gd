extends SceneTree
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/roll_probe_node.gd").new())
	return false

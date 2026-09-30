extends SceneTree
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/puqa_here_node.gd").new())
	return false

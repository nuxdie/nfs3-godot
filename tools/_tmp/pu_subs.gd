extends SceneTree
## Loader for pu_subs_node.gd (see there).
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/pu_subs_node.gd").new())
	return false

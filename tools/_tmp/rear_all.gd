extends SceneTree
## Loader for rear_all_node.gd: ./godot --headless --path . -s tools/_tmp/rear_all.gd -- [id prefixes]
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/rear_all_node.gd").new())
	return false

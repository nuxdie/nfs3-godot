extends SceneTree
## Colliders (all layers) near a point: -s tools/_tmp/gt2_probe_at.gd -- <track> x y z [r]
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/gt2_probe_node.gd").new())
	return false

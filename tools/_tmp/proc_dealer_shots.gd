extends SceneTree
## tools/offscreen.sh -s tools/_tmp/proc_dealer_shots.gd: the generated cars in the dealership.
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		change_scene_to_file("res://scenes/main_menu.tscn")
		root.add_child(load("res://tools/_tmp/proc_dealer_shots_node.gd").new())
	return false

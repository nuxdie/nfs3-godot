extends SceneTree
## Loader for showroom_shots_node.gd (see there).
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		change_scene_to_file("res://scenes/main_menu.tscn")
		root.add_child(load("res://tools/_tmp/showroom_shots_node.gd").new())
	return false

extends SceneTree
## Loader for garage_shots_node.gd: godot --path . -s tools/_tmp/garage_shots.gd -- <series>
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		change_scene_to_file("res://scenes/main_menu.tscn")
		root.add_child(load("res://tools/_tmp/garage_shots_node.gd").new())
	return false

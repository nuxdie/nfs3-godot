extends SceneTree
## godot --path . -s tools/_tmp/trackui_shots.gd -- <name> [keys...]: the menu's track screen, shots/tu_<name>_*.png.
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		change_scene_to_file("res://scenes/main_menu.tscn")
		root.add_child(load("res://tools/_tmp/trackui_shots_node.gd").new())
	return false

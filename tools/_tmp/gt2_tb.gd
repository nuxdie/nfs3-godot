extends SceneTree
## Loader for gt2_tb_node.gd: tools/offscreen.sh -s tools/_tmp/dealer_shots.gd -- [series]
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		change_scene_to_file("res://scenes/main_menu.tscn")
		root.add_child(load("res://tools/_tmp/gt2_tb_node.gd").new())
	return false

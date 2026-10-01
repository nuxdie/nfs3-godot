extends SceneTree
## godot --headless --fixed-fps 60 -s tools/_tmp/puqa_drive.gd -- pu_<track> <layout> [--only=lap|side|N]
## Starts a time trial on the track (no rivals, no traffic) and drives it: puqa_drive_node.gd.
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load("res://tools/_tmp/puqa_drive_node.gd").new())
		change_scene_to_file.call_deferred("res://scenes/race.tscn")
	return false

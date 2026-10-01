extends SceneTree
## `godot --headless --path . -s tools/_tmp/hp2_run.gd -- <node script> [args]`: adds the node
## once the autoloads are up (scripts that use Game can't compile in a SceneTree script).
var started := false


func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load(OS.get_cmdline_user_args()[0]).new())
	return false

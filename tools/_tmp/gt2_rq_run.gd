extends SceneTree
## -s tools/_tmp/gt2_rq_run.gd -- <node script> args...: adds that node under the root.
var started := false
func _process(_d: float) -> bool:
	if not started:
		started = true
		root.add_child(load(OS.get_cmdline_user_args()[0]).new())
	return false

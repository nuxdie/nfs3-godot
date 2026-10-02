extends SceneTree
func _process(_d):
	var g = root.get_node("Game")
	var v = g._gt2_vol
	for f in v.list("crsobj"):
		var b = v.read("crsobj/" + f)
		var fa = FileAccess.open("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/1764b256-78e0-40a2-9f6a-b94ad362fa42/scratchpad/crs/" + f.trim_suffix(".gz"), FileAccess.WRITE)
		fa.store_buffer(b)
	for f in v.list("bgsobj"):
		var b = v.read("bgsobj/" + f)
		var fa = FileAccess.open("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/1764b256-78e0-40a2-9f6a-b94ad362fa42/scratchpad/crs/bgs_" + f.trim_suffix(".gz"), FileAccess.WRITE)
		fa.store_buffer(b)
	print(v.list(""))
	quit()
	return true

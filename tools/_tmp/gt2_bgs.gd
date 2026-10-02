extends SceneTree
func _process(_d):
	var v: Gt2Vol = root.get_node("Game")._gt2_vol
	var i := 0
	for f in v.list("bgsobj"):
		if f.ends_with(".bso.gz") or f.ends_with(".bso"):
			print(i, " ", f)
			i += 1
	quit()
	return true

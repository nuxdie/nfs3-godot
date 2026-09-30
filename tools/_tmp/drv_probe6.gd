extends SceneTree
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var seen := {}
	for c in g.cars:
		if g.is_pu_path(c.path):
			var m: String = g._pu_cars[c.path].model.to_lower()
			if not seen.has(m):
				seen[m] = true
				print("CAR ", m, " ", c.id)
	quit()
	return true

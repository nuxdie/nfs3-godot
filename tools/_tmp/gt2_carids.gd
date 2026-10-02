extends SceneTree
func _process(_d):
	var g = root.get_node("Game")
	for c in g.cars:
		if c.id.begins_with("gt2_") and ("Skyline" in c.name or "NSX" in c.name or "Supra" in c.name):
			print(c.id, " ", c.name)
	quit()
	return true

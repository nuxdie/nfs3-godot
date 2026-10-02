extends SceneTree
func _init():
	pass
func _process(_d):
	var g = root.get_node("Game")
	for id in g._gt2_tracks:
		var c = g._gt2_tracks[id]
		print(id, " | ", c.name, " | night=", c.night, " dirt=", c.dirt, " sprint=", c.sprint, " rev=", c.reverse)
	quit()
	return true

extends Node
## Loads the first NFS3 and High Stakes tracks and the procedural one, and Normandie: path
## size, walls, and (Normandie) road width against wall width at a few nodes.
func _ready() -> void:
	var ids := ["procedural"]
	for id: String in Game.tracks:
		if not id.begins_with("pu_") and ids.size() < 3 and id != "procedural":
			ids.append(id)
	ids.append("pu_farmland")
	for id in ids:
		var w := TrackWorld.load_track(id)
		var walls := w.root.get_node_or_null("Walls")
		var faces := 0
		if walls:
			for c in walls.get_children():
				faces += c.shape.get_faces().size() / 3
		var s := "%s: %d nodes, %d wall faces" % [id, w.path.size(), faces]
		if id == "pu_farmland":
			for i in [62, 150, 233, 900]:
				s += "  n%d road %.0f/%.0f walls %.0f/%.0f" % [i, w.path.left_width[i], w.path.right_width[i], w.path.wall_width(i, -1.0), w.path.wall_width(i, 1.0)]
		print(s)
	get_tree().quit()

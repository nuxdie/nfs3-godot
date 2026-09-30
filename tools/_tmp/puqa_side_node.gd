extends Node
## `-- <track>`: the side roads kept: slices, where their ends meet the lap (node, m), and
## the lap's wall gaps.
func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var w := TrackWorld.load_track(id)
	var t: Nfs5Track = w.track
	var p := w.path
	for r in t.side_roads.size():
		var road: Array = t.side_roads[r]
		var s := []
		for vr: Nfs3Track.VRoad in [road[0], road[-1]]:
			var n := p.closest(vr.pos)
			s.append("node %d (%.0f m)" % [n, p.points[n].distance_to(vr.pos)])
		print("side road %d: %d slices, ends at %s, walls %.1f/%.1f" % [r, road.size(), " / ".join(s), road[road.size() / 2].left_wall, road[road.size() / 2].right_wall])
	var walls := w.root.get_node("Walls")
	for c in walls.get_children():
		print("  wall shape %s: %d faces" % [c.name, c.shape.get_faces().size() / 3])
	get_tree().quit()

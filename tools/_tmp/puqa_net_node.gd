extends Node
## `-- pu_<track>...`: the side roads' ends: how far from the lap and from each other's ends.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var t := Nfs5Track.load_file(Game.track_dir(id))
		var lap: Array[Vector3] = []
		for vr in t.vroad:
			lap.append(vr.pos)
		print("== %s: lap %d slices closed=%s sprint=%s, %d side roads" % [id, lap.size(), t.closed, t.sprint, t.side_roads.size()])
		for i in t.side_roads.size():
			var road: Array = t.side_roads[i]
			var s := "  %d: %d slices" % [i, road.size()]
			for e in [0, road.size() - 1]:
				var p: Vector3 = road[e].pos
				var bd := INF
				var bk := -1
				for k in lap.size():
					var d := lap[k].distance_to(p)
					if d < bd:
						bd = d
						bk = k
				var others := []
				for j in t.side_roads.size():
					if j == i:
						continue
					for f in [0, t.side_roads[j].size() - 1]:
						var d: float = t.side_roads[j][f].pos.distance_to(p)
						if d < 40.0:
							others.append("%d%s %.0fm" % [j, "a" if f == 0 else "b", d])
				s += " | %s end: lap slice %d at %.0f m, others [%s]" % ["a" if e == 0 else "b", bk, bd, ", ".join(others)]
			print(s)
	get_tree().quit()

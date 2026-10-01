extends SceneTree

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	Gt2Track.vol = Gt2Vol.open(img)
	var t := Gt2Track.load_dir("gt2:laguna")
	for n in [0, 20, 40, 60, 100, 200, 400, 600, 800]:
		var p: Vector3 = t.vroad[n].pos
		var q := Vector2(p.x, p.z)
		var best := INF
		for i in t._line.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, t._line[i], t._line[i + 1]).distance_to(q))
		print(n, " ", q, " nearest line ", snappedf(best, 0.1))
	quit()

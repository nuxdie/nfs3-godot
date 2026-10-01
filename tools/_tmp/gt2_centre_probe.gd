extends SceneTree
## ./godot --headless --path . -s tools/_tmp/gt2_centre_probe.gd -- course from to

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	Gt2Track.vol = Gt2Vol.open(img)
	var t := Gt2Track.load_dir("gt2:" + args[0])
	var grid := t._tri_grid()
	print("tarmac images ", t._tarmac.keys(), " line pts ", t._line.size())
	for i in range(int(args[1]), int(args[2]), 3):
		var vr: Nfs3Track.VRoad = t.vroad[i]
		var runs := []
		var x := -40.0
		var on_start := INF
		while x <= 40.5:
			var tt := t._tri_at(grid, vr.pos + vr.right * x)
			var on := tt >= 0 and t._tarmac.has(t._road_tris[tt][3])
			if on and on_start == INF:
				on_start = x
			elif not on and on_start != INF:
				runs.append("%.1f..%.1f" % [on_start, x - 0.5])
				on_start = INF
			x += 0.5
		print(i, " line at ", snappedf(t._line_offset(vr.pos, vr.right), 0.1), " walls ", snappedf(vr.left_wall, 0.1), "/", snappedf(vr.right_wall, 0.1), " runs ", runs)
	quit()

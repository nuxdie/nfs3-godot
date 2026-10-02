extends SceneTree
func _process(_d):
	var g = root.get_node("Game")
	var a := OS.get_cmdline_user_args()
	var t: Gt2Track = Gt2Track.load_dir("gt2:" + (g._gt2_tracks[a[0]].course as String))
	for i in range(int(a[1]), int(a[2])):
		var v = t.vroad[i]
		print("%d pos %s L %.1f R %.1f wallL %.1f wallR %.1f fwd %s" % [i, v.pos.snapped(Vector3.ONE * 0.1), v.left_wall, v.right_wall, t.fences[0][i], t.fences[1][i], v.forward.snapped(Vector3.ONE * 0.01)])
	quit()
	return true

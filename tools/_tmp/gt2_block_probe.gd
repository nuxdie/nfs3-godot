extends SceneTree
## Solid faces on the centre line: ./godot --headless --path . -s tools/_tmp/gt2_block_probe.gd -- course n

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	Gt2Track.vol = Gt2Vol.open(img)
	var t := Gt2Track.load_dir("gt2:" + args[0])
	var walls := []
	for ch in t.chunks:
		var p: Nfs5Track.Piece = ch.pieces[Nfs5Track.Kind.SCENERY]
		for i in range(0, p.pos.size(), 3):
			walls.append([p.pos[i], p.pos[i + 1], p.pos[i + 2]])
	for n in range(0, int(args[1]), 3):
		var vr: Nfs3Track.VRoad = t.vroad[n]
		var hit := 0
		for w in walls:
			var c: Vector3 = (w[0] + w[1] + w[2]) / 3.0
			if Vector2(c.x - vr.pos.x, c.z - vr.pos.z).length() < 2.0 and c.y > vr.pos.y - 0.5 and c.y < vr.pos.y + 4.0:
				hit += 1
		print(n, " ", vr.pos.snapped(Vector3.ONE * 0.1), " walls ", snappedf(vr.left_wall, 0.1), "/", snappedf(vr.right_wall, 0.1), " fence ", snappedf(t.fences[0][n], 0.1), "/", snappedf(t.fences[1][n], 0.1), " solid near ", hit)
	quit()

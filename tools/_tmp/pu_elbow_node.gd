extends Node
## How far each forearm's elbow end (rearmost quarter of its vertices) is from the body's
## nearest vertex, for body lean frame b and arm frame a.
func _ready() -> void:
	Game.scan_data()
	var args := OS.get_cmdline_user_args()
	var dir := DataPath.find_ci(Game.pu_root, "Carmodel")
	var crp := Crp.load_file(DataPath.find_ci(dir, args[0] + ".crp"))
	var arts := {}
	for art in crp.articles: arts[art.name] = art
	var body = arts[args[1]]
	for pair in [[0, 0], [0, 9], [4, 0], [4, 9], [2, 4], [2, 5]]:
		var bv := crp.vec3s(crp.sub(body, "vt", 1 | pair[0] << 4))
		var tot := 0.0
		var s := ""
		for side in [args[2], args[3]]:
			var av := crp.vec3s(crp.sub(arts[side], "vt", 1 | pair[1] << 4))
			var zs := []
			for v in av: zs.append(v.z)
			zs.sort()
			var cut: float = zs[int(zs.size() * 0.75)]
			var c := Vector3.ZERO; var n := 0
			for v in av:
				if v.z >= cut: c += v; n += 1
			c /= n
			var best := INF
			for v in bv: best = minf(best, v.distance_to(c))
			tot += best
			s += " %s %.3f" % [side, best]
		print("body %d arms %d:%s  sum %.3f" % [pair[0], pair[1], s, tot])
	get_tree().quit()

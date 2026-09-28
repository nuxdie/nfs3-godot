extends SceneTree
func _init() -> void:
	var lay := ProceduralTrack.make_layout(ProceduralTrack.SEED)
	var out := ""
	for i in range(140, 240, 3):
		var g := (lay.pts[i + 1].y - lay.pts[i - 1].y) / 12.0
		out += "%d:%.1f(%+.0f%%)%s " % [i, lay.pts[i].y, g * 100.0, "B" if lay.kind[i] == 2 else ""]
	print(out)
	quit()

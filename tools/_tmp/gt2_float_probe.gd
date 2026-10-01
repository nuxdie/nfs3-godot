extends SceneTree
## Finds faces far above the road near them: ./godot --headless --path . -s tools/_tmp/gt2_float_probe.gd -- course

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	Gt2Track.vol = Gt2Vol.open(img)
	var t := Gt2Track.load_dir("gt2:" + OS.get_cmdline_user_args()[0])
	var nodes := PackedVector3Array()
	for vr in t.vroad:
		nodes.append(vr.pos)
	var found := {}
	for ci in t.chunks.size():
		for kind in 3:
			var p: Nfs5Track.Piece = t.chunks[ci].pieces[kind]
			for i in range(0, p.pos.size(), 3):
				var c := (p.pos[i] + p.pos[i + 1] + p.pos[i + 2]) / 3.0
				var best := INF
				var bh := 0.0
				for n in nodes:
					var dd := Vector2(n.x - c.x, n.z - c.z).length()
					if dd < best:
						best = dd
						bh = n.y
				if best < 40.0 and c.y - bh > 25.0:
					var key := "%d/%d" % [ci, kind]
					found[key] = found.get(key, 0) + 1
	print("chunks ", t.chunks.size(), " floating (chunk/kind: faces) ", found)
	quit()

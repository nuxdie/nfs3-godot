extends SceneTree
## ./godot --headless --path . -s tools/_tmp/gt2_track_probe.gd -- course...

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	Gt2Track.vol = Gt2Vol.open(img)
	for c in OS.get_cmdline_user_args():
		var t0 := Time.get_ticks_msec()
		var t := Gt2Track.load_dir("gt2:" + c)
		var tris := [0, 0, 0]
		for ch in t.chunks:
			for k in 3:
				tris[k] += ch.pieces[k].tex.size()
		print(c, " err='", t.error, "' ms ", Time.get_ticks_msec() - t0, " images ", t.images.size(), " chunks ", t.chunks.size(),
			" tris road/ground/scenery ", tris, " texture misses ", t.misses, " vroad ", t.vroad.size(), " closed ", t.closed)
	quit()

extends Node
## Per track: ground-kind triangles textured like the road (a texture the ROAD articles use),
## by article name family, and how much of the ground that is.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var t := Nfs5Track.load_file(Game.track_dir(id))
		var fsh_names := Fsh.load_file(Game.track_dir(id).get_basename() + ".fsh").names
		var road_tex := {}
		var ground := 0
		var roadlike := {}
		for c in t.chunks:
			for x in c.pieces[Nfs5Track.Kind.ROAD].tex:
				road_tex[x] = true
		for c in t.chunks + [{"pieces": t.backdrop}]:
			var g: Nfs5Track.Piece = c.pieces[Nfs5Track.Kind.GROUND]
			ground += g.tex.size()
			for x in g.tex:
				if road_tex.has(x):
					roadlike[fsh_names[x]] = roadlike.get(fsh_names[x], 0) + 1
		var n := 0
		for k in roadlike:
			n += roadlike[k]
		var top := roadlike.keys()
		top.sort_custom(func(a, b): return roadlike[a] > roadlike[b])
		print("%s: ground tris %d, road-textured %d (%.1f%%): %s" % [id, ground, n, 100.0 * n / maxi(ground, 1),
			", ".join(top.slice(0, 8).map(func(k): return "%s×%d" % [k, roadlike[k]]))])
		print("   road textures: %s" % ", ".join(road_tex.keys().map(func(x): return fsh_names[x])))
	get_tree().quit()

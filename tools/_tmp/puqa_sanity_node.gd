extends Node
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var t := Nfs5Track.load_file(Game.track_dir(id))
		var see := Nfs5TrackBuilder._see_through(t)
		var hist := [0, 0, 0]
		for s in see:
			hist[s] += 1
		var tri := [0, 0, 0]
		var scen_by_see := [0, 0, 0]
		for c in t.chunks:
			for k in 3:
				var pc: Nfs5Track.Piece = c.pieces[k]
				tri[k] += pc.tex.size()
				if k == Nfs5Track.Kind.SCENERY:
					for x in pc.tex:
						scen_by_see[see[x]] += 1
		var bd := [0, 0, 0]
		for k in 3:
			bd[k] = t.backdrop[k].tex.size()
		print("%s images opaque/cutout/glass %s  tris road/ground/scenery %s  backdrop %s  scenery tris by see-through %s" % [id, hist, tri, bd, scen_by_see])
	get_tree().quit()

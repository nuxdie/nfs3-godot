extends Node
## Per track: materials whose texture isn't in the .fsh, and the triangles (by kind) that
## the loader drops for it.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var path := Game.track_dir(id)
		var crp := Crp.load_file(path)
		var fsh := Fsh.load_file(path.get_basename() + ".fsh")
		var names := {}
		for n in fsh.names:
			names[n] = true
		var tex_of := {}
		for e in crp.misc_of("mt"):
			tex_of[e.index] = crp.data.slice(e.offset + 40, e.offset + 44).get_string_from_ascii() if e.length >= 44 else ""
		var dropped := {}   # "kind tex" -> tris
		var total := [0, 0, 0]
		for art in crp.articles:
			var base := crp.sub(art, "Base")
			if base == null or crp.sub(art, "vt") == null:
				continue
			var flags := crp.data.decode_u32(base.offset)
			if flags & Nfs5Track.BASE_SMACKABLE:
				continue
			var kind := "scenery"
			if flags & Nfs5Track.BASE_GROUND:
				kind = "ROAD" if flags & Nfs5Track.BASE_ROAD else "ground"
			for k in 256:
				var pe := crp.sub(art, "pr", k)
				if pe == null:
					break
				var p := crp.part(pe)
				var n: int = p.vertex.size() / 3
				var tn: String = tex_of.get(p.material, "<no mt %d>" % p.material)
				if not names.has(tn):
					var key := "%s %s" % [kind, tn]
					dropped[key] = dropped.get(key, 0) + n
		print("%s: %d fsh images; dropped tris: %s" % [id, fsh.names.size(), dropped])
	get_tree().quit()

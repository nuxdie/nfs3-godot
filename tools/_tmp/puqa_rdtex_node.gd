extends Node
## Per track: "rd…" textures used on ground-kind triangles but on no ROAD article, with
## the article families (name up to the digits/paren) they're in.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var path := Game.track_dir(id)
		var crp := Crp.load_file(path)
		var tex_of := {}
		for e in crp.misc_of("mt"):
			tex_of[e.index] = crp.data.slice(e.offset + 40, e.offset + 44).get_string_from_ascii() if e.length >= 44 else ""
		var road := {}
		var ground := {}   # tex -> {family: tris}
		for art in crp.articles:
			var base := crp.sub(art, "Base")
			if base == null or crp.sub(art, "vt") == null:
				continue
			var flags := crp.data.decode_u32(base.offset)
			if flags & Nfs5Track.BASE_SMACKABLE or not flags & Nfs5Track.BASE_GROUND:
				continue
			for k in 256:
				var pe := crp.sub(art, "pr", k)
				if pe == null:
					break
				var p := crp.part(pe)
				var tn: String = tex_of.get(p.material, "")
				if flags & Nfs5Track.BASE_ROAD:
					road[tn] = true
				elif tn.begins_with("rd"):
					var fam: String = art.name.get_slice("(", 1).get_slice(")", 0).strip_edges() if "(" in art.name else art.name
					fam = fam.get_slice(" ", 1) if " " in fam else fam
					var d: Dictionary = ground.get_or_add(tn, {})
					d[fam] = d.get(fam, 0) + p.vertex.size() / 3
		var out := []
		for tn in ground:
			if not road.has(tn):
				out.append("%s %s" % [tn, ground[tn]])
		print("%s: %s" % [id, "; ".join(out)])
	get_tree().quit()

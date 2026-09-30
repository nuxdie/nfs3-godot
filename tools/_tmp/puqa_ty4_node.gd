extends Node
## `-- <track> <type> [n]`: the first n parts of that primitive type: article, texture,
## corner count, and the first corners' positions.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var crp := Crp.load_file(Game.track_dir(a[0]))
	var shown := 0
	for art in crp.articles:
		var vt := crp.sub(art, "vt")
		if vt == null:
			continue
		var verts := crp.vec3s(vt)
		for k in 256:
			var pe := crp.sub(art, "pr", k)
			if pe == null:
				break
			if crp.data.decode_u16(pe.offset) != int(a[1]):
				continue
			var p := crp.part(pe)
			var base := crp.sub(art, "Base")
			print("%s pr%x flags %08x tex %s count %d" % [art.name.left(40), k, crp.data.decode_u32(base.offset) if base else 0,
				crp.material_texture(p.material), pe.count])
			var s := []
			for c in mini(9, p.vertex.size()):
				s.append(str(verts[p.vertex[c]].snappedf(0.1)))
			print("    ", " ".join(s))
			shown += 1
			if shown >= (int(a[2]) if a.size() > 2 else 4):
				get_tree().quit()
				return
	get_tree().quit()

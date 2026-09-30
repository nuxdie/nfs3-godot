extends Node
## `-- <track> <article substring> [max parts]`: level-0 parts' header words, corner
## count, material texture, and how many consecutive triangles share an edge as a strip would.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var crp := Crp.load_file(Game.track_dir(a[0]))
	var shown := 0
	for art in crp.articles:
		if not a[1] in art.name:
			continue
		for k in 256:
			var pe := crp.sub(art, "pr", k)
			if pe == null:
				break
			var p := crp.part(pe)
			var h := []
			for w in 10:
				h.append("%08x" % crp.data.decode_u32(pe.offset + w * 4))
			var vi: PackedInt32Array = p.vertex
			var stripish := 0
			for t in range(3, vi.size() - 2, 3):
				var prev := [vi[t - 3], vi[t - 2], vi[t - 1]]
				var shared := 0
				for c in 3:
					if vi[t + c] in prev:
						shared += 1
				if shared >= 2:
					stripish += 1
			print("%s pr%x count %d (%%3=%d) tex %s  hdr %s  sharing-2 %d/%d  idx %s" % [art.name.left(28), k, pe.count, pe.count % 3,
				crp.material_texture(p.material), " ".join(h), stripish, vi.size() / 3 - 1, vi.slice(0, 12)])
			shown += 1
			if shown >= int(a[2]) if a.size() > 2 else 40:
				get_tree().quit()
				return
	get_tree().quit()

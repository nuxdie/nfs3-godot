extends Node
## `-- <track> [track...]`: parts by primitive word (u16 at +0): count and corners; for
## type-1 parts, triangle edge lengths and facing read as a list and as a strip.
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var crp := Crp.load_file(Game.track_dir(id))
		var types := {}
		var stats := {"list": [0.0, 0, 0], "strip": [0.0, 0, 0]}   # summed longest edge, up, count
		for art in crp.articles:
			var vt := crp.sub(art, "vt")
			if vt == null:
				continue
			var verts := crp.vec3s(vt)
			for k in 256:
				var pe := crp.sub(art, "pr", k)
				if pe == null:
					break
				var ty := crp.data.decode_u16(pe.offset)
				types[ty] = types.get(ty, [0, 0])
				types[ty][0] += 1
				types[ty][1] += pe.count
				if ty != 1:
					continue
				var vi: PackedInt32Array = crp.part(pe).vertex
				for mode in ["list", "strip"]:
					var tris := []
					if mode == "list":
						for t in range(0, vi.size() - 2, 3):
							tris.append([vi[t], vi[t + 1], vi[t + 2]])
					else:
						for t in vi.size() - 2:
							tris.append([vi[t], vi[t + 1], vi[t + 2]] if t % 2 == 0 else [vi[t + 1], vi[t], vi[t + 2]])
					for tr in tris:
						if tr[0] >= verts.size() or tr[1] >= verts.size() or tr[2] >= verts.size() or tr[0] == tr[1] or tr[1] == tr[2] or tr[0] == tr[2]:
							continue
						var a := verts[tr[0]]; var b := verts[tr[1]]; var c := verts[tr[2]]
						stats[mode][0] += maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
						var n := (b - a).cross(c - a).normalized()
						if n.y > 0.5:
							stats[mode][1] += 1
						stats[mode][2] += 1
		print("%s: parts by type {type: [parts, corners]} %s" % [id, types])
		for mode in stats:
			var s: Array = stats[mode]
			if s[2] > 0:
				print("   type 1 as %s: %d tris, mean longest edge %.1f m, facing up (as stored) %d%%" % [mode, s[2], s[0] / s[2], 100 * s[1] / s[2]])
	get_tree().quit()

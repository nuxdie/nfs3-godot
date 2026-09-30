extends Node
## `-- <track> node[:lat],...`: every article (level 0) with triangles over those points,
## how the loader classified it, and the heights of its triangles there.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var w := TrackWorld.load_track(id)
	var crp := Crp.load_file(Game.track_dir(id))
	var pts := []
	for s in args[1].split(","):
		var n := int(s.get_slice(":", 0))
		var lat := float(s.get_slice(":", 1)) if ":" in s else 0.0
		pts.append([s, w.path.points[n] + w.path.rights[n] * lat, w.path.ups[n]])
	var tex_of := {}
	for e in crp.misc_of("mt"):
		tex_of[e.index] = crp.data.slice(e.offset + 40, e.offset + 44).get_string_from_ascii() if e.length >= 44 else "?"
	for pt in pts:
		print("== %s at %s" % [pt[0], pt[1]])
		var p: Vector3 = pt[1]
		for art in crp.articles:
			var base := crp.sub(art, "Base")
			var vt := crp.sub(art, "vt")
			if base == null or vt == null:
				continue
			var flags := crp.data.decode_u32(base.offset)
			var verts := crp.vec3s(vt)
			var ys := []
			var mats := {}
			for k in 256:
				var pe := crp.sub(art, "pr", k)
				if pe == null:
					break
				var part := crp.part(pe)
				var vi: PackedInt32Array = part.vertex
				for t3 in range(0, vi.size() - 2, 3):
					if vi[t3] >= verts.size() or vi[t3+1] >= verts.size() or vi[t3+2] >= verts.size():
						continue
					var a := verts[vi[t3]]; var b := verts[vi[t3+1]]; var c := verts[vi[t3+2]]
					if Geometry2D.point_is_inside_triangle(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
						var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 1e4, p.z), Vector3.DOWN, a, b, c)
						if hit == null:
							hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, -1e4, p.z), Vector3.UP, a, b, c)
						if hit != null:
							var nn := (b - a).cross(c - a).normalized()
							ys.append("%.2f%s%s" % [hit.y - p.y, "^" if nn.y < 0 else "v", tex_of.get(part.material, "-")])
							mats["%d:%s" % [part.material, tex_of.get(part.material, "-")]] = true
			if ys.is_empty():
				continue
			ys.sort()
			var box := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(v)
			print("  %-10s flags %08x  dy %s\n      mats %s  box %s" % [art.name, flags, ys, mats.keys(), box.size.round()])
	get_tree().quit()

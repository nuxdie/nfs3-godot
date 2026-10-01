extends Node
## `-- pu_<track> x,y,z [x,y,z...]`: rays along the lap at car height through each point
## (several lateral offsets), what they hit and which track triangles (image, kind) that is.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0])
	add_child(w.root)
	for k in 3:
		await get_tree().physics_frame
	var t: Nfs5Track = w.track
	var space := get_viewport().world_3d.direct_space_state
	for s in a.slice(1):
		var f := s.split_floats(",")
		var p := Vector3(f[0], f[1], f[2])
		var n := w.path.closest(p)
		var fw := w.path.forward(n)
		var rt := w.path.rights[n]
		print("== %s: node %d lateral %.1f (road -%.1f/+%.1f), node y %.1f" % [p, n, w.path.lateral(p, n), w.path.left_width[n], w.path.right_width[n], w.path.points[n].y])
		for lat in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
			for dir in [1.0, -1.0]:
				var o: Vector3 = w.path.points[n] + rt * lat + Vector3.UP * 0.7 - fw * dir * 25.0
				var q := PhysicsRayQueryParameters3D.create(o, o + fw * dir * 50.0, 0xFFFF & ~Nfs3TrackBuilder.AI_WALL_LAYER)
				var h := space.intersect_ray(q)
				if h.is_empty():
					print("  lat %+.0f dir %+.0f: clear" % [lat, dir])
					continue
				var hp: Vector3 = h.position
				var what := []
				for c in t.chunks:
					for pc: Nfs5Track.Piece in c.pieces:
						for i in range(0, pc.pos.size(), 3):
							var A := pc.pos[i]; var B := pc.pos[i + 1]; var C := pc.pos[i + 2]
							var nn := (B - A).cross(C - A)
							if nn.length() < 1e-6: continue
							nn = nn.normalized()
							if absf((hp - A).dot(nn)) > 0.05: continue
							var bc := Geometry3D.get_closest_point_to_segment(hp, A, B)
							var cp := hp - nn * (hp - A).dot(nn)
							# inside test via barycentric
							var v0 := B - A; var v1 := C - A; var v2 := cp - A
							var d00 := v0.dot(v0); var d01 := v0.dot(v1); var d11 := v1.dot(v1); var d20 := v2.dot(v0); var d21 := v2.dot(v1)
							var den := d00 * d11 - d01 * d01
							if absf(den) < 1e-9: continue
							var vv := (d11 * d20 - d01 * d21) / den
							var ww := (d00 * d21 - d01 * d20) / den
							if vv < -0.01 or ww < -0.01 or vv + ww > 1.01: continue
							var tex: int = pc.tex[i / 3]
							what.append("%s kind%d n%.2f size %.1f" % [t.image_names[tex] if tex < t.image_names.size() else "?", pc.kind, nn.y, maxf(maxf(A.distance_to(B), B.distance_to(C)), C.distance_to(A))])
				print("  lat %+.0f dir %+.0f: hit %s at %.1f m (%s) %s" % [lat, dir, h.collider.name, o.distance_to(hp), hp, what])
	get_tree().quit()

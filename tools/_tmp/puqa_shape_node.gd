extends Node
## `-- pu_<track> body shape x,y,z r`: the triangles of that collision shape within r m of the point,
## with the track triangles (image, kind) they came from.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0])
	var t: Nfs5Track = w.track
	var body: CollisionObject3D = w.root.get_node(a[1])
	var f := a[3].split_floats(",")
	var p := Vector3(f[0], f[1], f[2])
	var r := float(a[4])
	var owners := body.get_shape_owners()
	var si := int(a[2])
	var count := 0
	for o in owners:
		for k in body.shape_owner_get_shape_count(o):
			if count == si:
				var sh := body.shape_owner_get_shape(o, k)
				var xf := body.shape_owner_get_transform(o)
				print("shape %d: %s" % [si, sh])
				if sh is ConcavePolygonShape3D:
					var fc: PackedVector3Array = sh.get_faces()
					for i in range(0, fc.size(), 3):
						var A := xf * fc[i]; var B := xf * fc[i + 1]; var C := xf * fc[i + 2]
						var c := (A + B + C) / 3.0
						if Geometry3D.get_closest_point_to_segment(p, A, B).distance_to(p) > r and c.distance_to(p) > r:
							continue
						var tag := "?"
						for ch in t.chunks:
							for pc: Nfs5Track.Piece in ch.pieces:
								for j in range(0, pc.pos.size(), 3):
									if pc.pos[j].is_equal_approx(A) or pc.pos[j].is_equal_approx(B) or pc.pos[j].is_equal_approx(C):
										if (pc.pos[j] + pc.pos[j + 1] + pc.pos[j + 2]).distance_to(A + B + C) < 0.03:
											tag = "%s kind%d" % [t.image_names[pc.tex[j / 3]], pc.kind]
						print("  tri %s %s %s  n%s  %s" % [A.snapped(Vector3.ONE * 0.1), B.snapped(Vector3.ONE * 0.1), C.snapped(Vector3.ONE * 0.1), (B - A).cross(C - A).normalized().snapped(Vector3.ONE * 0.01), tag])
				elif sh is ConvexPolygonShape3D or sh is BoxShape3D:
					print("  xf %s" % xf)
			count += 1
	get_tree().quit()

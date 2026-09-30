extends Node
## `-- <track> node side(+1/-1)`: the wall walk step by step: every level surface under
## each metre out (relative to the slice's plane there) and every steep one near it.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Nfs5Track.load_file(Game.track_dir(a[0]))
	var w := TrackWorld.load_track(a[0])
	var i := int(a[1])
	var sg := float(a[2])
	var p := w.path
	var g := t._level_grid()
	var all := {}
	for c in t.chunks:
		for pc: Nfs5Track.Piece in [c.pieces[0], c.pieces[1], c.pieces[2]]:
			for k in range(0, pc.pos.size(), 3):
				var cell := Vector2i(floori(pc.pos[k].x / 4.0), floori(pc.pos[k].z / 4.0))
				all.get_or_add(cell, []).append([pc, k])
	for d in range(0, 18):
		var at: Vector3 = p.points[i] + p.rights[i] * d * sg
		var hs := []
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for e: Array in all.get(Vector2i(floori(at.x / 4.0) + dx, floori(at.z / 4.0) + dz), []):
					var pc: Nfs5Track.Piece = e[0]
					var k: int = e[1]
					var hit = Geometry3D.ray_intersects_triangle(Vector3(at.x, at.y + 30, at.z), Vector3.DOWN, pc.pos[k], pc.pos[k + 1], pc.pos[k + 2])
					if hit != null and absf(hit.y - at.y) < 8:
						var n := (pc.pos[k + 2] - pc.pos[k]).cross(pc.pos[k + 1] - pc.pos[k]).normalized()
						hs.append("%+.1f %s n%.2f" % [hit.y - at.y, ["R", "G", "S"][pc.kind], n.y])
		print("%2d m: %s" % [d, ", ".join(hs)])
	get_tree().quit()

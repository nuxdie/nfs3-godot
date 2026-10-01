extends Node
## `-- pu_<track> x,y,z ...`: per point, the side road slices near it (horizontal distance,
## height, lateral against its walls) and on_side_road's verdict.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Nfs5Track.load_file(Game.track_dir(a[0]))
	var path := TrackPath.new()
	for road: Array in t.side_roads:
		for vr: Nfs3Track.VRoad in road:
			path.add_side_slice(vr.pos, vr.right.normalized(), vr.left_wall, vr.right_wall)
	for s in a.slice(1):
		var f := s.split_floats(",")
		var p := Vector3(f[0], f[1], f[2])
		print("== %s on_side_road=%s" % [p, path.on_side_road(p)])
		for si in t.side_roads.size():
			var road: Array = t.side_roads[si]
			for k in road.size():
				var vr: Nfs3Track.VRoad = road[k]
				var d := p - vr.pos
				if Vector2(d.x, d.z).length() < 30.0:
					var r := vr.right.normalized()
					print("  road %d slice %d/%d: dist %.1f dy %.1f lat %.1f walls -%.1f/+%.1f along %.1f" % [si, k, road.size(), d.length(), d.y, d.dot(r), vr.left_wall, vr.right_wall, (d - r * d.dot(r)).length()])
		var bd := INF
		for vr in t.vroad:
			bd = minf(bd, vr.pos.distance_to(p))
		print("  lap: nearest slice %.0f m" % bd)
	get_tree().quit()

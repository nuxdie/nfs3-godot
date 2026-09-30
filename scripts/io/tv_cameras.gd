class_name TvCameras
## Trackside "TV" cameras (Porsche Unleashed's too, see load_dir). High Stakes' Tracks/<name>/tr.cam: a count, then 68-byte records
## (a type, the position, an orientation matrix, a zoom, and the virtual road nodes it
## covers: first, middle, last). NFS3's trNN.ccm: a version and a count, then 28-byte records
## (16.16 fixed-point position, orientation quaternion, and two flags), with no road
## stretches: those are used when the car is near enough to be seen.

var cams: Array[Dictionary] = []   # {pos: Vector3, from: int, to: int} (from = -1: no stretch)


static func load_dir(dir: String, high_stakes: bool) -> TvCameras:
	var t := TvCameras.new()
	if Nfs5Track.is_track_file(dir):
		# Porsche Unleashed: Track/<name>_cameras.scn, text: each CAMERA_ELEMENT's next line is
		# its position (the trigger zones after it aren't used: as NFS3's, by distance).
		var f := DataPath.find_ci(dir.get_base_dir(), dir.get_file().get_basename() + "_cameras.scn")
		var lines := FileAccess.get_file_as_string(f).split("\n") if f != "" else PackedStringArray()
		for i in lines.size() - 1:
			if lines[i].begins_with("CAMERA_ELEMENT"):
				var v := lines[i + 1].split_floats(" ", false)
				if v.size() >= 3:
					t.cams.append({"pos": Vector3(-v[0], v[1], v[2]), "from": -1, "to": -1})
	elif high_stakes:
		var d := FileAccess.get_file_as_bytes(DataPath.find_ci(dir, "tr.cam"))
		if d.size() >= 4:
			for i in mini(d.decode_u32(0), (d.size() - 4) / 68):
				var p := 4 + i * 68
				var pos := Vector3(-d.decode_float(p + 4), d.decode_float(p + 8), d.decode_float(p + 12)) * Nfs4Track.SCALE
				var nodes := [d.decode_u32(p + 56), d.decode_u32(p + 60), d.decode_u32(p + 64)]
				t.cams.append({"pos": pos, "from": nodes.min(), "to": nodes.max()})
	else:
		var d := FileAccess.get_file_as_bytes(DataPath.find_ci(dir, dir.get_file().to_lower().replace("k0", "") + ".ccm"))
		if d.size() >= 8:
			for i in mini(d.decode_u32(4), (d.size() - 8) / 28):
				var p := 8 + i * 28
				var pos := Vector3(-d.decode_s32(p), d.decode_s32(p + 4), d.decode_s32(p + 8)) / 65536.0
				t.cams.append({"pos": pos, "from": -1, "to": -1})
	return t


## For the mirrored and reversed layouts (see TrackWorld.load_track): `n` road nodes.
func lay_out(mirrored: bool, reversed: bool, n: int) -> void:
	for c in cams:
		if mirrored:
			c.pos = Vector3(-c.pos.x, c.pos.y, c.pos.z)
		if reversed and c.from >= 0:
			var a: int = (n - c.to) % n
			var b: int = (n - c.from) % n
			c.from = mini(a, b)
			c.to = maxi(a, b)


## The camera to watch a car at `pos` (road node `node`) from: the one whose stretch holds
## the node, else the nearest within `reach` m that `can_see` it. {} for none.
func pick(pos: Vector3, node: int, reach: float, can_see: Callable) -> Dictionary:
	var best := {}
	var best_d := reach
	for c in cams:
		if c.from >= 0:
			if node >= c.from and node <= c.to and can_see.call(c.pos):
				return c
			continue
		var d: float = (c.pos as Vector3).distance_to(pos)
		if d < best_d and can_see.call(c.pos):
			best = c
			best_d = d
	return best

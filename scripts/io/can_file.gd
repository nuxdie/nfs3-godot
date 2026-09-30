class_name CanFile
## Camera animations (NFS3 trNN00.can, High Stakes trNN.can): keyframes relative to the
## player's car, e.g. the fly-by before the start (00 and 00a). Each key is a 16.16
## fixed-point position and a quaternion (int16s over 16384).

var keys: Array[Dictionary] = []   # {pos: Vector3 (car-local, ours), rot: Quaternion (as stored)}


## `scale`: High Stakes' tracks are drawn at 1/1.3 of ours (see Nfs4Track.SCALE).
static func load_file(path: String, scale := 1.0) -> CanFile:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 8:
		return null
	var n := d.decode_u16(4)
	if n < 2 or 8 + n * 20 > d.size():
		return null
	var c := CanFile.new()
	for i in n:
		var p := 8 + i * 20
		# Mirrored in X like the tracks (NFS's x runs the other way).
		var pos := Vector3(-d.decode_s32(p), d.decode_s32(p + 4), d.decode_s32(p + 8)) / 65536.0 * scale
		var q := Quaternion(d.decode_s16(p + 12), d.decode_s16(p + 14), d.decode_s16(p + 16), d.decode_s16(p + 18)) / 16384.0
		c.keys.append({"pos": pos, "rot": q})
	return c


## Position at `f` (0..1 along the animation), smoothed through the keys.
func position_at(f: float) -> Vector3:
	var x := clampf(f, 0.0, 1.0) * (keys.size() - 1)
	var i := mini(int(x), keys.size() - 2)
	var t := x - i
	var p0: Vector3 = keys[maxi(i - 1, 0)].pos
	var p1: Vector3 = keys[i].pos
	var p2: Vector3 = keys[i + 1].pos
	var p3: Vector3 = keys[mini(i + 2, keys.size() - 1)].pos
	return p1.cubic_interpolate(p2, p0, p3, t)


## The track's start fly-bys: NFS3's trNN00.can / trNN00a.can, High Stakes' tr00.can / tr00a.can.
static func intros(dir: String, high_stakes: bool) -> Array[CanFile]:
	var out: Array[CanFile] = []
	var stem := "tr00" if high_stakes else dir.get_file().to_lower().replace("k0", "") + "00"
	for suffix in ["", "a"]:
		var c := load_file(DataPath.find_ci(dir, stem + suffix + ".can"), Nfs4Track.SCALE if high_stakes else 1.0)
		if c:
			out.append(c)
	return out

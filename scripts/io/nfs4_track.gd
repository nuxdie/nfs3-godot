class_name Nfs4Track
## Parses a Need for Speed: High Stakes track folder (Data/Tracks/<Name>/tr.frd + tr0.qfs)
## into the same Nfs3Track data the NFS3 tracks give, so Nfs3TrackBuilder, the AI and the
## sky take either. High Stakes keeps the virtual road in the FRD (there's no .col), gives
## each poly its texture straight from the archive with rotate/flip bits in place of NFS3's
## texture table, and draws its tracks at 1/SCALE of NFS3's size: its versions of the NFS3
## tracks are the same shapes scaled down exactly 1.3 times.

## High Stakes units to NFS3's (which the cars and their handling are made for).
const SCALE := 1.3
const POLY_SIZE := 13
const VROAD_SIZE := 84
const BLOCK_HEADER_SIZE := 1512
const XOBJ_HEADER_SIZE := 52
const NODES_PER_BLOCK := 8
## Poly chunks per block: 0-3 lower detail levels (not drawn), 4 the road and terrain, 5 its
## fences and walls, 6 lane markings, 7-10 scenery on the block's vertices.
const ROAD_CHUNK := 4
const LANE_CHUNK := 6
const OBJECT_CHUNKS := [5, 7, 8, 9, 10]
## Poly flag bits: the texture turned 90 degrees, not flipped vertically, mirrored in X or Y.
const UV_ROTATE := 0x04
const UV_INVERT := 0x08
const UV_MIRROR_X := 0x10
const UV_MIRROR_Y := 0x20
const UV_BITS := UV_ROTATE | UV_INVERT | UV_MIRROR_X | UV_MIRROR_Y
## Texture word: the archive index in the low 11 bits; with this bit it's a lane marking and
## the index picks the lin<N> sprite of GameArt/sfx.fsh instead.
const LANE_TEXTURE := 0x800
## Surface values (Nfs3Track.drivable) given to road polys inside and outside the walls.
const SURFACE_ROAD := 1
const SURFACE_TERRAIN := 14
## ...and only when they face up (cosine to the road's normal) and lie within this height (m)
## of it: not the roof of a covered bridge or a tunnel's ceiling.
const MIN_FACING := 0.5
const ROAD_REACH := 3.0

var t: Nfs3Track
var _tex_of := {}   # Vector4i(archive index, uv flags, lane, frames) -> first Nfs3Track.textures index


## Whether `dir` is a High Stakes track folder.
static func is_track_dir(dir: String) -> bool:
	return dir != "" and DataPath.find_ci(dir, "tr.frd") != "" and DataPath.find_ci(dir, "tr.ini") != ""


static func load_dir(dir: String) -> Nfs3Track:
	var r := Nfs4Track.new()
	r.t = Nfs3Track.new()
	var t := r.t
	t.name = "hs_" + dir.get_file().to_lower()
	var frd_path := DataPath.find_ci(dir, "tr.frd")
	var frd := FileAccess.get_file_as_bytes(frd_path) if frd_path != "" else PackedByteArray()
	if frd.is_empty():
		t.error = "missing tr.frd"
		return t
	if not r._parse_frd(frd):
		return t
	var fsh := Fsh.load_file(DataPath.find_ci(dir, "tr0.qfs"))
	if fsh == null:
		t.error = "missing texture archive"
		return t
	# Texture ids count the archive's entries leaving out the "<mirrored>" copies of lettered
	# textures (signs), which only the mirrored tracks use. Glows, fire and light rays are
	# tagged "<additive>" (on one of Hometown's, "additive").
	var additive := PackedByteArray()
	for i in fsh.images.size():
		if fsh.tags[i] != "<mirrored>":
			t.images.append(fsh.images[i])
			additive.append(int("additive" in fsh.tags[i]))
	for ti in t.textures:
		if not ti.is_lane and ti.qfs_index < t.images.size():
			var img := t.images[ti.qfs_index]
			ti.width = img.get_width()
			ti.height = img.get_height()
			ti.cutout = img.detect_alpha() != Image.ALPHA_NONE
			ti.additive = additive[ti.qfs_index] != 0
	# Data/Tracks/<Name> -> Data/GameArt/sfx.fsh
	t._add_lane_images(Fsh.load_file(DataPath.find_ci(dir.get_base_dir().get_base_dir(), "gameart/sfx.fsh")))
	return t


## The virtual road's points (Godot space) without building anything, for the menu's map.
static func peek_outline(dir: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var path := DataPath.find_ci(dir, "tr.frd")
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null or f.get_length() < 36:
		return out
	f.seek(32)
	var n := f.get_32()
	if n < 16 or 36 + n * VROAD_SIZE > f.get_length():
		return out
	f.seek(36)
	var d := f.get_buffer(n * VROAD_SIZE)
	for i in range(0, n, NODES_PER_BLOCK):
		var q := i * VROAD_SIZE
		out.append(_point(d, q))
	return out


static func _point(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)) * SCALE


static func _dir(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))


func _short(d: PackedByteArray, p: int, n: int) -> bool:
	if p < 0 or n < 0 or p + n > d.size():
		t.error = "truncated or damaged FRD"
		return true
	return false


func _parse_frd(d: PackedByteArray) -> bool:
	if _short(d, 0, 36):
		return false
	var n_blocks := d.decode_u32(28) + 1
	var n_vroad := d.decode_u32(32)
	if n_blocks < 2 or n_blocks > 1000 or (n_vroad + NODES_PER_BLOCK - 1) / NODES_PER_BLOCK != n_blocks:
		t.error = "bad FRD block count"
		return false
	var p := 36
	if _short(d, p, n_vroad * VROAD_SIZE + n_blocks * BLOCK_HEADER_SIZE):
		return false
	for i in n_vroad:
		var vr := Nfs3Track.VRoad.new()
		vr.pos = _point(d, p)
		vr.normal = _dir(d, p + 12)
		vr.forward = _dir(d, p + 24)
		vr.right = _dir(d, p + 36)
		vr.left_wall = d.decode_float(p + 48) * SCALE
		vr.right_wall = d.decode_float(p + 52) * SCALE
		t.vroad.append(vr)
		p += VROAD_SIZE

	var headers := []
	for bi in n_blocks:
		var h := {
			"sz": [], "n_verts": d.decode_u32(p + 88), "nobj": [],
			"n_poly": d.decode_u32(p + 1412), "n_xref": d.decode_u32(p + 1448),
			"n_polyobj": d.decode_u32(p + 1456), "n_sound": d.decode_u32(p + 1464),
			"n_light": d.decode_u32(p + 1472),
		}
		for c in 11:
			h.sz.append(d.decode_u32(p + c * 4))
		for c in 4:
			h.nobj.append(d.decode_u32(p + 1380 + c * 8))
		var b := Nfs3Track.Block.new()
		b.center = _point(d, p + 120)
		b.n_hires_verts = d.decode_u32(p + 92)
		b.n_object_verts = d.decode_u32(p + 108)
		t.blocks.append(b)
		headers.append(h)
		p += BLOCK_HEADER_SIZE

	for bi in n_blocks:
		var h: Dictionary = headers[bi]
		var b := t.blocks[bi]
		var nv: int = h.n_verts
		if _short(d, p, nv * 16 + h.n_poly * 24 + h.n_xref * 20 + h.n_polyobj * 20 + h.n_sound * 16 + h.n_light * 16):
			return false
		b.verts = _scaled(Nfs3Track.read_vec3s(d, p, nv))
		p += nv * 12
		b.shading = Nfs3Track.read_shading(d, p, nv)
		p += nv * 4
		# Collision bounds with vroad normals per road stretch, object references and
		# sound sources: not needed here.
		p += h.n_poly * 24 + h.n_xref * 20 + h.n_polyobj * 20 + h.n_sound * 16
		for li in h.n_light:
			b.lights.append(Nfs3Track.fixed(d, p + li * 16) * SCALE)
		p += h.n_light * 16
		for c in 11:
			var n: int = h.sz[c]
			if _short(d, p, n * POLY_SIZE):
				return false
			if c == ROAD_CHUNK:
				b.road = _read_polys(d, p, n)
			elif c == LANE_CHUNK:
				b.lanes = _read_polys(d, p, n)
			elif c in OBJECT_CHUNKS:
				b.objects.append_array(_split_objects(_read_polys(d, p, n)))
			p += n * POLY_SIZE
		for c in 4:
			p = _read_xobjs(d, p, h.nobj[c], b)
			if p < 0:
				return false
	# Global objects: animated ones, then physics props (cones, barrels, hay bales).
	for g in 2:
		if _short(d, p, 4):
			return false
		p = _read_xobjs(d, p + 4, d.decode_u32(p), t.blocks[-1])
		if p < 0:
			return false
	_flag_road()
	return true


static func _scaled(v: PackedVector3Array) -> PackedVector3Array:
	for i in v.size():
		v[i] *= SCALE
	return v


## `n` extra objects at `p` (their headers, then each one's data) into `b.xobjs`; returns
## the offset after them, or -1 when the file ends first.
func _read_xobjs(d: PackedByteArray, p: int, n: int, b: Nfs3Track.Block) -> int:
	if _short(d, p, n * XOBJ_HEADER_SIZE):
		return -1
	var heads := []
	for i in n:
		var q := p + i * XOBJ_HEADER_SIZE
		heads.append([d.decode_u32(q), _point(d, q + 12), d.decode_u32(q + 32), d.decode_u32(q + 44)])
	p += n * XOBJ_HEADER_SIZE
	for hd in heads:
		var x := {"ref": hd[1], "unmirrored": true}
		match hd[0]:
			3:
				# Animated: 2 unknown bytes, type, id, key count, delay, keys as in NFS3.
				if _short(d, p, 8):
					return -1
				var n_keys := d.decode_u16(p + 4)
				x.anim_delay = d.decode_u16(p + 6)
				if _short(d, p + 8, n_keys * 20):
					return -1
				var keys := Nfs3Track.anim_keys(d, p + 8, n_keys)
				for k in keys:
					k.pos *= SCALE
				x.anim = keys
				x.ref = keys[0].pos if keys.size() > 0 else Vector3.ZERO
				p += 8 + n_keys * 20
			6:
				# Physics prop: position, mass, orientation, half extents; the header's
				# point is its position too.
				p += 72
		var nv: int = hd[2]
		var np: int = hd[3]
		if _short(d, p, nv * 16 + np * POLY_SIZE):
			return -1
		x.verts = _scaled(Nfs3Track.read_vec3s(d, p, nv))
		p += nv * 12
		x.shading = Nfs3Track.read_shading(d, p, nv)
		p += nv * 4
		x.polys = _read_polys(d, p, np)
		p += np * POLY_SIZE
		b.xobjs.append(x)
	return p


func _read_polys(d: PackedByteArray, p: int, n: int) -> Array:
	var out := []
	out.resize(n)
	for i in n:
		var q := p + i * POLY_SIZE
		var poly := Nfs3Track.Poly.new()
		# High Stakes winds its quads the other way round from NFS3: read them as 1, 0, 3, 2
		# (corner_uvs follows) so the builder's normals face the same way.
		poly.v = PackedInt32Array([d.decode_u16(q + 2), d.decode_u16(q), d.decode_u16(q + 6), d.decode_u16(q + 4)])
		var tw := d.decode_u16(q + 8)
		poly.flags = d.decode_u16(q + 10)
		# Animated texture: frame count in the low 3 bits, ticks per frame in the high 5; the
		# frames are the next entries of the archive.
		var anim := d[q + 12]
		if anim & 7 >= 2 and anim >> 3 > 0:
			poly.anim_frames = anim & 7
			poly.anim_period = anim >> 3
		poly.tex = _texture(tw & 0x7FF, poly.flags & UV_BITS, tw & LANE_TEXTURE != 0, poly.anim_frames)
		out[i] = poly
	return out


## The Nfs3Track.textures entry for an archive index drawn with these uv flags, made on
## first use. An animated texture gets one entry per frame, in a row, as the builder expects.
func _texture(index: int, uv_flags: int, lane: bool, frames: int) -> int:
	var key := Vector4i(index, uv_flags, int(lane), frames)
	if _tex_of.has(key):
		return _tex_of[key]
	var first := t.textures.size()
	var uv := corner_uvs(uv_flags)
	for f in maxi(frames, 1):
		var ti := Nfs3Track.TexInfo.new()
		ti.qfs_index = index + f
		ti.is_lane = lane
		ti.uv = uv
		t.textures.append(ti)
	_tex_of[key] = first
	return first


## Texture coordinates of a quad's four corners for its flags: a quarter turn (UV_ROTATE),
## a half turn (UV_INVERT), then mirrored across the turned texture. Worked out from the
## textures themselves (crops, hedges, guardrails and signs stood upright on every track):
## LibOpenNFS takes UV_INVERT for a vertical flip only and turns the other way, which hangs
## Hometown's roadside corn from its tops.
static func corner_uvs(flags: int) -> PackedVector2Array:
	var c := PackedVector2Array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
	for k in 4:
		var uv := c[k]
		if flags & UV_ROTATE:
			uv = Vector2(1.0 - uv.y, uv.x)
		if flags & UV_INVERT:
			uv = Vector2.ONE - uv
		if flags & UV_MIRROR_X:
			uv.x = 1.0 - uv.x
		if flags & UV_MIRROR_Y:
			uv.y = 1.0 - uv.y
		c[k] = uv
	return PackedVector2Array([c[1], c[0], c[3], c[2]])   # in the order _read_polys gives the corners


## A chunk's polys split into objects: the polys joined through shared corners.
static func _split_objects(polys: Array) -> Array:
	if polys.is_empty():
		return []
	var parent := {}
	var find := func(find: Callable, v: int) -> int:
		var r: int = parent.get(v, v)
		if r == v:
			return v
		r = find.call(find, r)
		parent[v] = r
		return r
	for poly: Nfs3Track.Poly in polys:
		var a: int = find.call(find, poly.v[0])
		for k in range(1, 4):
			var b: int = find.call(find, poly.v[k])
			if a != b:
				parent[b] = a
	var groups := {}
	for poly: Nfs3Track.Poly in polys:
		var root: int = find.call(find, poly.v[0])
		if not groups.has(root):
			groups[root] = []
		groups[root].append(poly)
	return groups.values()


## Marks each block's road polys drivable when they lie between the walls of the nearest
## virtual road node, facing up and near its surface (High Stakes has no surface flags for
## them): the rest is scenery terrain, which the invisible walls fence off.
func _flag_road() -> void:
	var n := t.vroad.size()
	for bi in t.blocks.size():
		var b := t.blocks[bi]
		b.road_flags.resize(b.road.size())
		for i in b.road.size():
			var p: Nfs3Track.Poly = b.road[i]
			if p.v[0] >= b.verts.size() or p.v[1] >= b.verts.size() or p.v[2] >= b.verts.size() or p.v[3] >= b.verts.size():
				b.road_flags[i] = SURFACE_TERRAIN
				continue
			var c := (b.verts[p.v[0]] + b.verts[p.v[1]] + b.verts[p.v[2]] + b.verts[p.v[3]]) * 0.25
			var best: Nfs3Track.VRoad = null
			var best_d := INF
			for k in range(bi * NODES_PER_BLOCK - NODES_PER_BLOCK, bi * NODES_PER_BLOCK + 2 * NODES_PER_BLOCK):
				var vr := t.vroad[posmod(k, n)]
				var dist := vr.pos.distance_squared_to(c)
				if dist < best_d:
					best_d = dist
					best = vr
			var up := best.normal.normalized()
			# Across the diagonals: a triangle stored as a quad repeats a corner.
			var facing := (b.verts[p.v[2]] - b.verts[p.v[0]]).cross(b.verts[p.v[1]] - b.verts[p.v[3]]).normalized().dot(up)
			var lat := (c - best.pos).dot(best.right.normalized())
			var rise := (c - best.pos).dot(up)
			var on_road := lat >= -best.left_wall and lat <= best.right_wall \
				and facing > MIN_FACING and rise > -ROAD_REACH and rise < ROAD_REACH
			b.road_flags[i] = SURFACE_ROAD if on_road else SURFACE_TERRAIN

class_name Nfs4Track
## Parses a Need for Speed: High Stakes track folder (Data/Tracks/<Name>/tr.frd + tr0.qfs)
## into the same Nfs3Track data the NFS3 tracks give, so Nfs3TrackBuilder, the AI and the
## sky take either. High Stakes keeps the virtual road in the FRD (there's no .col), gives
## each poly its texture straight from the archive with rotate/flip bits in place of NFS3's
## texture table, and draws its tracks at 1/SCALE of NFS3's size: its versions of the NFS3
## tracks are the same shapes scaled down exactly 1.3 times.

## High Stakes units to NFS3's (which the cars and their handling are made for).
const SCALE := 1.3
## The game's clock: animated objects, animated textures and blinking glows count its ticks.
const TICKS_PER_SECOND := 64.0
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
## The most nodes a wall may dip in by before the dip counts as real (see _fill_wall_dips).
const WALL_DIP_NODES := 3
## The most (m) a wall may step in per node across level ground (see _taper_wall_steps).
const WALL_TAPER := 2.0

var t: Nfs3Track
var _tex_of := {}   # Vector4i(archive index, uv flags, lane, frames) -> first Nfs3Track.textures index
var _ground := {}   # block index -> _ground_of's polys


static func has_night_version(dir: String) -> bool:
	return DataPath.find_ci(dir, "trn.frd") != ""


## Whether `dir` is a High Stakes track folder.
static func is_track_dir(dir: String) -> bool:
	return dir != "" and DataPath.find_ci(dir, "tr.frd") != "" and DataPath.find_ci(dir, "tr.ini") != ""


## With `night`, the track's night version where it has one (trn.frd: the same geometry
## with the street lamps and lit windows baked into its lighting; trn0.qfs: its textures
## with the windows lit, where they differ).
static func load_dir(dir: String, night := false) -> Nfs3Track:
	var r := Nfs4Track.new()
	r.t = Nfs3Track.new()
	var t := r.t
	t.name = "hs_" + dir.get_file().to_lower()
	t.ticks_per_second = TICKS_PER_SECOND
	t.vroad_walls = true
	t.soft_effects = true
	var frd_path := DataPath.find_ci(dir, "tr.frd")
	if night and has_night_version(dir):
		frd_path = DataPath.find_ci(dir, "trn.frd")
		t.night_version = true
	var frd := FileAccess.get_file_as_bytes(frd_path) if frd_path != "" else PackedByteArray()
	if frd.is_empty():
		t.error = "missing tr.frd"
		return t
	if not r._parse_frd(frd):
		return t
	var qfs := DataPath.find_ci(dir, "trn0.qfs") if t.night_version else ""
	var fsh := Fsh.load_file(qfs if qfs != "" else DataPath.find_ci(dir, "tr0.qfs"))
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
	var sfx := Fsh.load_file(DataPath.find_ci(dir.get_base_dir().get_base_dir(), "gameart/sfx.fsh"))
	t._add_lane_images(sfx)
	if sfx and sfx.by_name.has("glw0") and sfx.by_name.has("glw3"):
		t.glow_sprites = [sfx.by_name.glw0, sfx.by_name.glw3]
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
		# Traffic lanes (the PSX slice's avgPavedWidthLf/Rt and laneCount): widths in metres
		# as they are, not in the track's units (they fit the walls only that way).
		vr.lane_w_left = d.decode_float(p + 56)
		vr.lane_w_right = d.decode_float(p + 60)
		vr.lanes_left = clampi(d.decode_u32(p + 68), 0, 8)
		vr.lanes_right = clampi(d.decode_u32(p + 72), 0, 8)
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
		# Light sources: a point and a type whose low word picks the glow from the .ini's
		# [track glows] table (see TrackGlows); the game ignores the high word.
		for li in h.n_light:
			b.lights.append(Nfs3Track.fixed(d, p + li * 16) * SCALE)
			b.light_types.append(d.decode_u16(p + li * 16 + 12))
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
	_fill_wall_dips()
	_taper_wall_steps()
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
		# xtype: 2 billboard (see Nfs3TrackBuilder.BILLBOARD_XTYPE), 3 animated, 6 physics prop.
		var x := {"ref": hd[1], "unmirrored": true, "xtype": hd[0]}
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
				# point is its position too. The game knocks these about (benches, cones,
				# barrels, hay bales): Nfs3TrackBuilder._is_prop takes them whatever their size.
				x.physics = true
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


## Pushes back out a wall that dips in for a node or few (at most WALL_DIP_NODES) between
## wider ones, as far as the ground stays level with the road. The slices' wall distances are
## coarse (steps of ~5 m) and uneven: across a wide run-off such a dip is a wall in the middle
## of open grass (the Dolphin Cove gully, nodes 774-776). A wall that narrows and stays narrow
## is a real funnel and is left alone.
func _fill_wall_dips() -> void:
	var n := t.vroad.size()
	for side in [-1.0, 1.0]:
		var w := PackedFloat32Array()
		for vr in t.vroad:
			w.append(vr.right_wall if side > 0.0 else vr.left_wall)
		for i in n:
			var before := 0.0
			var after := 0.0
			for k in range(1, WALL_DIP_NODES + 1):
				before = maxf(before, w[posmod(i - k, n)])
				after = maxf(after, w[(i + k) % n])
			var target := minf(before, after)
			if target < w[i] + 1.0:
				continue
			var reach := _level_reach(i, side, w[i], target)
			if side > 0.0:
				t.vroad[i].right_wall = reach
			else:
				t.vroad[i].left_wall = reach


## Where a wall steps in across ground still level with the road, draws it in over several
## nodes instead, WALL_TAPER at a time (~18 degrees), and no further out than that ground
## reaches: the slices' widths jump by 10-35 m from one node to the next at the ends of
## run-offs, lay-bys and lots (Dolphin Cove 317-321, Rocky Pass, Hills, Redrock), a wall
## across the car's path that stopped it dead. Tapered from both ways, for either direction.
func _taper_wall_steps() -> void:
	var n := t.vroad.size()
	for side in [-1.0, 1.0]:
		var w := PackedFloat32Array()
		for vr in t.vroad:
			w.append(vr.right_wall if side > 0.0 else vr.left_wall)
		var out := w.duplicate()
		for step in [1, -1]:
			var run := w.duplicate()
			# Twice round, so a taper carries on over the lap's seam.
			for k in 2 * n:
				var i := posmod(k * step, n)
				var target: float = run[posmod(i - step, n)] - WALL_TAPER
				if target > run[i] + 0.5:
					run[i] = maxf(run[i], _level_reach(i, side, run[i], target))
			for i in n:
				out[i] = maxf(out[i], run[i])
		for i in n:
			if side > 0.0:
				t.vroad[i].right_wall = out[i]
			else:
				t.vroad[i].left_wall = out[i]


## How far (m, from `from` up to `to`) the ground at node `i` stays level with the road
## on `side` (+1 right): facing up and within ROAD_REACH of its surface, as _flag_road asks.
func _level_reach(i: int, side: float, from: float, to: float) -> float:
	var vr := t.vroad[i]
	var up := vr.normal.normalized()
	var right := vr.right.normalized() * side
	var bi := i / NODES_PER_BLOCK
	var reach := from
	var d := from + 1.0
	while d <= to:
		var q := vr.pos + right * d
		var q2 := Vector2(q.x, q.z)
		var level := false
		for bk in range(maxi(bi - 1, 0), mini(bi + 2, t.blocks.size())):
			for g: Array in _ground_of(bk):
				var box: Rect2 = g[0]
				if not box.has_point(q2):
					continue
				var c2: PackedVector2Array = g[1]
				if not (Geometry2D.point_is_inside_triangle(q2, c2[0], c2[1], c2[2]) \
						or Geometry2D.point_is_inside_triangle(q2, c2[0], c2[2], c2[3])):
					continue
				var nrm: Vector3 = g[2]
				var a: Vector3 = g[3]
				if nrm.dot(up) <= MIN_FACING:
					continue
				# The poly's height under the sample point.
				var y := a.y - (nrm.x * (q.x - a.x) + nrm.z * (q.z - a.z)) / nrm.y
				if absf((Vector3(q.x, y, q.z) - vr.pos).dot(up)) < ROAD_REACH:
					level = true
					break
			if level:
				break
		if not level:
			break
		reach = d
		d += 1.0
	return reach


## Block `bi`'s road and terrain polys that face up at all, for _level_reach: [ground-plane
## bounds, corners on the ground plane, normal, a corner] each, made on first use.
func _ground_of(bi: int) -> Array:
	if _ground.has(bi):
		return _ground[bi]
	var out := []
	var b := t.blocks[bi]
	for p: Nfs3Track.Poly in b.road:
		if p.v[0] >= b.verts.size() or p.v[1] >= b.verts.size() or p.v[2] >= b.verts.size() or p.v[3] >= b.verts.size():
			continue
		var a := b.verts[p.v[0]]
		var c := b.verts[p.v[2]]
		var nrm := (c - a).cross(b.verts[p.v[1]] - b.verts[p.v[3]]).normalized()
		if nrm.y < 0.01:
			continue
		var c2 := PackedVector2Array()
		for k in 4:
			c2.append(Vector2(b.verts[p.v[k]].x, b.verts[p.v[k]].z))
		var box := Rect2(c2[0], Vector2.ZERO)
		for k in range(1, 4):
			box = box.expand(c2[k])
		out.append([box.grow(0.01), c2, nrm, a])
	_ground[bi] = out
	return out


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

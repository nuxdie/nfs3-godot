class_name Nfs3Track
## Parses an NFS3 track folder (trkNNN/trNN.frd + .col + trNN0.qfs) into plain data
## and builds Godot nodes from it. Coordinates are converted to Godot space by
## mirroring X (NFS3 is left-handed).

const POLY_SIZE := 14
const TEX_BLOCK_SIZE := 47
const QUAD := [0, 1, 2, 0, 2, 3]

class Poly:
	var v: PackedInt32Array
	var tex: int
	var flags: int
	var anim_frames := 0    # animated texture (fire, water, ...): frames in textures tex, tex+1, ...
	var anim_period := 0    # game ticks per frame

class Block:
	var center: Vector3
	var verts: PackedVector3Array
	var shading: PackedColorArray
	var n_hires_verts: int
	var n_object_verts: int
	var road: Array = []        # Array[Poly] (LOD chunk 4, high res)
	var road_flags := PackedByteArray()   # per road poly; see drivable()
	var lanes: Array = []       # Array[Poly] (chunk 6, lane markings)
	var objects: Array = []     # Array[Array[Poly]] block-local scenery
	var xobjs: Array = []       # Array[Dictionary] {ref, verts, shading, polys, anim}
	var lights: PackedVector3Array = []

class TexInfo:
	var width: int
	var height: int
	var uv: PackedVector2Array
	var is_lane: bool       # painted road marking (a sfx.fsh sprite, see _add_lane_images)
	var additive: bool      # glows, fire, light shafts: drawn additively over the scene
	var cutout: bool        # alpha-tested (foliage, fences, railings)
	var qfs_index: int

class VRoad:
	var pos: Vector3
	var normal: Vector3
	var forward: Vector3
	var right: Vector3
	var left_wall: float
	var right_wall: float

var name := ""
var blocks: Array[Block] = []
var textures: Array[TexInfo] = []
var vroad: Array[VRoad] = []
var col_objects: Array = []   # Array[Dictionary] {ref, verts, shading, polys}: static ones only
var images: Array[Image] = []
var error := ""


static func mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


static func shade(packed: int) -> Color:
	return Color8((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF, (packed >> 24) & 0xFF)


static func read_vec3s(d: PackedByteArray, p: int, n: int) -> PackedVector3Array:
	var f := d.slice(p, p + n * 12).to_float32_array()
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(-f[i * 3], f[i * 3 + 1], f[i * 3 + 2])
	return out


static func read_shading(d: PackedByteArray, p: int, n: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		out[i] = shade(d.decode_u32(p + i * 4))
	return out


static func read_polys(d: PackedByteArray, p: int, n: int) -> Array:
	var out := []
	out.resize(n)
	for i in n:
		var q := p + i * POLY_SIZE
		var poly := Poly.new()
		poly.v = PackedInt32Array([d.decode_u16(q), d.decode_u16(q + 2), d.decode_u16(q + 4), d.decode_u16(q + 6)])
		poly.tex = d.decode_u16(q + 8)
		poly.flags = d[q + 12]
		# Flag 0x04: animated texture; the last byte packs frame count (low 3 bits) and
		# ticks per frame (high 5 bits). The frames are the next entries of the texture table.
		if poly.flags & 0x04 and d[q + 13] & 7 >= 2 and d[q + 13] >> 3 > 0:
			poly.anim_frames = d[q + 13] & 7
			poly.anim_period = d[q + 13] >> 3
		out[i] = poly
	return out


## Whether a road poly (by its flags from the block's poly table) can be driven on. The low
## nibble is the surface: 14 is the scenery terrain beyond the road's edge, 0 the ground
## under buildings and past road-closed barriers; every other value is a road, verge or
## shortcut surface.
static func drivable(flags: int) -> bool:
	var surface := flags & 0x0F
	return surface != 0 and surface != 14


static func fixed(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_s32(p) / 65536.0, d.decode_s32(p + 4) / 65536.0, d.decode_s32(p + 8) / 65536.0)


## `n` animation keyframes of 20 bytes: fixed-point position, then the rotation.
static func anim_keys(d: PackedByteArray, p: int, n: int) -> Array:
	var keys := []
	for a in n:
		var q := p + a * 20
		# Fixed-point (1.0 = 16384) x, y, z, w; mirroring X flips the y and z parts.
		var rot := Quaternion(d.decode_s16(q + 12), -d.decode_s16(q + 14), -d.decode_s16(q + 16), d.decode_s16(q + 18))
		keys.append({
			"pos": fixed(d, q),
			"rot": rot.normalized() if rot.length_squared() > 1.0 else Quaternion.IDENTITY,
		})
	return keys


## Whether the FRD already has animated object `o` (same mesh size and starting point).
func _has_anim_xobj(o: Dictionary) -> bool:
	for b in blocks:
		for x in b.xobjs:
			if x.has("anim") and x.verts.size() == o.verts.size() and x.ref.distance_to(o.ref) < 0.1:
				return true
	return false


# --------------------------------------------------------------------- loading

static func load_dir(dir: String) -> Nfs3Track:
	var t := Nfs3Track.new()
	t.name = dir.get_file().to_lower()
	var short := t.name.replace("k0", "")  # trk000 -> tr00
	var frd_path := DataPath.find_ci(dir, short + ".frd")
	var frd := FileAccess.get_file_as_bytes(frd_path) if frd_path != "" else PackedByteArray()
	if frd.is_empty():
		t.error = "missing " + short + ".frd"
		return t
	if not t._parse_frd(frd):
		return t
	var col_path := DataPath.find_ci(dir, short + ".col")
	var col := FileAccess.get_file_as_bytes(col_path) if col_path != "" else PackedByteArray()
	if not col.is_empty() and not t._parse_col(col):
		return t
	var fsh := Fsh.load_file(DataPath.find_ci(dir, short + "0.qfs"))
	if fsh:
		t.images = fsh.images
	else:
		t.error = "missing texture archive"
		return t
	# Lane markings aren't in the track's archive: their textures index the shared lin0-lin9
	# sprites of gamedata/render/pc/sfx.fsh (the game's tracks folder is gamedata/tracks).
	t._add_lane_images(Fsh.load_file(DataPath.find_ci(dir.get_base_dir().get_base_dir(), "render/pc/sfx.fsh")))
	return t


## Appends the lane sprites the lane textures use to `images` and points them there; with
## no sfx archive, lane textures get an index past the end, so nothing draws them.
func _add_lane_images(sfx: Fsh) -> void:
	var layer_of := {}
	for ti in textures:
		if not ti.is_lane:
			continue
		var sprite := "lin%d" % ti.qfs_index
		if not layer_of.has(sprite):
			layer_of[sprite] = -1
			if sfx and sfx.by_name.has(sprite):
				layer_of[sprite] = images.size()
				images.append(sfx.by_name[sprite])
		ti.qfs_index = layer_of[sprite] if layer_of[sprite] >= 0 else 0xFFFF


## Just the block centres along the lap (Godot space), read from the FRD headers without
## building anything: enough for the menu's track map. Empty if the file is missing or bad.
static func peek_outline(dir: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var short := dir.get_file().to_lower().replace("k0", "")
	var frd_path := DataPath.find_ci(dir, short + ".frd")
	var d := FileAccess.get_file_as_bytes(frd_path) if frd_path != "" else PackedByteArray()
	if d.size() < 32:
		return out
	var n_blocks := d.decode_u32(28) + 1
	if n_blocks < 1 or n_blocks > 1000:
		return out
	var p := 32
	for bi in n_blocks:
		if p + 84 > d.size():
			return PackedVector3Array()
		out.append(mirror(Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))))
		var n_verts := d.decode_u32(p + 60)
		p += 84 + n_verts * 16 + 4 * 0x12C
		if p + 32 > d.size():
			return PackedVector3Array()
		var n := [d.decode_u32(p + 4), d.decode_u32(p + 8), d.decode_u32(p + 12), d.decode_u32(p + 16),
			d.decode_u32(p + 20), d.decode_u32(p + 24), d.decode_u32(p + 28)]
		p += 32 + n[0] * 8 + n[1] * 8 + n[2] * 12 + n[3] * 20 + n[4] * 20 + n[5] * 16 + n[6] * 16
	return out


## True (and sets `error`) when `n` bytes at `p` run past the end of the file: a damaged or
## truncated file is rejected instead of being read as garbage.
func _short(d: PackedByteArray, p: int, n: int, what: String) -> bool:
	if p < 0 or n < 0 or p + n > d.size():
		error = "truncated or damaged " + what
		return true
	return false


func _parse_frd(d: PackedByteArray) -> bool:
	if _short(d, 0, 32, "FRD"):
		return false
	var n_blocks := d.decode_u32(28) + 1
	if n_blocks < 1 or n_blocks > 1000:
		error = "bad FRD block count"
		return false
	var p := 32
	var poly_counts: Array[int] = []
	for bi in n_blocks:
		if _short(d, p, 84, "FRD"):
			return false
		var b := Block.new()
		b.center = mirror(Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)))
		p += 60
		var n_verts := d.decode_u32(p)
		b.n_hires_verts = d.decode_u32(p + 4)
		b.n_object_verts = d.decode_u32(p + 20)
		p += 24
		if _short(d, p, n_verts * 16 + 4 * 0x12C + 32, "FRD"):
			return false
		b.verts = read_vec3s(d, p, n_verts)
		p += n_verts * 12
		b.shading = read_shading(d, p, n_verts)
		p += n_verts * 4
		p += 4 * 0x12C  # neighbour table
		var n_pos := d.decode_u32(p + 4)
		var n_poly := d.decode_u32(p + 8)
		var n_vroad := d.decode_u32(p + 12)
		var n_xobj := d.decode_u32(p + 16)
		var n_polyobj := d.decode_u32(p + 20)
		var n_sound := d.decode_u32(p + 24)
		var n_light := d.decode_u32(p + 28)
		p += 32
		if _short(d, p, n_pos * 8 + n_poly * 8, "FRD"):
			return false
		# Per road poly: vroad entry, flags, 6 unknown bytes.
		b.road_flags.resize(n_poly)
		for i in n_poly:
			b.road_flags[i] = d[p + n_pos * 8 + i * 8 + 1]
		p += n_pos * 8 + n_poly * 8 + n_vroad * 12 + n_xobj * 20 + n_polyobj * 20 + n_sound * 16
		if _short(d, p, n_light * 16, "FRD"):
			return false
		for li in n_light:
			b.lights.append(fixed(d, p + li * 16))
		p += n_light * 16
		poly_counts.append(n_poly)
		blocks.append(b)

	for bi in n_blocks:
		var b := blocks[bi]
		for chunk in 7:
			if _short(d, p, 4, "FRD"):
				return false
			var sz := d.decode_u32(p)
			p += 4
			if sz == 0:
				continue
			if _short(d, p, 4 + sz * POLY_SIZE, "FRD"):
				return false
			p += 4  # duplicate size
			if chunk == 4:
				b.road = read_polys(d, p, sz)
			elif chunk == 6:
				b.lanes = read_polys(d, p, sz)
			p += sz * POLY_SIZE
		for chunk in 4:
			if _short(d, p, 4, "FRD"):
				return false
			var n1 := d.decode_u32(p)
			p += 4
			if n1 == 0:
				continue
			if _short(d, p, 4, "FRD"):
				return false
			var n2 := d.decode_u32(p)
			p += 4
			for k in n2:
				if _short(d, p, 8, "FRD"):
					return false
				var typ := d.decode_u32(p)
				p += 4
				if typ == 1:
					var np := d.decode_u32(p)
					p += 4
					if _short(d, p, np * POLY_SIZE, "FRD"):
						return false
					b.objects.append(read_polys(d, p, np))
					p += np * POLY_SIZE

	for xi in 4 * n_blocks + 1:
		if _short(d, p, 4, "FRD"):
			return false
		var nobj := d.decode_u32(p)
		p += 4
		for k in nobj:
			if _short(d, p, 12 + 24, "FRD"):
				return false
			var crosstype := d.decode_u32(p)
			p += 12
			var x := {}
			if crosstype == 4:
				x.ref = mirror(Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)))
				p += 16
			elif crosstype == 3:
				var n_anim := d.decode_u16(p + 20)
				x.anim_delay = d.decode_u16(p + 22)
				p += 24
				if _short(d, p, n_anim * 20, "FRD"):
					return false
				var keys := anim_keys(d, p, n_anim)
				p += n_anim * 20
				x.anim = keys
				x.ref = keys[0].pos if keys.size() > 0 else Vector3.ZERO
			else:
				error = "unknown xobj type %d" % crosstype
				return false
			if _short(d, p, 4, "FRD"):
				return false
			var nv := d.decode_u32(p)
			p += 4
			if _short(d, p, nv * 16 + 4, "FRD"):
				return false
			x.verts = read_vec3s(d, p, nv)
			p += nv * 12
			x.shading = read_shading(d, p, nv)
			p += nv * 4
			var np := d.decode_u32(p)
			p += 4
			if _short(d, p, np * POLY_SIZE, "FRD"):
				return false
			x.polys = read_polys(d, p, np)
			p += np * POLY_SIZE
			# XOBJ blocks are laid out 4 per track block (+1 global).
			blocks[mini(xi / 4, n_blocks - 1)].xobjs.append(x)

	if _short(d, p, 4, "FRD"):
		return false
	var n_tex := d.decode_u32(p)
	p += 4
	if _short(d, p, n_tex * TEX_BLOCK_SIZE, "FRD"):
		return false
	for i in n_tex:
		var ti := TexInfo.new()
		ti.width = d.decode_u16(p)
		ti.height = d.decode_u16(p + 2)
		var c := d.slice(p + 8, p + 40).to_float32_array()
		ti.uv = PackedVector2Array([Vector2(c[0], c[1]), Vector2(c[2], c[3]), Vector2(c[4], c[5]), Vector2(c[6], c[7])])
		# Low byte of the flags word: 0x04 = alpha cut-out, 0x02 = additive.
		ti.additive = (d[p + 40] & 0x02) != 0
		ti.cutout = (d[p + 40] & 0x04) != 0
		ti.is_lane = d[p + 44] != 0
		ti.qfs_index = d.decode_u16(p + 45)
		textures.append(ti)
		p += TEX_BLOCK_SIZE
	return true


func _parse_col(d: PackedByteArray) -> bool:
	if d.slice(0, 4).get_string_from_ascii() != "COLL" or _short(d, 0, 16, "COL"):
		error = "bad COL file"
		return false
	var n_xb := d.decode_u32(12)
	var p := 16 + n_xb * 4
	if n_xb > 16 or _short(d, p, 8, "COL"):
		return false
	# texture table
	var tex_nrec := d.decode_u16(p + 6)
	var col_tex: Array[int] = []
	p += 8
	if _short(d, p, tex_nrec * 8 + 8, "COL"):
		return false
	for i in tex_nrec:
		col_tex.append(d.decode_u16(p + i * 8))
	p += tex_nrec * 8
	var structs := []
	if n_xb >= 4:
		var n := d.decode_u16(p + 6)
		p += 8
		for i in n:
			if _short(d, p, 8, "COL"):
				return false
			var size := d.decode_u32(p)
			var nv := d.decode_u16(p + 4)
			var np := d.decode_u16(p + 6)
			if size < 8 + nv * 16 + np * 6 or _short(d, p, size, "COL"):
				error = "truncated or damaged COL"
				return false
			var q := p + 8
			var verts := PackedVector3Array()
			var sh := PackedColorArray()
			for v in nv:
				verts.append(mirror(Vector3(d.decode_float(q), d.decode_float(q + 4), d.decode_float(q + 8))))
				sh.append(shade(d.decode_u32(q + 12)))
				q += 16
			var polys := []
			for k in np:
				var poly := Poly.new()
				var ct := d.decode_u16(q)
				poly.tex = col_tex[ct] if ct < col_tex.size() else 0
				poly.v = PackedInt32Array([d[q + 2], d[q + 3], d[q + 4], d[q + 5]])
				poly.flags = 0
				polys.append(poly)
				q += 6
			structs.append({"verts": verts, "shading": sh, "polys": polys})
			p += size
		for pass_i in (2 if n_xb == 5 else 1):
			if _short(d, p, 8, "COL"):
				return false
			var n_obj := d.decode_u16(p + 6)
			p += 8
			for i in n_obj:
				if _short(d, p, 4, "COL"):
					return false
				var size := d.decode_u16(p)
				if size < 4 or _short(d, p, size, "COL"):
					error = "truncated or damaged COL"
					return false
				var typ := d[p + 2]
				var s := d[p + 3]
				if s >= structs.size():
					p += size
					continue
				var o := {"ref": Vector3.ZERO, "verts": structs[s].verts, "shading": structs[s].shading, "polys": structs[s].polys, "col_tex": true}
				if typ == 1 and size >= 16:
					o.ref = fixed(d, p + 4)
					col_objects.append(o)
				elif typ == 3:
					# Animated: {size, type, struct, n_keys, delay} then keys as in the FRD. The
					# FRD mostly carries the same objects; the rest join its animated xobjs.
					var n_anim := d.decode_u16(p + 4)
					if n_anim == 0 or size < 8 + n_anim * 20:
						p += size
						continue
					o.anim = anim_keys(d, p + 8, n_anim)
					o.anim_delay = d.decode_u16(p + 6)
					o.ref = o.anim[0].pos
					if not _has_anim_xobj(o) and blocks.size() > 0:
						blocks[-1].xobjs.append(o)
				p += size
	# virtual road
	if _short(d, p, 8, "COL"):
		return false
	var n_vr := d.decode_u16(p + 6)
	p += 8
	if _short(d, p, n_vr * 36, "COL"):
		return false
	for i in n_vr:
		var q := p + i * 36
		var vr := VRoad.new()
		vr.pos = fixed(d, q)
		vr.normal = _i8vec(d, q + 16)
		vr.forward = _i8vec(d, q + 20)
		vr.right = _i8vec(d, q + 24)
		vr.left_wall = d.decode_u32(q + 28) / 65536.0
		vr.right_wall = d.decode_u32(q + 32) / 65536.0
		vroad.append(vr)
	return true


static func _i8vec(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_s8(p) / 128.0, d.decode_s8(p + 1) / 128.0, d.decode_s8(p + 2) / 128.0)

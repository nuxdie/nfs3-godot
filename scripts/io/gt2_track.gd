class_name Gt2Track
extends Nfs5Track
## A Gran Turismo 2 course, out of GT2.VOL (Gt2Vol): crsobj/<name>.tro (its geometry) and
## .trp (its textures), as Porsche Unleashed's track data (Nfs5TrackBuilder builds it).
## Its "folder" is "gt2:<name>" (Game.track_dir).
##
## The .tro ("@(#)GT-PS", after Nenkai's 010 template, the rest worked out here): at 0x10
## the offsets of the chunk table, the object LOD table and its data; at 0x48 the start line
## (16.16 fixed point, metres) and 0x58 the grid's 16 slots; at 0x118 33 offsets of the
## placed objects' lists ({count, then 28 bytes each: rotation x y z (4096 a turn), object,
## scale x y z (4096 = 1), visible, position x y z (16.16)}).
## The chunk table: u16 x2, u16 chunk count, u16 UV record count / 2, offset of the UV records
## (16 bytes each: uv0, palette, uv1, page, uv2, uv3, 4 bytes more), the chunks' offsets.
## A chunk: u16 previous and next chunk, ..., its centre at 0x30 (16.16), and at 0xA4 its
## shape: offsets of its vertices and of 8 polygon lists, then their counts. Vertices are 8
## bytes (s16 x, z, height, 0) in 1/64 m about the centre rounded down to 64 m (each axis). The lists
## are the PS1's primitives in order (flat tri, quad; gouraud tri, quad; textured tri, quad;
## both), 12 bytes (gouraud: 20, 24): u32 three 9-bit vertex indices; u32 a quad's fourth
## index (9 bits), a 10-bit UV record index from bit 9, the surface at 24; colour and code;
## the gouraud ones' other corners' colours. Object meshes (s16 x, height, z; z mirrored to
## match the chunks): as a shape, the LOD's vertex scale
## in its last u32 (2^(s - 16) / 4096 m, as GT2's cars), 24-byte polygons: u32 three 10-bit
## indices, u32 the fourth, colour and code, then uv0 + palette, uv1 + page, uv2, uv3.

const STRIDE := [12, 12, 20, 24, 12, 12, 20, 24]
const QUAD_LIST := [false, true, false, true, false, true, false, true]
const TEXTURED_LIST := [false, false, false, false, true, true, true, true]
const GOURAUD_LIST := [false, false, true, true, false, false, true, true]
const FIXED := 65536.0
const VERT_UNIT := 1.0 / 64.0
const CELL := 64.0
## The faces steeper than this (their normal's y under it, ~37°) are scenery (solid), the rest road.
const FLAT := 0.8
## A steep face lower than this (m) is road all the same.
const LOW_STEP := 0.6
## A course whose last chunk is this near the start line (m) is a lap; one whose chain jumps
## this many times its chunks' usual spacing is a run that ends there.
const CLOSE_REACH := 150.0
const JUMP := 4.0
## How far back from a run's start line its lead-in reaches (m): room for its grid.
const LEAD_IN := 250.0
## An image under this share of the driving line's samples isn't tarmac (a kerb it clips).
const TARMAC_SHARE := 0.01
## The centring's smoothing, nodes either side.
const SMOOTH := 4
## The driving line guides the centring within this distance (m).
const LINE_REACH := 30.0
## A driving line whose ends are this near each other (m), the road between, goes round the lap.
const LINE_GAP := 1500.0
const LINE_ON_ROAD := 0.9
## The widest a road is taken to reach either side of where it's aimed for (m).
const HALF_ROAD := 9.0
## The stretch of road the grid stands on: this far behind the start line (m), and ahead.
const GRID_ZONE := 150.0
const GRID_AHEAD := 20.0
const GRID_BLEND := 30.0
## How far past the tarmac the walls may stand (m), and at least stand.
const VERGE := 8.0
const MIN_VERGE := 3.0
## The road is taken to be at least this wide either side of the centre line (m): where the
## tarmac goes unseen (the start line's and grid's paint), room for the grid's two columns.
const MIN_HALF := 5.0
## Objects wider than this (m) are backdrop hills; their faces this far (m) above the road
## beneath them are left out (_add_poly).
const BACKDROP_SPAN := 100.0
const OVERHANG := 8.0
## The centre line's nodes are this far apart (m).
const NODE_STEP := 4.0
## How far out from the centre line the road may reach (m), and the step the edge is found in.
const WALL_REACH := 40.0
const WALL_STEP := 0.5

## The disc the courses come from (Game sets it when it finds one).
static var vol: Gt2Vol

var course := ""
var misses := 0              # textured faces whose image wasn't found
var _d := PackedByteArray()
var _tex_keys := {}          # palette << 16 | page -> [image indices]
var _tex_rect: Array[Rect2i] = []   # each image's place in its page (u, v, w, h)
var _white := -1             # the plain image the untextured faces use
var _road_tris := []         # [a, b, c, image], the flat faces (for the centre line)
var _tarmac := {}            # image -> true: the ones under GT2's driving lines
var _start := Vector3.ZERO
var _open := false
var _grid: Array[Vector3] = []


static func is_track_dir(dir: String) -> bool:
	return dir.begins_with("gt2:")


static func load_dir(dir: String, _night := false) -> Gt2Track:
	var t := Gt2Track.new()
	t.course = dir.trim_prefix("gt2:")
	t.name = t.course
	if vol == null:
		t.error = "no Gran Turismo 2 disc"
		return t
	t._d = vol.read("crsobj/%s.tro.gz" % t.course)
	var trp := vol.read("crsobj/%s.trp.gz" % t.course)
	if t._d.size() < 0x19C or t._d.slice(0, 9).get_string_from_ascii() != "@(#)GT-PS":
		t.error = "bad crsobj/%s.tro" % t.course
		return t
	t._read_textures(trp)
	t._read_header()
	t._read_chunks()
	t.backdrop = [_piece(Kind.ROAD), _piece(Kind.GROUND), _piece(Kind.SCENERY)]
	t._read_objects()
	t._make_vroad()
	if t.vroad.size() < 10:
		t.error = "no centre line"
	return t


static func _piece(kind: int) -> Piece:
	var p := Piece.new()
	p.kind = kind
	return p


## The chunk centres in the lap's order, for the menu's map (Godot space, metres).
static func peek_outline(dir: String) -> PackedVector3Array:
	var t := Gt2Track.new()
	t.course = dir.trim_prefix("gt2:")
	if vol == null:
		return PackedVector3Array()
	t._d = vol.read("crsobj/%s.tro.gz" % t.course)
	if t._d.size() < 0x19C:
		return PackedVector3Array()
	t._read_header()
	var out := PackedVector3Array()
	for c in t._chunk_order():
		out.append(t._centre(c))
	return out


# ---------------------------------------------------------------- the textures

## The .trp: a count, then PS1 TIM images (4 or 8 bits, with their palettes), each where it
## goes in the GPU's VRAM: its page and palette (as the polygons name
## them) and its place in the page.
func _read_textures(d: PackedByteArray) -> void:
	if d.size() < 8:
		return
	var n := d.decode_u32(0)
	var p := 4
	for i in n:
		if p + 8 > d.size() or d.decode_u32(p) != 0x10:
			break
		var flags := d.decode_u32(p + 4)
		var q := p + 8
		var clut := PackedInt32Array()
		var clut_id := 0
		if flags & 8:
			var size := d.decode_u32(q)
			var cx := d.decode_u16(q + 4)
			var cy := d.decode_u16(q + 6)
			var cw := d.decode_u16(q + 8)
			clut_id = (cx >> 4) | (cy << 6)
			for k in cw:
				clut.append(d.decode_u16(q + 12 + k * 2))
			q += size
		var size := d.decode_u32(q)
		var ix := d.decode_u16(q + 4)
		var iy := d.decode_u16(q + 6)
		var bpp := flags & 3
		var per := 4 if bpp == 0 else 2 if bpp == 1 else 1
		var w := d.decode_u16(q + 8) * per
		var h := d.decode_u16(q + 10)
		var px := d.slice(q + 12, q + size)
		p = q + size
		var rgba := PackedByteArray()
		rgba.resize(w * h * 4)
		for y in h:
			for x in w:
				var c := 0
				if bpp == 0:
					var b := px[(y * w + x) >> 1] if (y * w + x) >> 1 < px.size() else 0
					c = clut[(b >> ((x & 1) * 4)) & 15] if clut.size() >= 16 else 0
				elif bpp == 1:
					var k := px[y * w + x] if y * w + x < px.size() else 0
					c = clut[k] if k < clut.size() else 0
				else:
					c = px.decode_u16((y * w + x) * 2) if (y * w + x) * 2 + 1 < px.size() else 0
				var o := (y * w + x) * 4
				rgba[o] = (c & 31) << 3
				rgba[o + 1] = ((c >> 5) & 31) << 3
				rgba[o + 2] = ((c >> 10) & 31) << 3
				rgba[o + 3] = 0 if c == 0 else 255
		images.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba))
		image_names.append("")
		var page := (ix >> 6) | ((iy >> 8) << 4)
		var key := (clut_id << 16) | page
		if not _tex_keys.has(key):
			_tex_keys[key] = []
		_tex_keys[key].append(images.size() - 1)
		_tex_rect.append(Rect2i((ix & 63) * per, iy & 255, w, h))
	var white := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	images.append(white)
	image_names.append("")
	_white = images.size() - 1


## The image a textured face's palette and page name, and its UVs (bytes in the page) as
## that image's (0..1, repeating: GT2 tiles the road's textures by its texture window).
func _uvs(clut: int, page: int, uvs: Array[Vector2i]) -> Array:
	var cands: Array = _tex_keys.get((clut << 16) | (page & 0x1F), [])
	if cands.is_empty():
		misses += 1
		return [_white, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]]
	var img: int = cands[0]
	if cands.size() > 1:
		# (Several images on one palette and page: the one the UVs fall in.)
		var mid := Vector2i.ZERO
		for uv in uvs:
			mid += uv
		mid /= uvs.size()
		for c: int in cands:
			if _tex_rect[c].has_point(mid):
				img = c
				break
	var r := _tex_rect[img]
	var out: Array[Vector2] = []
	for uv in uvs:
		out.append(Vector2(float(uv.x - r.position.x + 0.5) / r.size.x, float(uv.y - r.position.y + 0.5) / r.size.y))
	return [img, out]


# ---------------------------------------------------------------- the header and chunks

var _chunk_at := PackedInt32Array()
var _uv_at := 0
var _uv_count := 0


func _read_header() -> void:
	var d := _d
	_read_lines()
	_start = _v32(0x48)
	for k in 16:
		var g := _v32(0x58 + k * 12)
		if g != Vector3.ZERO:
			_grid.append(g)
	var table := d.decode_u32(0x10)
	var n := d.decode_u16(table + 4)
	_uv_count = d.decode_u16(table + 6) * 2
	_uv_at = d.decode_u32(table + 8)
	_chunk_at.resize(n)
	for i in n:
		_chunk_at[i] = d.decode_u32(table + 12 + i * 4)


## GT2's AI driving lines (header 0x20: a header size, a count, the lists' offsets from the
## block; a list: a count, then 40 bytes each: type (1 an arc, its signed radius at 0x14),
## x, z (16.16 / 16, z the other way), ..., the heading at 0x24): the longest, which the
## lap's centre line follows (a curve through its points along their headings), and which
## tells the tarmac's images from the verges'.
var _line := PackedVector2Array()
var _line_dir := PackedVector2Array()   # its heading at each point (unit, XZ)
var _line_closed := false


func _read_lines() -> void:
	var d := _d
	var p := d.decode_u32(0x20)
	if p <= 0 or p + 8 > d.size():
		return
	var n := mini(d.decode_s32(p + 4), 7)
	for k in n:
		var o := d.decode_u32(p + 8 + k * 4)
		if o == 0 or p + o + 4 > d.size():
			continue
		var q := p + o
		var pts := PackedVector2Array()
		var dirs := PackedVector2Array()
		for i in d.decode_s32(q):
			var e := q + 4 + i * 40
			if e + 40 > d.size():
				break
			pts.append(Vector2(d.decode_s32(e + 4), -d.decode_s32(e + 8)) * 16.0 / FIXED)
			# The heading at 0x24, 4096 a turn.
			var a := d.decode_s32(e + 36) * TAU / 4096.0
			dirs.append(Vector2(-sin(a), -cos(a)))
		if pts.size() > _line.size():
			_line = pts
			_line_dir = dirs



## A 16.16 vector at `p` in metres.
func _v32(p: int) -> Vector3:
	return Vector3(_d.decode_s32(p), _d.decode_s32(p + 4), _d.decode_s32(p + 8)) / FIXED


func _centre(c: int) -> Vector3:
	return _v32(_chunk_at[c] + 0x30)


func _read_chunks() -> void:
	for c in _chunk_at.size():
		var at := _chunk_at[c]
		var centre := _centre(c)
		var origin := (centre / CELL).floor() * CELL
		var pieces := [_piece(Kind.ROAD), _piece(Kind.GROUND), _piece(Kind.SCENERY)]
		# (Its second shape at 0x94 is a coarse copy of this one, for far off: left out.)
		_add_shape(at + 0xA4, origin, VERT_UNIT, false, Transform3D.IDENTITY, pieces)
		chunks.append({"center": centre, "pieces": pieces})


## A shape's faces (a chunk's or an object's: `object` has the 24-byte polygons) into
## `pieces`, its vertices scaled by `unit` about `origin` and then moved by `xf`.
func _add_shape(p: int, origin: Vector3, unit: float, object: bool, xf: Transform3D, pieces: Array) -> void:
	var d := _d
	if p + 64 > d.size():
		return
	var verts_at := d.decode_u32(p)
	var n_verts := d.decode_s32(p + 44)
	if n_verts <= 0 or verts_at + n_verts * 8 > d.size():
		return
	var verts := PackedVector3Array()
	for k in n_verts:
		var q := verts_at + k * 8
		var v := Vector3(d.decode_s16(q), d.decode_s16(q + 4), d.decode_s16(q + 2)) if not object \
			else Vector3(d.decode_s16(q), d.decode_s16(q + 2), -d.decode_s16(q + 4))
		verts.append(xf * (origin + v * unit))
	for li in 8:
		var list_at := d.decode_u32(p + 4 + li * 4)
		var count := d.decode_s16(p + 48 + li * 2)
		var stride: int = 24 if object else STRIDE[li]
		for k in count:
			var q := list_at + k * stride
			if q + stride > d.size():
				break
			_add_poly(q, li, object, verts, pieces)


func _add_poly(q: int, li: int, object: bool, verts: PackedVector3Array, pieces: Array) -> void:
	var d := _d
	var w0 := d.decode_u32(q)
	var w1 := d.decode_u32(q + 4)
	var quad: bool = QUAD_LIST[li]
	var idx := PackedInt32Array()
	if object:
		idx = PackedInt32Array([w0 & 0x3FF, (w0 >> 10) & 0x3FF, (w0 >> 20) & 0x3FF])
		if quad:
			idx.append(w1 & 0x3FF)
	else:
		idx = PackedInt32Array([w0 & 0x1FF, (w0 >> 9) & 0x1FF, (w0 >> 18) & 0x1FF])
		if quad:
			idx.append(w1 & 0x1FF)
	for i in idx:
		if i >= verts.size():
			return
	# Colours, one per corner on the gouraud ones: a textured face's tint its texture (128 as
	# it is), an untextured one's its colour (255 full); halved, as Porsche Unleashed's, which
	# Nfs5TrackBuilder lights at twice their value.
	var full := 256.0 if TEXTURED_LIST[li] else 510.0
	var cols: Array[Color] = []
	var base := Color(d[q + 8] / full, d[q + 9] / full, d[q + 10] / full)
	for k in idx.size():
		if GOURAUD_LIST[li] and k > 0 and not object and q + 8 + k * 4 + 3 <= q + STRIDE[li]:
			var o := q + 8 + k * 4
			cols.append(Color(d[o] / full, d[o + 1] / full, d[o + 2] / full))
		else:
			cols.append(base)
	# The texture and its UVs.
	var img := _white
	var uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	if TEXTURED_LIST[li]:
		var rec := q + 12
		if not object:
			var k := (w1 >> 9) & 0x3FF
			if k >= _uv_count:
				return
			rec = _uv_at + k * 16
		var uvs: Array[Vector2i] = [Vector2i(d[rec], d[rec + 1]), Vector2i(d[rec + 4], d[rec + 5]),
			Vector2i(d[rec + 8], d[rec + 9]), Vector2i(d[rec + 10], d[rec + 11])]
		if not quad:
			uvs.resize(3)
		var got := _uvs(d.decode_u16(rec + 2), d.decode_u16(rec + 6), uvs)
		img = got[0]
		uv = got[1]
		if not quad:
			uv.append(Vector2.ZERO)
	# Quads go round their edge, as the cars' (0 1 2 3).
	var tris := [[0, 1, 2]] if not quad else [[0, 1, 2], [0, 2, 3]]
	for tri in tris:
		var a := verts[idx[tri[0]]]
		var b := verts[idx[tri[1]]]
		var c := verts[idx[tri[2]]]
		# The backdrop hills' and tree lines' huge faces reach over the road (up high, or
		# standing across it): the PS1 draws them first, under everything nearer, so it never
		# shows; a depth buffer would. Left out there.
		if _backdrop_mesh and _hangs_over_road((a + b + c) / 3.0):
			continue
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-8:
			continue
		var up := absf(n.normalized().y) >= FLAT
		# (A low step, a kerb's or a pavement's edge, isn't a wall to stop a car dead: road.)
		if not up and not object and maxf(maxf(a.y, b.y), c.y) - minf(minf(a.y, b.y), c.y) < LOW_STEP:
			up = true
		var piece: Piece = pieces[Kind.ROAD if up else Kind.SCENERY]
		# Godot's front faces wind clockwise; GT2's, mirrored as they're read (the chunks'
		# by the swap, the objects' in z), anticlockwise. Objects show their fronts only, as
		# the PS1 draws them (their big hillsides would hang over the road from below).
		for k in [tri[0], tri[2], tri[1]]:
			piece.pos.append(verts[idx[k]])
			piece.uv.append(uv[k])
			piece.colour.append(cols[k])
		piece.tex.append(img)
		piece.scroll.append(Vector2.ZERO)
		if object:
			piece.one_sided.resize(piece.tex.size())
			piece.one_sided[piece.tex.size() - 1] = 1
		if up and not object:
			_road_tris.append([a, b, c, img])


# ---------------------------------------------------------------- placed objects

var _over_road := {}         # the flat faces' grid, while the objects are added (see _add_poly)
var _backdrop_mesh := false  # the object being added is a big backdrop hill


func _read_objects() -> void:
	var d := _d
	_over_road = _tri_grid()
	var lod_table := d.decode_u32(0x14)
	var n_types := d.decode_s32(lod_table)
	var meshes := PackedInt32Array()
	for k in n_types:
		var o := d.decode_u32(lod_table + 4 + k * 4)
		meshes.append(d.decode_u32(o + 8) if d.decode_s32(o) > 0 else 0)   # the nearest LOD's
	var pieces := [_piece(Kind.ROAD), _piece(Kind.GROUND), _piece(Kind.SCENERY)]
	var far := [_piece(Kind.ROAD), _piece(Kind.GROUND), _piece(Kind.SCENERY)]
	for li in 33:
		var o := d.decode_u32(0x118 + li * 4)
		if o <= 0 or o + 4 > d.size():
			continue
		for k in d.decode_s32(o):
			var e := o + 4 + k * 28
			if e + 28 > d.size():
				break
			var kind := d.decode_u16(e + 6)
			if kind >= meshes.size() or meshes[kind] == 0:
				continue
			var rot := Vector3(d.decode_s16(e), d.decode_s16(e + 2), d.decode_s16(e + 4)) * TAU / 4096.0
			var scale := Vector3(d.decode_s16(e + 8), d.decode_s16(e + 10), d.decode_s16(e + 12)) / 4096.0
			var pos := _v32(e + 16)
			# (The meshes come mirrored in z, as the chunks' vertices by their swap: turns about
			# x and y go the other way.)
			var basis := Basis.from_euler(Vector3(-rot.x, -rot.y, rot.z), EULER_ORDER_YXZ).scaled(scale)
			var mesh := meshes[kind]
			var unit := pow(2.0, d.decode_s32(mesh + 84) - 16) / 4096.0
			_backdrop_mesh = _mesh_span(mesh) * unit > BACKDROP_SPAN
			# (The backdrop hills and tree lines are to be seen, not run into: Backdrop.)
			_add_shape(mesh, Vector3.ZERO, unit, true, Transform3D(basis, pos), far if _backdrop_mesh else pieces)
	_backdrop_mesh = false
	_over_road = {}
	for k in 3:
		backdrop[k].pos.append_array(far[k].pos)
		backdrop[k].uv.append_array(far[k].uv)
		backdrop[k].colour.append_array(far[k].colour)
		backdrop[k].tex.append_array(far[k].tex)
		backdrop[k].scroll.append_array(far[k].scroll)
		backdrop[k].one_sided.append_array(far[k].one_sided)
	# (The road kind of the backdrop would be road: as scenery, without the solid bodies.)
	backdrop[Kind.SCENERY].pos.append_array(backdrop[Kind.ROAD].pos)
	backdrop[Kind.SCENERY].uv.append_array(backdrop[Kind.ROAD].uv)
	backdrop[Kind.SCENERY].colour.append_array(backdrop[Kind.ROAD].colour)
	backdrop[Kind.SCENERY].tex.append_array(backdrop[Kind.ROAD].tex)
	backdrop[Kind.SCENERY].scroll.append_array(backdrop[Kind.ROAD].scroll)
	backdrop[Kind.SCENERY].one_sided.append_array(backdrop[Kind.ROAD].one_sided)
	backdrop[Kind.ROAD] = _piece(Kind.ROAD)
	if pieces[Kind.SCENERY].pos.size() + pieces[Kind.ROAD].pos.size() > 0:
		chunks.append({"center": _start, "pieces": pieces})


## A mesh's widest reach across (its vertices' x or z span, in its own units).
func _mesh_span(p: int) -> float:
	var at := _d.decode_u32(p)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in maxi(_d.decode_s32(p + 44), 0):
		var q := at + k * 8
		var v := Vector2(_d.decode_s16(q), _d.decode_s16(q + 4))
		lo = lo.min(v)
		hi = hi.max(v)
	return maxf(hi.x - lo.x, hi.y - lo.y) if lo.x < INF else 0.0


# ---------------------------------------------------------------- the centre line

## The chunks round the lap from the one at the start line, the way the grid faces.
func _chunk_order() -> PackedInt32Array:
	var order := PackedInt32Array()
	var n := _chunk_at.size()
	if n == 0:
		return order
	var first := 0
	for c in n:
		if _centre(c).distance_squared_to(_start) < _centre(first).distance_squared_to(_start):
			first = c
	var ahead := _ahead()
	var nxt := _d.decode_u16(_chunk_at[first] + 2)
	var prv := _d.decode_u16(_chunk_at[first])
	var use_next := nxt < n and (_centre(nxt) - _centre(first)).dot(ahead) >= (_centre(prv) - _centre(first)).dot(ahead) if prv < n else true
	var c := first
	var seen := {}
	while c < n and not seen.has(c):
		seen[c] = true
		order.append(c)
		c = _d.decode_u16(_chunk_at[c] + (2 if use_next else 0))
	# A point-to-point course still chains its finish back to its start: a jump far longer
	# than its chunks (Pikes Peak's summit to its foot). The run ends before it.
	var gaps := PackedFloat32Array()
	for i in order.size() - 1:
		gaps.append(_centre(order[i]).distance_to(_centre(order[i + 1])))
	if gaps.size() > 4:
		var sorted := gaps.duplicate()
		sorted.sort()
		var median := sorted[sorted.size() / 2]
		for i in gaps.size():
			if gaps[i] > JUMP * median:
				order = order.slice(0, i + 1)
				_open = true
				break
	return order


## The way the grid faces: from its slots towards the start line.
func _ahead() -> Vector3:
	if _grid.is_empty():
		return Vector3.FORWARD
	var mid := Vector3.ZERO
	for g in _grid:
		mid += g
	mid /= _grid.size()
	var f := Vector3(_start.x - mid.x, 0.0, _start.z - mid.z)
	return f.normalized() if f.length() > 0.1 else Vector3.FORWARD


func _make_vroad() -> void:
	var order := _chunk_order()
	if order.size() < 3:
		return
	var ahead := _ahead()
	closed = not _open and _centre(order[order.size() - 1]).distance_to(_start) < CLOSE_REACH
	# A run's grid stands behind its start line: the chunks before it, as the lead-in (the
	# race puts the grid on the nodes behind the start node, which a lap has anyway).
	var ctrl := PackedVector3Array()
	if not closed:
		var lead := PackedVector3Array()
		var c := _d.decode_u16(_chunk_at[order[0]])
		var seen := {order[0]: true}
		while c < _chunk_at.size() and not seen.has(c) and lead.size() < 40:
			seen[c] = true
			var p := _centre(c)
			if (p - _start).dot(ahead) < 0.0:
				lead.append(p)
				if _start.distance_to(p) > LEAD_IN:
					break
			c = _d.decode_u16(_chunk_at[c])
		lead.reverse()
		ctrl.append_array(lead)
	var start_ctrl := ctrl.size()
	ctrl.append(_start)
	for i in order.size():
		var p := _centre(order[i])
		# (The start chunk's middle may be behind the line.)
		if i == 0 and (p - _start).dot(ahead) < 0.0:
			continue
		ctrl.append(p)
	var grid := _tri_grid()
	_close_line(grid)
	_find_tarmac(grid)
	if closed and _line_closed and _line.size() > 10:
		_vroad_from(grid, _line_curve(), ahead)
		return
	# Catmull-Rom through the control points, a node every NODE_STEP.
	var pts := PackedVector3Array()
	var m := ctrl.size()
	var segs := m if closed else m - 1
	var start_node := 0
	for s in segs:
		if s == start_ctrl:
			start_node = pts.size()
		var p0 := ctrl[(s - 1 + m) % m] if closed or s > 0 else ctrl[0]
		var p1 := ctrl[s]
		var p2 := ctrl[(s + 1) % m]
		var p3 := ctrl[(s + 2) % m] if closed or s + 2 < m else ctrl[m - 1]
		var steps := maxi(1, ceili(p1.distance_to(p2) / NODE_STEP))
		for k in steps:
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	if not closed:
		pts.append(ctrl[m - 1])
	pts = _recentre(grid, pts)
	_vroad_from(grid, pts, ahead)
	if not closed:
		sprint = PackedInt32Array([start_node, vroad.size() - 1, vroad.size() - 1, start_node])


## The driving line as a curve (cubic Hermite through its points along their headings), a
## point every NODE_STEP, starting where it passes the start line.
func _line_curve() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in _line.size() - 1:
		var a := _line[i]
		var b := _line[i + 1]
		var len := a.distance_to(b)
		var ta := _line_dir[i] * len
		var tb := _line_dir[i + 1] * len
		var steps := maxi(1, ceili(len / NODE_STEP))
		for k in steps:
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			var q := (2.0 * t3 - 3.0 * t2 + 1.0) * a + (t3 - 2.0 * t2 + t) * ta + (-2.0 * t3 + 3.0 * t2) * b + (t3 - t2) * tb
			pts.append(Vector3(q.x, _start.y, q.y))
	# Node 0 at the start line.
	var first := 0
	for i in pts.size():
		if Vector2(pts[i].x - _start.x, pts[i].z - _start.z).length_squared() < \
				Vector2(pts[first].x - _start.x, pts[first].z - _start.z).length_squared():
			first = i
	return pts.slice(first) + pts.slice(0, first)


## The centre line's nodes at `pts`: on the road's surface, its tarmac's width either side
## (the AI's, the grid's) and the walls at the edge of everything drivable.
func _vroad_from(grid: Dictionary, pts: PackedVector3Array, ahead: Vector3) -> void:
	var walls_l := PackedFloat32Array()
	var walls_r := PackedFloat32Array()
	for i in pts.size():
		var f := (pts[(i + 1) % pts.size()] - pts[(i - 1 + pts.size()) % pts.size()]) if closed \
			else (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else ahead
		var vr := VRoad.new()
		var right := f.cross(Vector3.UP).normalized()
		var ground := _ground(grid, pts[i])
		vr.pos = Vector3(pts[i].x, ground[0] if ground[0] > -INF else pts[i].y, pts[i].z)
		vr.normal = ground[1]
		vr.forward = f
		vr.right = right
		var lanes := _tarmac_span(grid, vr.pos, right)
		vr.left_wall = maxf(-lanes.x, MIN_HALF)
		vr.right_wall = maxf(lanes.y, MIN_HALF)
		vroad.append(vr)
		# (The walls: at the edge of the drivable ground, but no further than a verge's width
		# past the tarmac: not up the grass banks.)
		walls_l.append(clampf(_edge(grid, vr.pos, -right), vr.left_wall + MIN_VERGE, vr.left_wall + VERGE))
		walls_r.append(clampf(_edge(grid, vr.pos, right), vr.right_wall + MIN_VERGE, vr.right_wall + VERGE))
	fences = [walls_l, walls_r]


## A lap's driving line starts and ends past the start line: it's closed over the road
## between its ends (the main straight) if they're no more than LINE_GAP apart and that
## stretch is over the road (LINE_ON_ROAD of it).
func _close_line(grid: Dictionary) -> void:
	if _line.size() < 3:
		return
	var a := _line[_line.size() - 1]
	var b := _line[0]
	if a.distance_to(b) > LINE_GAP:
		return
	var steps := maxi(2, int(a.distance_to(b) / 4.0))
	var on := 0
	for k in steps + 1:
		var q := a.lerp(b, float(k) / steps)
		if _tri_at(grid, Vector3(q.x, 0.0, q.y)) >= 0:
			on += 1
	if on >= LINE_ON_ROAD * (steps + 1):
		_line_closed = true
		_line.append(b)
		_line_dir.append(_line_dir[0])


## The images under the driving line (every 2 m along it), those with at least TARMAC_SHARE
## of the hits: the tarmac. Without a line, every flat face counts.
func _find_tarmac(grid: Dictionary) -> void:
	var hits := {}
	var total := 0
	for i in _line.size() - 1:
		var a := _line[i]
		var b := _line[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 2.0))
		for k in steps:
			var q := a.lerp(b, float(k) / steps)
			var t := _tri_at(grid, Vector3(q.x, 0.0, q.y))
			if t >= 0:
				var img: int = _road_tris[t][3]
				hits[img] = hits.get(img, 0) + 1
				total += 1
	for img: int in hits:
		if hits[img] >= TARMAC_SHARE * total:
			_tarmac[img] = true


## The flat face under `p` (its XZ), or -1.
func _tri_at(grid: Dictionary, p: Vector3) -> int:
	for i: int in grid.get(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0)), []):
		if _height_in(_road_tris[i], p) > -INF:
			return i
	return -1


## The tarmac across `p` along `right`: Vector2(left edge, right edge) in m from `p` (the
## run nearest `aim` m across, within WALL_REACH), or (0, 0) if there's none.
func _tarmac_span(grid: Dictionary, p: Vector3, right: Vector3, aim := 0.0) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var run_start := INF
	var x := -WALL_REACH
	while x <= WALL_REACH + WALL_STEP:
		var on := false
		if x <= WALL_REACH:
			var t := _tri_at(grid, p + right * x)
			on = t >= 0 and (_tarmac.is_empty() or _tarmac.has(_road_tris[t][3])) \
				and absf(_height_in(_road_tris[t], p + right * x) - p.y) < 4.0
		if on and run_start == INF:
			run_start = x
		elif not on and run_start != INF:
			var run := Vector2(run_start, x - WALL_STEP)
			# (Short gaps, a painted line's own image, join the run either side.)
			var d := 0.0 if run.x <= aim and run.y >= aim else minf(absf(run.x - aim), absf(run.y - aim))
			if run.y - run.x >= 3.0 and d < best_d:
				best_d = d
				best = run
			run_start = INF
		x += WALL_STEP
	# (A run wider than a road, the track and a paved apron or the pit lane side by side,
	# is taken as the road's width about where it's aimed for.)
	if best != Vector2.ZERO:
		best = Vector2(maxf(best.x, minf(aim, best.y) - HALF_ROAD), minf(best.y, maxf(aim, best.x) + HALF_ROAD))
	return best


## The nodes where the grid stands moved across to its slots' middle (the race lines its
## cars up either side of the centre line), blended in and out over GRID_BLEND.
func _through_grid(pts: PackedVector3Array, ahead: Vector3) -> PackedVector3Array:
	if _grid.is_empty():
		return pts
	var mid := _grid_middle()
	var out := pts.duplicate()
	var n := pts.size()
	# How far each node is behind node 0 (the start line) along the path: the lap's last
	# stretch before it, and its first after it (negative). Not by place: the lap passes
	# other bits of road level with the grid.
	var along := PackedFloat32Array()
	along.resize(n)
	var d := 0.0
	for i in n:
		along[i] = -d
		d += pts[i].distance_to(pts[(i + 1) % n])
	var lap := d
	for i in n:
		var behind := lap + along[i] if lap + along[i] < GRID_ZONE + GRID_BLEND else along[i]
		var w := clampf(minf(behind + GRID_AHEAD, GRID_ZONE - behind) / GRID_BLEND, 0.0, 1.0)
		if w <= 0.0:
			continue
		var f := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		f.y = 0.0
		var right := f.normalized().cross(Vector3.UP)
		out[i] = pts[i] + right * ((mid - pts[i]).dot(right) * w)
	return out


## The middle of the grid's slots (they stand in pairs either side of the straight's middle).
func _grid_middle() -> Vector3:
	var mid := Vector3.ZERO
	for g in _grid:
		mid += g
	return mid / _grid.size()


## How far across (along `right`) from `p` the driving line passes nearest, or 0 if it's
## more than LINE_REACH away.
func _line_offset(p: Vector3, right: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best := INF
	var at := Vector2.ZERO
	for i in _line.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(q, _line[i], _line[i + 1])
		var dd := c.distance_squared_to(q)
		if dd < best:
			best = dd
			at = c
	if best > LINE_REACH * LINE_REACH:
		return 0.0
	return (at - q).dot(Vector2(right.x, right.z))


## The nodes moved across to the middle of the tarmac (each its run's), the move smoothed
## along the road so the line doesn't jink where a run is cut short.
func _recentre(grid: Dictionary, pts: PackedVector3Array) -> PackedVector3Array:
	var n := pts.size()
	var shift := PackedFloat32Array()
	var rights := PackedVector3Array()
	for i in n:
		var f := pts[(i + 1) % n] - pts[(i - 1 + n) % n] if closed else pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		f.y = 0.0
		var right := f.normalized().cross(Vector3.UP).normalized() if f.length() > 0.01 else Vector3.RIGHT
		rights.append(right)
		var g := _ground(grid, pts[i])
		var p := Vector3(pts[i].x, g[0] if g[0] > -INF else pts[i].y, pts[i].z)
		# Where the grid stands, through its slots' middle (the race lines its cars up
		# either side of the centre line); elsewhere the tarmac where the driving line is
		# (not the pit lane beside it).
		var behind := (_start - p).dot(_ahead())
		if not _grid.is_empty() and behind > -GRID_AHEAD and behind < GRID_ZONE \
				and Vector2(p.x - _start.x, p.z - _start.z).length() < GRID_ZONE + GRID_AHEAD:
			shift.append((_grid_middle() - p).dot(right))
			continue
		var span := _tarmac_span(grid, p, right, _line_offset(p, right))
		shift.append((span.x + span.y) * 0.5 if span.y - span.x >= 3.0 else 0.0)
	var out := PackedVector3Array()
	for i in n:
		var sum := 0.0
		var cnt := 0
		for k in range(-SMOOTH, SMOOTH + 1):
			var j := i + k
			if closed:
				j = (j + n) % n
			elif j < 0 or j >= n:
				continue
			sum += shift[j]
			cnt += 1
		out.append(pts[i] + rights[i] * (sum / cnt))
	return out


## Whether `p` is over the road (above it, or less than OVERHANG below).
func _hangs_over_road(p: Vector3) -> bool:
	var t := _tri_at(_over_road, p)
	return t >= 0 and p.y - _height_in(_road_tris[t], p) > -OVERHANG


## The flat faces by XZ cell (16 m): Vector2i -> [triangle indices].
func _tri_grid() -> Dictionary:
	var g := {}
	for i in _road_tris.size():
		var t: Array = _road_tris[i]
		var lo := Vector2(minf(minf(t[0].x, t[1].x), t[2].x), minf(minf(t[0].z, t[1].z), t[2].z))
		var hi := Vector2(maxf(maxf(t[0].x, t[1].x), t[2].x), maxf(maxf(t[0].z, t[1].z), t[2].z))
		for x in range(floori(lo.x / 16.0), floori(hi.x / 16.0) + 1):
			for z in range(floori(lo.y / 16.0), floori(hi.y / 16.0) + 1):
				var key := Vector2i(x, z)
				if not g.has(key):
					g[key] = []
				g[key].append(i)
	return g


## The road under `p` (nearest to its height): [height, normal], or [-INF, UP] if none.
func _ground(grid: Dictionary, p: Vector3) -> Array:
	var best := -INF
	var normal := Vector3.UP
	for i: int in grid.get(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0)), []):
		var t: Array = _road_tris[i]
		var h := _height_in(t, p)
		if h > -INF and (best == -INF or absf(h - p.y) < absf(best - p.y)):
			best = h
			var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
			normal = n if n.y > 0.0 else -n
	return [best, normal]


static func _height_in(t: Array, p: Vector3) -> float:
	var a: Vector3 = t[0]
	var b: Vector3 = t[1]
	var c: Vector3 = t[2]
	var v0 := Vector2(c.x - a.x, c.z - a.z)
	var v1 := Vector2(b.x - a.x, b.z - a.z)
	var v2 := Vector2(p.x - a.x, p.z - a.z)
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return -INF
	var u := (v2.x * v1.y - v1.x * v2.y) / den
	var v := (v0.x * v2.y - v2.x * v0.y) / den
	if u < -0.001 or v < -0.001 or u + v > 1.002:
		return -INF
	return a.y + u * (c.y - a.y) + v * (b.y - a.y)


## How far the road reaches from `p` along `dir` before it stops (m).
func _edge(grid: Dictionary, p: Vector3, dir: Vector3) -> float:
	var d := 0.0
	var missed := 0
	var last := 2.0
	while d < WALL_REACH:
		d += WALL_STEP
		var q := p + dir * d
		var g := _ground(grid, q)
		if g[0] > -INF and absf(g[0] - p.y) < 3.0:
			last = d
			missed = 0
		else:
			missed += 1
			if missed * WALL_STEP > 1.5:
				break
	return maxf(last, 2.0)

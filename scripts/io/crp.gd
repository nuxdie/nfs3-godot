class_name Crp
## Reader for Need for Speed: Porsche Unleashed's CRP model files (cars "Car ", tracks
## "Trak"), RefPack-compressed as they ship. A CRP is a table of 16-byte entries: "Arti"cles
## (one object each: its name, base info and geometry) holding sub-entries, then "misc"
## entries shared by them (materials, render methods, and on tracks the virtual road).
## An entry is id (4 chars, or 2 chars + a 16-bit index when flag bit 0 is set), flags and
## data length, a count, and an offset from the entry to its data (to its sub-entries in
## 16-byte units for an article). The layout follows Arushan's CrpLib (LibOpenNFS).
##
## Geometry sub-entries are indexed by level of detail (low 4 bits; the damaged copy of a
## car part adds 0x8000, an animation frame n adds n << 4): "vt" vertices (4 floats each),
## "nm" normals, "uv" (2 floats), "df" per-corner colours (tracks), and "pr" parts, one
## triangle list per material, indexed level << 12 | part.

const ID_CAR := 0x43617220
const ID_TRACK := 0x5472616B
const ID_ARTI := 0x41727469
const INDEX_VERTEX := 0x4976
const INDEX_UV := 0x4975
const INFO_VERTEX := 0
const INFO_UV := 2
const INFO_COLOUR := 3
## A part's primitive (the first word of its header): 3 a triangle list, 1 a strip (a few
## tracks' set pieces: ramp decks, junction islands).
const PRIM_STRIP := 1

var path := ""
var track := false
## Per article: {name, subs: {"id:index" -> Entry}}.
var articles: Array[Dictionary] = []
var misc: Array[Entry] = []
var data := PackedByteArray()
var error := ""


class Entry:
	var id := ""
	var index := 0
	var length := 0
	var count := 0
	var offset := 0   # of its data in the file


static func load_file(path: String) -> Crp:
	var c := Crp.new()
	c.path = path
	var raw := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	if raw.size() < 16:
		c.error = "missing " + path.get_file()
		return c
	c.data = Qfs.decompress(raw)
	c._parse()
	return c


func _parse() -> void:
	var d := data
	var id := d.decode_u32(0)
	if id != ID_CAR and id != ID_TRACK:
		error = "not a CRP file"
		return
	track = id == ID_TRACK
	var n_arti := d.decode_u32(4) >> 5
	var n_misc := d.decode_u32(8)
	var table := d.decode_u32(12) << 4
	if table + (n_arti + n_misc) * 16 > d.size():
		error = "truncated CRP"
		return
	for i in n_arti:
		var at := table + i * 16
		var n_sub := d.decode_u32(at + 8)
		var subs_at := at + (d.decode_u32(at + 12) << 4)
		var art := {"name": "", "subs": {}}
		for k in n_sub:
			var e := _entry(subs_at + k * 16)
			if e == null:
				continue
			art.subs["%s:%d" % [e.id, e.index]] = e
			if e.id == "Name":
				art.name = d.slice(e.offset, e.offset + e.length).get_string_from_ascii().strip_edges()
		articles.append(art)
	for i in n_misc:
		var e := _entry(table + (n_arti + i) * 16)
		if e != null:
			misc.append(e)


func _entry(at: int) -> Entry:
	var d := data
	if at + 16 > d.size():
		return null
	var w0 := d.decode_u32(at)
	var w1 := d.decode_u32(at + 4)
	var e := Entry.new()
	if w1 & 1:
		e.index = w0 & 0xFFFF
		e.id = _fourcc(w0 >> 16, 2)
	else:
		e.id = _fourcc(w0, 4)
	e.length = w1 >> 8
	e.count = d.decode_u32(at + 8)
	e.offset = at + d.decode_s32(at + 12)
	if e.offset < 0 or e.offset + e.length > d.size():
		return null
	return e


static func _fourcc(v: int, n: int) -> String:
	var s := ""
	for k in range(n - 1, -1, -1):
		s += char((v >> (k * 8)) & 0xFF)
	return s


func sub(art: Dictionary, id: String, index := 0) -> Entry:
	return art.subs.get("%s:%d" % [id, index])


## The misc entries with this id, in file order.
func misc_of(id: String) -> Array[Entry]:
	var out: Array[Entry] = []
	for e in misc:
		if e.id == id:
			out.append(e)
	return out


## Vertices as stored (x, y, z; the fourth float is 1): Porsche Unleashed is left-handed
## like the other games, so X is mirrored for Godot.
func vec3s(e: Entry) -> PackedVector3Array:
	var out := PackedVector3Array()
	if e == null:
		return out
	var f := data.slice(e.offset, e.offset + e.count * 16).to_float32_array()
	out.resize(e.count)
	for i in e.count:
		out[i] = Vector3(-f[i * 4], f[i * 4 + 1], f[i * 4 + 2])
	return out


func uvs(e: Entry) -> PackedVector2Array:
	var out := PackedVector2Array()
	if e == null:
		return out
	var f := data.slice(e.offset, e.offset + e.count * 8).to_float32_array()
	out.resize(e.count)
	for i in e.count:
		out[i] = Vector2(f[i * 2], f[i * 2 + 1])
	return out


## Per-corner colours ("df"): 32-bit B, G, R, A.
func colours(e: Entry) -> PackedColorArray:
	var out := PackedColorArray()
	if e == null:
		return out
	out.resize(e.count)
	for i in e.count:
		var p := e.offset + i * 4
		out[i] = Color8(data[p + 2], data[p + 1], data[p], data[p + 3])
	return out


## A "pr" part: {material, trans, count (corners), vertex / uv / colour index lists (one per
## corner, already offset into the level's arrays)}. Its info rows say where in the
## level's vertex, uv and colour arrays this part's slice starts (in bytes); its index rows
## where its per-corner byte indices start among the part's own.
func part(e: Entry, sequential := false) -> Dictionary:
	var d := data
	var o := e.offset
	var p := {"trans": d.decode_u16(o + 2), "material": d.decode_s16(o + 4), "count": e.count,
		"vertex": PackedInt32Array(), "uv": PackedInt32Array(), "colour": PackedInt32Array()}
	var n_info := d.decode_s32(o + 40)
	var n_index := d.decode_s32(o + 44)
	var at := o + 48
	var base := {}   # info id -> first element
	for i in n_info:
		var off := d.decode_s32(at + 4)
		var info_id := d.decode_u16(at + 10)
		match info_id:
			INFO_UV:
				base[info_id] = off / 8
			INFO_VERTEX:
				base[info_id] = off / 16
			INFO_COLOUR:
				base[info_id] = off / 4
		at += 16
	var rows := {}   # index row id -> byte offset among the indices
	for i in n_index:
		rows[d.decode_u16(at + 2)] = d.decode_s32(at + 4)
		at += 8
	var indices_at := at
	if sequential and n_index == 0 and base.has(INFO_VERTEX):
		# No index rows: its corners are the vertices (and UVs) in order (the cars' dial
		# needles; on the tracks some set pieces, like Schwarzwald's covered bridges, and
		# much of the water, animated props and people).
		p.vertex.resize(e.count)
		p.uv.resize(e.count if base.has(INFO_UV) else 0)
		for k in e.count:
			p.vertex[k] = k + base[INFO_VERTEX]
			if base.has(INFO_UV):
				p.uv[k] = k + base[INFO_UV]
	elif not rows.has(INDEX_VERTEX) or indices_at + n_index * e.count > d.size():
		return p
	else:
		var vb: int = base.get(INFO_VERTEX, 0)
		var ub: int = base.get(INFO_UV, 0)
		var vr: int = rows[INDEX_VERTEX]
		var ur: int = rows.get(INDEX_UV, -1)
		p.vertex.resize(e.count)
		if ur >= 0:
			p.uv.resize(e.count)
		for k in e.count:
			p.vertex[k] = d[indices_at + vr + k] + vb
			if ur >= 0:
				p.uv[k] = d[indices_at + ur + k] + ub
	# Colours ("df") run one per corner, in the parts' order.
	if base.has(INFO_COLOUR):
		p.colour.resize(e.count)
		for k in e.count:
			p.colour[k] = base[INFO_COLOUR] + k
	if d.decode_u16(o) == PRIM_STRIP:
		_unstrip(p)
	return p


## Turns a strip part's corner lists into a triangle list: every three corners in a row
## a triangle, every other one turned back to wind like the first, the joins (a corner
## twice) left out.
static func _unstrip(p: Dictionary) -> void:
	var src: PackedInt32Array = p.vertex
	for key in ["vertex", "uv", "colour"]:
		var a: PackedInt32Array = p[key]
		if a.size() != src.size():
			continue
		var out := PackedInt32Array()
		for t in src.size() - 2:
			if src[t] == src[t + 1] or src[t + 1] == src[t + 2] or src[t] == src[t + 2]:
				continue
			if t % 2 == 0:
				out.append_array([a[t], a[t + 1], a[t + 2]])
			else:
				out.append_array([a[t + 1], a[t], a[t + 2]])
		p[key] = out
	p.count = p.vertex.size()


## The name of a track material's texture: an entry of the track's .fsh ("sn" names it),
## or "" when it has none.
func material_texture(index: int) -> String:
	for e in misc:
		if e.id == "mt" and e.index == index and e.length >= 44:
			return data.slice(e.offset + 40, e.offset + 44).get_string_from_ascii()
	return ""

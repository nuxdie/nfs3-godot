class_name Eagl
## Hot Pursuit 2's compiled models (.o): EA's EAGL geometry as 32-bit little-endian MIPS ELF
## relocatable objects. Everything lives in .data; the pointers in it are REL relocations
## against .data, so the value in place is already the .data offset it points at. Symbols
## name the pieces: __Model:::<name>, __geoprimdatabuffer_<n>_*, __RenderMethod:::*,
## __EAGL::TAR:::tar_<texture>_* (a texture reference).
##
## A geoprim's data buffer is a word, then a command stream of u32 words, each command's
## first word (op << 16 | its length in words, itself included), ended by a zero word:
##   op 0x4B  [?, stride, ?, -1, -1, vertex offset, vertex count, ...]
##   op 0x07  [primitive (2: triangle strip), -1, -1, index offset, index count]  (u16 indices)
## A vertex (stride 40): position f32 x3, a u32 (blend index), normal f32 x3, colour u32
## (ARGB), uv f32 x2.
## A model: +0x9C its part count, +0xA0 their names (pointers), and at +0xCC its draw list:
## a header entry (0xA0000000, 0, n), then per part (0xA0000001, 0, k) followed, when k is 2,
## by (0xA000FFFF, its render method + 0x30). The render method's +0x48 points at its texture
## reference.

var data := PackedByteArray()       # .data
var symbols := {}                   # name -> .data offset (defined symbols only)
var _by_offset := {}                # .data offset -> name
var error := ""


static func parse(bytes: PackedByteArray) -> Eagl:
	var e := Eagl.new()
	e._parse(bytes)
	return e


func _parse(d: PackedByteArray) -> void:
	if d.size() < 52 or d.decode_u32(0) != 0x464C457F:
		error = "not an ELF file"
		return
	var shoff := d.decode_u32(32)
	var shnum := d.decode_u16(48)
	var sections := []
	for i in shnum:
		var s := shoff + i * 40
		if s + 40 > d.size():
			error = "damaged ELF"
			return
		sections.append({"name": d.decode_u32(s), "type": d.decode_u32(s + 4),
			"offset": d.decode_u32(s + 16), "size": d.decode_u32(s + 20), "link": d.decode_u32(s + 24)})
	var shstr: Dictionary = sections[d.decode_u16(50)] if d.decode_u16(50) < sections.size() else {}
	var data_index := -1
	for i in sections.size():
		var s: Dictionary = sections[i]
		if not shstr.is_empty() and _str(d, shstr.offset + s.name) == ".data":
			data_index = i
			data = d.slice(s.offset, s.offset + s.size)
	if data_index < 0:
		error = "no .data"
		return
	for s: Dictionary in sections:
		if s.type != 2:   # SHT_SYMTAB
			continue
		var strtab: Dictionary = sections[s.link]
		for k in s.size / 16:
			var q: int = s.offset + k * 16
			if d.decode_u16(q + 14) != data_index:
				continue
			var name := _str(d, strtab.offset + d.decode_u32(q))
			var value := d.decode_u32(q + 4)
			symbols[name] = value
			_by_offset[value] = name


static func _str(d: PackedByteArray, off: int) -> String:
	var end := off
	while end < d.size() and d[end] != 0:
		end += 1
	return d.slice(off, end).get_string_from_utf8()


func u32(off: int) -> int:
	return data.decode_u32(off) if off >= 0 and off + 4 <= data.size() else 0


func c_string(off: int) -> String:
	return _str(data, off) if off >= 0 and off < data.size() else ""


## The name of the symbol at .data offset `off`, or "".
func symbol_at(off: int) -> String:
	return _by_offset.get(off, "")


## The parts of model `name` (its __Model:::<name> symbol) in its draw order:
## [{name, geoprim (its data buffer's offset, or -1 for a part with nothing to draw),
## texture (the TAR's texture name, "skin", "wl00"...)}].
func model_parts(name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not symbols.has("__Model:::" + name):
		return out
	var m: int = symbols["__Model:::" + name]
	var n := u32(m + 0x9C)
	var names := u32(m + 0xA0)
	var o := u32(m + 0xCC)
	if u32(o) != 0xA0000000 or n > 512:
		return out
	o += 12
	for i in n:
		if u32(o) != 0xA0000001:
			break
		var part := {"name": c_string(u32(names + i * 4)), "geoprim": -1, "texture": ""}
		var k := u32(o + 8)
		o += 12
		if k == 2 and u32(o) == 0xA000FFFF:
			var rm := u32(o + 4) - 0x30
			o += 8
			# The render method's first word points one word into its geoprim's data buffer.
			part.geoprim = u32(rm) - 4
			var tar := symbol_at(u32(rm + 0x48))
			if tar.begins_with("__EAGL::TAR:::tar_"):
				var t := tar.trim_prefix("__EAGL::TAR:::tar_")
				part.texture = t.substr(0, t.find("_")) if "_" in t else t
		out.append(part)
	return out


## A geoprim's triangles: {pos, normal, uv (PackedVector2Array), colour (PackedColorArray),
## indices (PackedInt32Array, a triangle list, the strips' degenerate triangles dropped)}, in
## the file's space; {} when its data buffer can't be read.
func geoprim(buffer: int) -> Dictionary:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var tris := PackedInt32Array()
	var o := buffer + 4
	var stride := 0
	var vbase := 0
	var guard := 0
	while guard < 256:
		guard += 1
		var w := u32(o)
		var op := w >> 16
		var n := w & 0xFFFF
		if n == 0 or n > 64:
			break
		if op == 0x4B and n >= 8:
			stride = u32(o + 8)
			var voff := u32(o + 24)
			var vcount := u32(o + 28)
			if stride < 40 or voff + vcount * stride > data.size():
				return {}
			vbase = pos.size()
			for k in vcount:
				var p := voff + k * stride
				pos.append(Vector3(data.decode_float(p), data.decode_float(p + 4), data.decode_float(p + 8)))
				nrm.append(Vector3(data.decode_float(p + 16), data.decode_float(p + 20), data.decode_float(p + 24)))
				var c := data.decode_u32(p + 28)
				col.append(Color8((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, (c >> 24) & 0xFF))
				uv.append(Vector2(data.decode_float(p + 32), data.decode_float(p + 36)))
		elif op == 0x07 and n >= 6 and stride > 0:
			var prim := u32(o + 4)
			var ioff := u32(o + 16)
			var icount := u32(o + 20)
			if ioff + icount * 2 > data.size():
				return {}
			var idx := PackedInt32Array()
			for k in icount:
				var v := data.decode_u16(ioff + k * 2)
				# 0xFFFF restarts the strip; anything else past the vertices is dropped with its triangles.
				idx.append(-1 if v == 0xFFFF or vbase + v >= pos.size() else vbase + v)
			if prim == 2:
				var start := 0
				for k in icount - 2:
					var a := idx[k]
					var b := idx[k + 1]
					var c := idx[k + 2]
					if a < 0:
						start = k + 1
						continue
					if b < 0 or c < 0 or a == b or b == c or a == c:
						continue
					if (k - start) % 2 == 0:
						tris.append_array([a, b, c])
					else:
						tris.append_array([b, a, c])
			else:
				for k in range(0, icount - 2, 3):
					if idx[k] >= 0 and idx[k + 1] >= 0 and idx[k + 2] >= 0:
						tris.append_array([idx[k], idx[k + 1], idx[k + 2]])
		o += n * 4
	return {"pos": pos, "normal": nrm, "uv": uv, "colour": col, "indices": tris}

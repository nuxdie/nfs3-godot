class_name Fsh
## Reader for EA "SHPI" shape archives (.fsh, or RefPack-compressed .qfs).
## Produces one Image per bitmap entry, in directory order, keyed by name as well.

var names: PackedStringArray = []
var images: Array[Image] = []
var by_name := {}

const BITMAP_CODES := [0x78, 0x7B, 0x7D, 0x7E, 0x7F, 0x6D]
const PALETTE_CODES := [0x22, 0x24, 0x29, 0x2A, 0x2D]


static func load_file(path: String) -> Fsh:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	return from_bytes(bytes)


static func from_bytes(bytes: PackedByteArray) -> Fsh:
	var data := Qfs.decompress(bytes)
	if data.size() < 16 or data.slice(0, 4).get_string_from_ascii() != "SHPI":
		return null
	var f := Fsh.new()
	f._parse(data)
	return f


func _parse(d: PackedByteArray) -> void:
	var count := d.decode_s32(8)
	var offsets: Array[int] = []
	var entry_names: Array[String] = []
	for i in count:
		entry_names.append(d.slice(16 + i * 8, 20 + i * 8).get_string_from_ascii())
		offsets.append(d.decode_s32(20 + i * 8))

	var global_pal := PackedColorArray()
	for i in count:
		if entry_names[i] == "!pal" and offsets[i] + 16 <= d.size():
			global_pal = _palette(d, offsets[i])

	for i in count:
		var off := offsets[i]
		if off + 16 > d.size():
			continue
		var code := d[off] & 0x7F
		if code not in BITMAP_CODES:
			continue
		var img := _bitmap(d, off, code, global_pal)
		if img == null:
			continue
		names.append(entry_names[i])
		images.append(img)
		by_name[entry_names[i]] = img


static func _next_attachment(d: PackedByteArray, off: int) -> int:
	return (d.decode_u32(off) >> 8) & 0xFFFFFF


func _palette(d: PackedByteArray, off: int) -> PackedColorArray:
	var code := d[off]
	var n := d.decode_u16(off + 4)
	var p := off + 16
	var pal := PackedColorArray()
	pal.resize(n)
	for i in n:
		match code:
			0x24:
				pal[i] = Color8(d[p + i * 3], d[p + i * 3 + 1], d[p + i * 3 + 2])
			0x22:
				pal[i] = Color8(d[p + i * 3] << 2, d[p + i * 3 + 1] << 2, d[p + i * 3 + 2] << 2)
			0x2D:
				pal[i] = _c1555(d.decode_u16(p + i * 2))
			0x29:
				pal[i] = _c565(d.decode_u16(p + i * 2))
			0x2A:
				var v := d.decode_u32(p + i * 4)
				pal[i] = Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, (v >> 24) & 0xFF)
	return pal


static func _c1555(v: int) -> Color:
	return Color8(((v >> 10) & 0x1F) << 3, ((v >> 5) & 0x1F) << 3, (v & 0x1F) << 3, 255 if (v & 0x8000) else 0)


static func _c565(v: int) -> Color:
	return Color8(((v >> 11) & 0x1F) << 3, ((v >> 5) & 0x3F) << 2, (v & 0x1F) << 3)


func _bitmap(d: PackedByteArray, off: int, code: int, global_pal: PackedColorArray) -> Image:
	var w := d.decode_u16(off + 4)
	var h := d.decode_u16(off + 6)
	if w == 0 or h == 0 or w > 4096 or h > 4096:
		return null
	var p := off + 16
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	var px := w * h
	match code:
		0x7B:
			var pal := global_pal
			var a := off
			while _next_attachment(d, a) > 0:
				a += _next_attachment(d, a)
				if a + 16 > d.size():
					break
				if d[a] in PALETTE_CODES:
					pal = _palette(d, a)
			if pal.is_empty():
				return null
			if p + px > d.size():
				return null
			for i in px:
				var c: Color = pal[d[p + i]] if d[p + i] < pal.size() else Color.BLACK
				rgba[i * 4] = c.r8
				rgba[i * 4 + 1] = c.g8
				rgba[i * 4 + 2] = c.b8
				rgba[i * 4 + 3] = c.a8
		0x7D:
			if p + px * 4 > d.size():
				return null
			for i in px:
				rgba[i * 4] = d[p + i * 4 + 2]
				rgba[i * 4 + 1] = d[p + i * 4 + 1]
				rgba[i * 4 + 2] = d[p + i * 4]
				rgba[i * 4 + 3] = d[p + i * 4 + 3]
		0x7F:
			if p + px * 3 > d.size():
				return null
			for i in px:
				rgba[i * 4] = d[p + i * 3 + 2]
				rgba[i * 4 + 1] = d[p + i * 3 + 1]
				rgba[i * 4 + 2] = d[p + i * 3]
				rgba[i * 4 + 3] = 255
		0x7E, 0x78, 0x6D:
			if p + px * 2 > d.size():
				return null
			for i in px:
				var v := d.decode_u16(p + i * 2)
				var r := 0
				var g := 0
				var b := 0
				var al := 255
				if code == 0x7E:
					r = ((v >> 10) & 0x1F) << 3
					g = ((v >> 5) & 0x1F) << 3
					b = (v & 0x1F) << 3
					al = 255 if (v & 0x8000) else 0
				elif code == 0x78:
					r = ((v >> 11) & 0x1F) << 3
					g = ((v >> 5) & 0x3F) << 2
					b = (v & 0x1F) << 3
				else:
					r = ((v >> 8) & 0x0F) * 17
					g = ((v >> 4) & 0x0F) * 17
					b = (v & 0x0F) * 17
					al = ((v >> 12) & 0x0F) * 17
				rgba[i * 4] = r
				rgba[i * 4 + 1] = g
				rgba[i * 4 + 2] = b
				rgba[i * 4 + 3] = al
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)

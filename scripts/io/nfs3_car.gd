class_name Nfs3Car
## Loads an NFS3 car (carmodel/<id>/car.viv): FCE mesh, car00.tga skin,
## carp.txt physics table and the display name from fedata.eng.

const HEADER_END := 0x1F04
const TRI_SIZE := 56
const SCALE := 1.0

var id := ""
var display_name := ""
var texture: Texture2D
var body_parts: Array[Dictionary] = []   # {name, mesh, center}
var wheels: Array[Dictionary] = []       # {name, mesh, center} front-left, front-right, rear-left, rear-right
var half_size := Vector3(0.9, 0.6, 2.2)
var colours: Array[Color] = []
var carp := {}                           # id -> PackedFloat32Array
var error := ""

const WHEEL_PREFIXES := ["left front", "right front", "left rear", "right rear"]


static func load_dir(dir: String) -> Nfs3Car:
	var c := Nfs3Car.new()
	c.id = dir.get_file()
	var viv := Viv.load_file(dir.path_join("car.viv"))
	if viv == null:
		c.error = "missing car.viv"
		return c
	c.display_name = read_name(viv.get_file("fedata.eng"), c.id)
	c.carp = parse_carp(viv.get_file("carp.txt").get_string_from_ascii())
	var tga := viv.get_file("car00.tga")
	if not tga.is_empty():
		var img := Image.new()
		if img.load_tga_from_buffer(tga) == OK:
			img.generate_mipmaps()
			c.texture = ImageTexture.create_from_image(img)
	var fce := viv.get_file("car.fce")
	if fce.is_empty():
		c.error = "missing car.fce"
		return c
	c._parse_fce(fce)
	return c


## Quick name lookup for menus, without building meshes.
static func peek_name(dir: String) -> String:
	var viv := Viv.load_file(dir.path_join("car.viv"))
	if viv == null:
		return ""
	return read_name(viv.get_file("fedata.eng"), dir.get_file())


static func read_name(fedata: PackedByteArray, fallback: String) -> String:
	if fedata.size() < 60:
		return fallback
	var strings: Array[String] = []
	for i in 3:
		var off := fedata.decode_u32(47 + i * 4)
		if off <= 0 or off >= fedata.size():
			return fallback
		var e := off
		while e < fedata.size() and fedata[e] != 0:
			e += 1
		strings.append(fedata.slice(off, e).get_string_from_ascii())
	var n := strings[2].strip_edges()
	if n.is_empty():
		n = (strings[0] + " " + strings[1]).strip_edges()
	return n if not n.is_empty() else fallback


static func parse_carp(text: String) -> Dictionary:
	var out := {}
	var lines := text.replace("\r", "").split("\n")
	var re := RegEx.create_from_string("\\((\\d+)\\)\\s*$")
	for i in range(lines.size() - 1):
		var m := re.search(lines[i])
		if m:
			var vals := PackedFloat32Array()
			for s in lines[i + 1].split(","):
				vals.append(s.to_float())
			out[int(m.get_string(1))] = vals
	return out


func carp_value(key: int, default := 0.0, index := 0) -> float:
	if carp.has(key) and carp[key].size() > index:
		return carp[key][index]
	return default


func _parse_fce(d: PackedByteArray) -> void:
	var vert_off := d.decode_u32(16)
	var norm_off := d.decode_u32(20)
	var tri_off := d.decode_u32(24)
	half_size = Vector3(d.decode_float(40), d.decode_float(44), d.decode_float(48)) * SCALE
	var n_parts := d.decode_u32(248)
	var n_pri := d.decode_u32(2044)
	for i in mini(n_pri, 16):
		var q := 2048 + i * 16
		colours.append(Color.from_hsv(d.decode_u32(q) / 255.0, d.decode_u32(q + 4) / 255.0, d.decode_u32(q + 8) / 255.0))
	for pi in n_parts:
		var pname := d.slice(3588 + pi * 64, 3588 + pi * 64 + 64).get_string_from_ascii().strip_edges().to_lower()
		var slot := -1
		for w in 4:
			if pname.begins_with(WHEEL_PREFIXES[w]):
				slot = w
		# Part 0 is always the high-detail body; other "medium/small/tiny" parts are LODs.
		if slot < 0 and pi != 0 and not pname.begins_with("high"):
			continue
		var center := _v(d, 252 + pi * 12)
		var first_v := d.decode_u32(1020 + pi * 4)
		var nv := d.decode_u32(1276 + pi * 4)
		var first_t := d.decode_u32(1532 + pi * 4)
		var nt := d.decode_u32(1788 + pi * 4)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ti in nt:
			var q := HEADER_END + tri_off + (first_t + ti) * TRI_SIZE
			# Mirroring X flips handedness; emit the triangle in reverse order to keep it front-facing.
			for k in [2, 1, 0]:
				var vi := d.decode_u32(q + 4 + k * 4)
				var vp := HEADER_END + vert_off + (first_v + vi) * 12
				var np := HEADER_END + norm_off + (first_v + vi) * 12
				st.set_normal(_v(d, np).normalized())
				st.set_uv(Vector2(d.decode_float(q + 32 + k * 4), 1.0 - d.decode_float(q + 44 + k * 4)))
				st.add_vertex(_v(d, vp))
		var part := {"name": pname, "mesh": st.commit(), "center": center}
		if slot >= 0:
			part.slot = slot
			wheels.append(part)
		else:
			body_parts.append(part)
	wheels.sort_custom(func(a, b): return a.slot < b.slot)


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)) * SCALE

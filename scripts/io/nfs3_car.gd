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


static func load_dir(dir: String) -> Nfs3Car:
	var c := Nfs3Car.new()
	c.id = dir.get_file()
	var viv := Viv.load_file(DataPath.find_ci(dir, "car.viv"))
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
	var viv := Viv.load_file(DataPath.find_ci(dir, "car.viv"))
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
	if d.size() < HEADER_END:
		error = "damaged car.fce"
		return
	var vert_off := d.decode_u32(16)
	var norm_off := d.decode_u32(20)
	var tri_off := d.decode_u32(24)
	half_size = Vector3(d.decode_float(40), d.decode_float(44), d.decode_float(48)) * SCALE
	var n_parts := d.decode_u32(248)
	if n_parts < 1 or n_parts > 64:
		error = "damaged car.fce"
		return
	var n_pri := d.decode_u32(2044)
	for i in mini(n_pri, 16):
		var q := 2048 + i * 16
		colours.append(Color.from_hsv(d.decode_u32(q) / 255.0, d.decode_u32(q + 4) / 255.0, d.decode_u32(q + 8) / 255.0))
	# Parts come in LOD groups: body, then its four wheels, then the next LOD down. Part 0 is the
	# most detailed body ("high body", or "medium body" on traffic), so its wheels are parts 1-4.
	# Wheel names in the data are unreliable (left/right swapped, a "left front" at the back), so
	# slots come from where the wheel sits. Headlight glass is a separate part at the end.
	var wheel_ids: Array[int] = []
	for pi in range(1, mini(5, n_parts)):
		if _part_name(d, pi).contains("wheel"):
			wheel_ids.append(pi)
	var slots: Array[int] = []
	for pi in wheel_ids:
		var c := _v(d, 252 + pi * 12)
		slots.append((0 if c.z > 0.0 else 2) + (0 if c.x > 0.0 else 1))
	var slots_ok := wheel_ids.size() == 4
	for k in 4:
		slots_ok = slots_ok and k in slots
	for pi in n_parts:
		var pname := _part_name(d, pi)
		var wi := wheel_ids.find(pi)
		if pi != 0 and wi < 0 and not pname.contains("headlight"):
			continue
		var center := _v(d, 252 + pi * 12)
		var first_v := d.decode_u32(1020 + pi * 4)
		var nv := d.decode_u32(1276 + pi * 4)
		var first_t := d.decode_u32(1532 + pi * 4)
		var nt := d.decode_u32(1788 + pi * 4)
		if HEADER_END + tri_off + (first_t + nt) * TRI_SIZE > d.size() \
				or HEADER_END + maxi(vert_off, norm_off) + (first_v + nv) * 12 > d.size():
			error = "damaged car.fce"
			return
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ti in nt:
			var q := HEADER_END + tri_off + (first_t + ti) * TRI_SIZE
			if d.decode_u32(q + 4) >= nv or d.decode_u32(q + 8) >= nv or d.decode_u32(q + 12) >= nv:
				continue
			# Mirroring X flips handedness; emit the triangle in reverse order to keep it front-facing.
			for k in [2, 1, 0]:
				var vi := d.decode_u32(q + 4 + k * 4)
				var vp := HEADER_END + vert_off + (first_v + vi) * 12
				var np := HEADER_END + norm_off + (first_v + vi) * 12
				st.set_normal(_v(d, np).normalized())
				st.set_uv(Vector2(d.decode_float(q + 32 + k * 4), 1.0 - d.decode_float(q + 44 + k * 4)))
				st.add_vertex(_v(d, vp))
		var part := {"name": pname, "mesh": st.commit(), "center": center}
		if wi >= 0 and slots_ok:
			part.slot = slots[wi]
			wheels.append(part)
		else:
			# Without a clean set of four wheels, draw them as part of the body.
			body_parts.append(part)
	wheels.sort_custom(func(a, b): return a.slot < b.slot)


static func _part_name(d: PackedByteArray, pi: int) -> String:
	return d.slice(3588 + pi * 64, 3588 + pi * 64 + 64).get_string_from_ascii().strip_edges().to_lower()


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)) * SCALE

class_name Nfs3Car
## Loads an NFS3 car (carmodel/<id>/car.viv): FCE mesh, car00.tga skin,
## carp.txt physics table and the display name from fedata.eng. High Stakes cars
## (cars/<id>/car.viv) hold the same files, with its FCE4 mesh and fedata layouts.

const HEADER_END := 0x1F04
const TRI_SIZE := 56
## FCE4 (High Stakes): the same header tables 36 bytes further on, a bigger header
## overall, and colours as four bytes rather than four ints.
const FCE4_SHIFT := 36
const FCE4_HEADER_END := 0x2038
## High Stakes parts drawn with the car: the most detailed body, its mirrors and T-top
## roof panel. The driver and cockpit (hidden behind the opaque glass here), the lower LODs
## and the brake discs are left out; the pop-up lamps (OL) and wheels are handled apart.
const FCE4_BODY_PARTS := [":hb", ":olm", ":orm", ":ot"]
const SCALE := 1.0

var id := ""
var display_name := ""
var texture: Texture2D
var body_parts: Array[Dictionary] = []   # {name, mesh, center}
var wheels: Array[Dictionary] = []       # {name, mesh, center} front-left, front-right, rear-left, rear-right
var popup_lights: Array[Dictionary] = [] # {name, mesh, center}: pop-up headlamps, raised only while the lights are on
var half_size := Vector3(0.9, 0.6, 2.2)
var colours: Array[Color] = []
var lights: Array[Dictionary] = []       # {kind, pos}: kind is the dummy's first letter (H head, T tail, S siren)
var carp := {}                           # id -> PackedFloat32Array
var high_stakes := false                 # a High Stakes (FCE4) car
var error := ""


static func load_dir(dir: String) -> Nfs3Car:
	var c := Nfs3Car.new()
	c.id = dir.get_file()
	var viv := Viv.load_file(DataPath.find_ci(dir, "car.viv"))
	if viv == null:
		c.error = "missing car.viv"
		return c
	var fce := viv.get_file("car.fce")
	c.high_stakes = is_fce4(fce)
	c.display_name = read_name(viv.get_file("fedata.eng"), c.id, c.high_stakes)
	c.carp = parse_carp(viv.get_file("carp.txt").get_string_from_ascii())
	if c.high_stakes:
		c._convert_hs_carp()
	var tga := viv.get_file("car00.tga")
	if not tga.is_empty():
		var img := Image.new()
		if img.load_tga_from_buffer(tga) == OK:
			# The game reads the pixel rows in file order and ignores the TGA "top-down" flag, so
			# undo the flip Godot applies for those files or the UVs land on the wrong rows.
			# High Stakes honours the flag (its skins come both ways up).
			if not c.high_stakes and tga.size() > 17 and tga[17] & 0x20:
				img.flip_y()
			if c.high_stakes:
				_hs_paint_mask(img, fce)
			_bleed_cutout(img)
			img.generate_mipmaps()
			c.texture = ImageTexture.create_from_image(img)
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
	return read_name(viv.get_file("fedata.eng"), dir.get_file(), is_fce4(viv.get_file("car.fce")))


## Name and carp.txt only (no mesh or skin): what a menu needs to list and rate the car.
static func peek_spec(dir: String) -> Nfs3Car:
	var c := Nfs3Car.new()
	c.id = dir.get_file()
	var viv := Viv.load_file(DataPath.find_ci(dir, "car.viv"))
	if viv == null:
		c.error = "missing car.viv"
		return c
	c.high_stakes = is_fce4(viv.get_file("car.fce"))
	c.display_name = read_name(viv.get_file("fedata.eng"), c.id, c.high_stakes)
	c.carp = parse_carp(viv.get_file("carp.txt").get_string_from_ascii())
	if c.high_stakes:
		c._convert_hs_carp()
	return c


## FCE4 files start with 0x00101014; FCE3 ones with anything, 0x00101013 included.
static func is_fce4(fce: PackedByteArray) -> bool:
	return fce.size() >= 4 and fce.decode_u32(0) == 0x101014


static func read_name(fedata: PackedByteArray, fallback: String, high_stakes := false) -> String:
	if high_stakes:
		# The full name ("Chevrolet Corvette") is at the offset stored at 0x3C8.
		if fedata.size() < 0x3CC:
			return fallback
		var n := _c_string(fedata, fedata.decode_u32(0x3C8)).strip_edges()
		return n if not n.is_empty() else fallback
	if fedata.size() < 60:
		return fallback
	var strings: Array[String] = []
	for i in 3:
		var off := fedata.decode_u32(47 + i * 4)
		if off <= 0 or off >= fedata.size():
			return fallback
		strings.append(_c_string(fedata, off))
	var n := strings[2].strip_edges()
	if n.is_empty():
		n = (strings[0] + " " + strings[1]).strip_edges()
	return n if not n.is_empty() else fallback


## A zero-terminated Latin-1 string ("La Niña"), or "" when `off` is out of range.
static func _c_string(d: PackedByteArray, off: int) -> String:
	var s := ""
	if off <= 0:
		return s
	while off < d.size() and d[off] != 0:
		s += char(d[off])
		off += 1
	return s


## High Stakes lists the torque curve [10] every 500 rpm (21 values) where NFS3 has one
## every 256 rpm (41 values): resample it to NFS3's steps, which Car reads.
func _convert_hs_carp() -> void:
	var tq: PackedFloat32Array = carp.get(10, PackedFloat32Array())
	if tq.size() < 2:
		return
	var out := PackedFloat32Array()
	for i in 41:
		var f := minf(i * 256.0 / 500.0, tq.size() - 1.0)
		var k := mini(int(f), tq.size() - 2)
		out.append(lerpf(tq[k], tq[k + 1], f - k))
	carp[10] = out


static func parse_carp(text: String) -> Dictionary:
	var out := {}
	var lines := text.replace("\r", "").split("\n")
	var re := RegEx.create_from_string("\\((\\d+)\\)\\s*$")
	for i in range(lines.size() - 1):
		var m := re.search(lines[i])
		if m:
			var vals := PackedFloat32Array()
			# Some files end each row with a comma: no empty value after it.
			for s in lines[i + 1].split(",", false):
				vals.append(s.to_float())
			out[int(m.get_string(1))] = vals
	return out


func carp_value(key: int, default := 0.0, index := 0) -> float:
	if carp.has(key) and carp[key].size() > index:
		return carp[key][index]
	return default


func _parse_fce(d: PackedByteArray) -> void:
	# FCE4 has one more count in front of the table offsets, and 32 bytes more of offsets
	# after them: from the model's size to the part names everything sits 36 bytes further on.
	var fce4 := is_fce4(d)
	var o := FCE4_SHIFT if fce4 else 0
	var header_end := FCE4_HEADER_END if fce4 else HEADER_END
	if d.size() < header_end:
		error = "damaged car.fce"
		return
	var t := 4 if fce4 else 0
	var vert_off := d.decode_u32(t + 16)
	var norm_off := d.decode_u32(t + 20)
	var tri_off := d.decode_u32(t + 24)
	half_size = Vector3(d.decode_float(o + 40), d.decode_float(o + 44), d.decode_float(o + 48)) * SCALE
	var n_parts := d.decode_u32(o + 248)
	if n_parts < 1 or n_parts > 64:
		error = "damaged car.fce"
		return
	# Light "dummies": positions named by type, e.g. HFLO (headlight), TRLN (taillight), SMLN (siren).
	# High Stakes also marks the licence plates, as ":LICENSE": not lamps.
	for i in mini(d.decode_u32(o + 52), 16):
		var dname := d.slice(o + 2564 + i * 64, o + 2628 + i * 64).get_string_from_ascii().strip_edges().to_upper()
		if not dname.is_empty() and not dname.begins_with(":"):
			lights.append({"kind": dname[0], "pos": _v(d, o + 56 + i * 12)})
	var n_pri := d.decode_u32(o + 2044)
	for i in mini(n_pri, 16):
		# Hue/saturation/brightness (a 4th value, usually ~128, is ignored). The paint areas of
		# the skin are mid-grey, so the colour is applied at double strength to come out true.
		var hsb := Vector3(d[o + 2048 + i * 4], d[o + 2049 + i * 4], d[o + 2050 + i * 4]) if fce4 \
			else Vector3(d.decode_u32(2048 + i * 16), d.decode_u32(2052 + i * 16), d.decode_u32(2056 + i * 16))
		var col := Color.from_hsv(hsb.x / 255.0, hsb.y / 255.0, hsb.z / 255.0)
		col = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0)
		colours.append(col)
	# Parts come in LOD groups: body, then its four wheels, then the next LOD down. Part 0 is the
	# most detailed body ("high body", or "medium body" on traffic), so its wheels are parts 1-4.
	# Wheel names in the data are unreliable (left/right swapped, a "left front" at the back), so
	# slots come from where the wheel sits. Pop-up headlamps, in the raised position, are a
	# separate part at the end.
	# High Stakes names its parts instead: ":HB" high body, ":HLFW" its left front wheel (and
	# ":HLMW" a middle one, on the six-wheelers), ":OL" the pop-up lamps, ":M..", ":L..",
	# ":T.." the lower LODs. Its middle wheels are drawn as part of the body.
	var body_ids: Array[int] = [0]
	var wheel_ids: Array[int] = []
	var popup_ids: Array[int] = []
	if fce4:
		body_ids.clear()
		for pi in n_parts:
			var pname := _part_name(d, pi, o)
			if pname in FCE4_BODY_PARTS or (pname.length() == 5 and pname.begins_with(":h") and pname.ends_with("mw")):
				body_ids.append(pi)
			elif pname.length() == 5 and pname.begins_with(":h") and pname.ends_with("w"):
				wheel_ids.append(pi)
			elif pname == ":ol":
				popup_ids.append(pi)
		if body_ids.is_empty():
			body_ids.append(0)
	else:
		for pi in range(1, mini(5, n_parts)):
			if _part_name(d, pi).contains("wheel"):
				wheel_ids.append(pi)
		for pi in n_parts:
			if pi != 0 and wheel_ids.find(pi) < 0 and _part_name(d, pi).contains("headlight"):
				popup_ids.append(pi)
	var slots: Array[int] = []
	for pi in wheel_ids:
		var c := _v(d, o + 252 + pi * 12)
		slots.append((0 if c.z > 0.0 else 2) + (0 if c.x > 0.0 else 1))
	var slots_ok := wheel_ids.size() == 4
	for k in 4:
		slots_ok = slots_ok and k in slots
	# The body whose underside gets tucked in (below): the first, or High Stakes' ":HB".
	var main_body := body_ids[0]
	for pi in body_ids:
		if _part_name(d, pi, o) == ":hb":
			main_body = pi
	for pi in n_parts:
		var pname := _part_name(d, pi, o)
		var wi := wheel_ids.find(pi)
		if wi < 0 and not pi in body_ids and not pi in popup_ids:
			continue
		var center := _v(d, o + 252 + pi * 12)
		var first_v := d.decode_u32(o + 1020 + pi * 4)
		var nv := d.decode_u32(o + 1276 + pi * 4)
		var first_t := d.decode_u32(o + 1532 + pi * 4)
		var nt := d.decode_u32(o + 1788 + pi * 4)
		if header_end + tri_off + (first_t + nt) * TRI_SIZE > d.size() \
				or header_end + maxi(vert_off, norm_off) + (first_v + nv) * 12 > d.size():
			error = "damaged car.fce"
			return
		# The underside is a few big, near-level quads spanning the full width; the body above
		# is rounded at the corners, so their corners poke out below the bumpers as dark,
		# torn-looking slivers. Pull them in towards their centre, tucked under the body.
		var floor_tris := {}
		var floor_box := AABB()
		if pi == main_body:
			var low := INF
			for vi in nv:
				low = minf(low, _v(d, header_end + vert_off + (first_v + vi) * 12).y)
			for ti in nt:
				var q := header_end + tri_off + (first_t + ti) * TRI_SIZE
				var p: Array[Vector3] = []
				for k in 3:
					var vi := mini(d.decode_u32(q + 4 + k * 4), nv - 1)
					p.append(_v(d, header_end + vert_off + (first_v + vi) * 12))
				var n := (p[1] - p[0]).cross(p[2] - p[0])
				var level := absf(n.y) > 0.97 * n.length()
				var bottom := maxf(p[0].y, maxf(p[1].y, p[2].y)) < low + 0.3
				if level and bottom and n.length() * 0.5 > 0.5:
					for v in p:
						floor_box = AABB(v, Vector3.ZERO) if floor_tris.is_empty() else floor_box.expand(v)
					floor_tris[ti] = true
		var floor_mid := floor_box.get_center()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ti in nt:
			var q := header_end + tri_off + (first_t + ti) * TRI_SIZE
			if d.decode_u32(q + 4) >= nv or d.decode_u32(q + 8) >= nv or d.decode_u32(q + 12) >= nv:
				continue
			# Mirroring X flips handedness; emit the triangle in reverse order to keep it front-facing.
			for k in [2, 1, 0]:
				var vi := d.decode_u32(q + 4 + k * 4)
				var vp := header_end + vert_off + (first_v + vi) * 12
				var np := header_end + norm_off + (first_v + vi) * 12
				st.set_normal(_v(d, np).normalized())
				# FCE4's v runs the other way (the skin's rows are read in file order either way).
				var tv := d.decode_float(q + 44 + k * 4)
				st.set_uv(Vector2(d.decode_float(q + 32 + k * 4), tv if fce4 else 1.0 - tv))
				var pos := _v(d, vp)
				if floor_tris.has(ti):
					pos = floor_mid + (pos - floor_mid) * Vector3(0.84, 1.0, 0.92)
				st.add_vertex(pos)
		var part := {"name": pname, "mesh": st.commit(), "center": center}
		if wi >= 0 and slots_ok:
			part.slot = slots[wi]
			wheels.append(part)
		elif pi in popup_ids:
			popup_lights.append(part)
		else:
			# Without a clean set of four wheels, draw them as part of the body.
			body_parts.append(part)
	wheels.sort_custom(func(a, b): return a.slot < b.slot)


## High Stakes skins mark the paint with alpha ~224 and the interior (seats, dash) with
## ~160, both grey, each tinted by its own colour table. Bring them to NFS3's convention,
## which car.gdshader reads: the paint gets NFS3's paint alpha, the interior takes the
## first interior colour and turns opaque.
static func _hs_paint_mask(img: Image, fce: PackedByteArray) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var interior := Color(0.5, 0.5, 0.5)
	if fce.size() >= FCE4_HEADER_END and fce.decode_u32(FCE4_SHIFT + 2044) > 0:
		var q := FCE4_SHIFT + 2048 + 64
		interior = Color.from_hsv(fce[q] / 255.0, fce[q + 1] / 255.0, fce[q + 2] / 255.0)
	var px := img.get_data()
	for i in range(0, px.size(), 4):
		var a := px[i + 3]
		if a >= 250 or a < 100:
			continue
		if a >= 200:
			px[i + 3] = 117
		else:
			for k in 3:
				px[i + k] = mini(int(px[i + k] * interior[k] * 2.0), 255)
			px[i + 3] = 255
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)


## Cut-out texels hold a key colour (often pure blue) that texture filtering smears onto
## the visible edges. Give them the colour of an opaque neighbour instead (alpha stays 0).
static func _bleed_cutout(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var px := img.get_data()
	var alpha := PackedByteArray()
	alpha.resize(w * h)
	var todo := PackedInt32Array()
	for i in w * h:
		alpha[i] = px[i * 4 + 3]
		if alpha[i] < 20:
			todo.append(i)
			px[i * 4 + 3] = 0
	px = _defringe(px, w, h)
	# Ring by ring outwards from the visible texels until every cut-out texel has a colour:
	# the small mip levels average whole blocks, so any key colour left over shows at the edges.
	while not todo.is_empty():
		var filled := PackedInt32Array()
		var left := PackedInt32Array()
		for i in todo:
			var x := i % w
			var src := -1
			if x > 0 and px[(i - 1) * 4 + 3] != 0:
				src = i - 1
			elif x < w - 1 and px[(i + 1) * 4 + 3] != 0:
				src = i + 1
			elif i >= w and px[(i - w) * 4 + 3] != 0:
				src = i - w
			elif i + w < w * h and px[(i + w) * 4 + 3] != 0:
				src = i + w
			if src < 0:
				left.append(i)
			else:
				filled.append(i)
				filled.append(src)
		for k in range(0, filled.size(), 2):
			var o := filled[k] * 4
			var so := filled[k + 1] * 4
			px[o] = px[so]
			px[o + 1] = px[so + 1]
			px[o + 2] = px[so + 2]
		# Mark this ring as a source for the next one only after it is complete.
		for k in range(0, filled.size(), 2):
			px[filled[k] * 4 + 3] = 1
		if filled.is_empty():
			break
		todo = left
	for i in w * h:
		px[i * 4 + 3] = alpha[i]
	img.set_data(w, h, false, Image.FORMAT_RGBA8, px)


## Some skins were pieced together over a green backdrop and kept thin seams of it: green
## texels along the cut-out edge and between panels (round the windows and bumpers of
## traffic car 0001, say), which show as green specks on the bodywork. Give such a texel the
## colour of its neighbours, unless enough of those are green too (green paint keeps its
## edges). `px` is RGBA8 with cut-out texels at alpha 0.
static func _defringe(px: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var candidates := PackedInt32Array()
	for i in w * h:
		var o := i * 4
		if px[o + 3] != 0 and px[o + 1] > maxi(px[o], px[o + 2]) + 30:
			candidates.append(i)
	# Two passes: the seams can be two texels wide.
	for pass_i in 2:
		var fixes := {}
		for i in candidates:
			var o := i * 4
			if not _greenish(px, o):
				continue
			var x := i % w
			var y := i / w
			var sum := Vector3.ZERO
			var n := 0
			var green := 0
			var green_around := 0
			for dy in range(-4, 5):
				# Inside a green panel: no need to look further.
				if green_around >= 24:
					break
				for dx in range(-4, 5):
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var q := (yy * w + xx) * 4
					if px[q + 3] == 0:
						continue
					var near := absi(dx) <= 2 and absi(dy) <= 2
					# Dark green paint is green too, if not as vividly as a seam.
					if _greenish(px, q, 1.25, 8):
						green_around += 1
						green += int(near)
					elif near:
						sum += Vector3(px[q], px[q + 1], px[q + 2])
						n += 1
			# A 1-2 texel seam is outnumbered by far; a green panel's straight edge is not,
			# nor is its thin trim (window frames) with the rest of the panel close by.
			if n > green + 4 and green_around < 24:
				fixes[o] = sum / n
		for o: int in fixes:
			var c: Vector3 = fixes[o]
			px[o] = int(c.x)
			px[o + 1] = int(c.y)
			px[o + 2] = int(c.z)
		if fixes.is_empty():
			break
	return px


static func _greenish(px: PackedByteArray, o: int, ratio := 1.0, margin := 30) -> bool:
	var other := maxi(px[o], px[o + 2])
	return px[o + 1] > maxi(int(other * ratio), other + margin)


static func _part_name(d: PackedByteArray, pi: int, o := 0) -> String:
	var at := o + 3588 + pi * 64
	var name := d.slice(at, at + 64)
	var end := name.find(0)
	return (name if end < 0 else name.slice(0, end)).get_string_from_ascii().strip_edges().to_lower()


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)) * SCALE

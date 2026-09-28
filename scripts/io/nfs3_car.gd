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
var popup_lights: Array[Dictionary] = [] # {name, mesh, center}: pop-up headlamps, raised only while the lights are on
var half_size := Vector3(0.9, 0.6, 2.2)
var colours: Array[Color] = []
var lights: Array[Dictionary] = []       # {kind, pos}: kind is the dummy's first letter (H head, T tail, S siren)
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
			# The game reads the pixel rows in file order and ignores the TGA "top-down" flag, so
			# undo the flip Godot applies for those files or the UVs land on the wrong rows.
			if tga.size() > 17 and tga[17] & 0x20:
				img.flip_y()
			_bleed_cutout(img)
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
	# Light "dummies": positions named by type, e.g. HFLO (headlight), TRLN (taillight), SMLN (siren).
	for i in mini(d.decode_u32(52), 16):
		var dname := d.slice(2564 + i * 64, 2628 + i * 64).get_string_from_ascii().strip_edges().to_upper()
		if not dname.is_empty():
			lights.append({"kind": dname[0], "pos": _v(d, 56 + i * 12)})
	var n_pri := d.decode_u32(2044)
	for i in mini(n_pri, 16):
		var q := 2048 + i * 16
		# Hue/saturation/brightness (a 4th byte, usually ~128, is ignored). The paint areas of
		# the skin are mid-grey, so the colour is applied at double strength to come out true.
		var col := Color.from_hsv(d.decode_u32(q) / 255.0, d.decode_u32(q + 4) / 255.0, d.decode_u32(q + 8) / 255.0)
		col = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0)
		colours.append(col)
	# Parts come in LOD groups: body, then its four wheels, then the next LOD down. Part 0 is the
	# most detailed body ("high body", or "medium body" on traffic), so its wheels are parts 1-4.
	# Wheel names in the data are unreliable (left/right swapped, a "left front" at the back), so
	# slots come from where the wheel sits. Pop-up headlamps, in the raised position, are a
	# separate part at the end.
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
		# The underside is a few big, near-level quads spanning the full width; the body above
		# is rounded at the corners, so their corners poke out below the bumpers as dark,
		# torn-looking slivers. Pull them in towards their centre, tucked under the body.
		var floor_tris := {}
		var floor_box := AABB()
		if pi == 0:
			var low := INF
			for vi in nv:
				low = minf(low, _v(d, HEADER_END + vert_off + (first_v + vi) * 12).y)
			for ti in nt:
				var q := HEADER_END + tri_off + (first_t + ti) * TRI_SIZE
				var p: Array[Vector3] = []
				for k in 3:
					var vi := mini(d.decode_u32(q + 4 + k * 4), nv - 1)
					p.append(_v(d, HEADER_END + vert_off + (first_v + vi) * 12))
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
				var pos := _v(d, vp)
				if floor_tris.has(ti):
					pos = floor_mid + (pos - floor_mid) * Vector3(0.84, 1.0, 0.92)
				st.add_vertex(pos)
		var part := {"name": pname, "mesh": st.commit(), "center": center}
		if wi >= 0 and slots_ok:
			part.slot = slots[wi]
			wheels.append(part)
		elif pname.contains("headlight"):
			popup_lights.append(part)
		else:
			# Without a clean set of four wheels, draw them as part of the body.
			body_parts.append(part)
	wheels.sort_custom(func(a, b): return a.slot < b.slot)


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


static func _part_name(d: PackedByteArray, pi: int) -> String:
	return d.slice(3588 + pi * 64, 3588 + pi * 64 + 64).get_string_from_ascii().strip_edges().to_lower()


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8)) * SCALE

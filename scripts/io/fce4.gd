class_name Fce4
## Reader for High Stakes' FCE4 models other than the car bodies Nfs3Car builds: the
## dashboard (dash.fce), the officer who walks up when you're busted (cop.fce) and the
## helicopter (hel.fce). Coordinates are mirrored in X like Nfs3Car's.

const HEADER_END := 0x2038
const TRI_SIZE := 56

var parts: Array[Dictionary] = []     # {name, center, first_v, nv, first_t, nt}
var dummies: Array[Dictionary] = []   # {name, pos}
var half_size := Vector3.ZERO
var _d := PackedByteArray()
var _vert_off := 0
var _norm_off := 0
var _tri_off := 0


static func parse(d: PackedByteArray) -> Fce4:
	if not Nfs3Car.is_fce4(d) or d.size() < HEADER_END:
		return null
	var f := Fce4.new()
	f._d = d
	f._vert_off = d.decode_u32(20)
	f._norm_off = d.decode_u32(24)
	f._tri_off = d.decode_u32(28)
	f.half_size = Vector3(d.decode_float(76), d.decode_float(80), d.decode_float(84))
	for i in mini(d.decode_u32(88), 16):
		var dname := d.slice(2600 + i * 64, 2664 + i * 64).get_string_from_ascii().strip_edges()
		f.dummies.append({"name": dname, "pos": _v(d, 92 + i * 12)})
	var n_parts := d.decode_u32(284)
	if n_parts > 64:
		return null
	for pi in n_parts:
		var p := {"name": Nfs3Car._part_name(d, pi, Nfs3Car.FCE4_SHIFT), "center": _v(d, 288 + pi * 12),
			"first_v": d.decode_u32(1056 + pi * 4), "nv": d.decode_u32(1312 + pi * 4),
			"first_t": d.decode_u32(1568 + pi * 4), "nt": d.decode_u32(1824 + pi * 4)}
		if HEADER_END + f._tri_off + (p.first_t + p.nt) * TRI_SIZE > d.size() \
				or HEADER_END + maxi(f._vert_off, f._norm_off) + (p.first_v + p.nv) * 12 > d.size():
			return null
		f.parts.append(p)
	return f


## The part's mesh, vertices relative to its centre, with one surface per texture page in
## `materials` (index = page; triangles on pages past the end use the last one), or a single
## surface without materials when `materials` is empty.
func mesh(part: Dictionary, materials: Array = []) -> ArrayMesh:
	var d := _d
	var by_page := {}
	for ti in part.nt:
		var q: int = HEADER_END + _tri_off + (part.first_t + ti) * TRI_SIZE
		var page := 0 if materials.is_empty() else mini(d.decode_u32(q), materials.size() - 1)
		if not by_page.has(page):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_page[page] = st
		var st: SurfaceTool = by_page[page]
		if d.decode_u32(q + 4) >= part.nv or d.decode_u32(q + 8) >= part.nv or d.decode_u32(q + 12) >= part.nv:
			continue
		for k in [2, 1, 0]:
			var vi: int = part.first_v + d.decode_u32(q + 4 + k * 4)
			st.set_normal(_v(d, HEADER_END + _norm_off + vi * 12).normalized())
			st.set_uv(Vector2(d.decode_float(q + 32 + k * 4), d.decode_float(q + 44 + k * 4)))
			st.add_vertex(_v(d, HEADER_END + _vert_off + vi * 12))
	var m := ArrayMesh.new()
	var pages := by_page.keys()
	pages.sort()
	for page in pages:
		(by_page[page] as SurfaceTool).commit(m)
		if not materials.is_empty():
			m.surface_set_material(m.get_surface_count() - 1, materials[page])
	return m


## High Stakes' police helicopter (cars/traffic/choppers/NNNN/car.viv: hel.fce, hel00.tga):
## {texture, body, main (rotor), tail (rotor)} with each part {mesh, center}, and its lamp
## dummies {name, pos} (S.. flashing, H.. the searchlight). {} when missing.
static func load_helicopter(dir: String) -> Dictionary:
	var viv := Viv.load_file(DataPath.find_ci(dir, "car.viv"))
	if viv == null:
		return {}
	var f := parse(viv.get_file("hel.fce"))
	if f == null:
		return {}
	var out := {"texture": Nfs3Car.load_skin(viv.get_file("hel00.tga"), true, PackedByteArray()),
		"lights": f.dummies}
	# "main" and "tail" are the rotors; ":LB", ":Lmain", ":Ltail" the low-detail copies.
	for key in ["body", "main", "tail"]:
		for p in f.parts:
			if p.name == key:
				out[key] = {"mesh": f.mesh(p), "center": p.center}
	return out if out.has("body") else {}


## A GameArt model (cone.fce with cone.art, ...): the first part whose name has `part`
## in it (or the first), textured from its .art pages, standing on its lowest point at
## the origin. null when missing.
static func load_prop(dir: String, name: String, part := "") -> ArrayMesh:
	var f := parse(FileAccess.get_file_as_bytes(DataPath.find_ci(dir, name + ".fce")))
	if f == null or f.parts.is_empty():
		return null
	var p: Dictionary = f.parts[0]
	if part != "" and not f.find(part).is_empty():
		p = f.find(part)
	var m := f.mesh(p, art_materials(FileAccess.get_file_as_bytes(DataPath.find_ci(dir, name + ".art"))))
	var lowest := INF
	for v in m.get_faces():
		lowest = minf(lowest, v.y)
	return Nfs3Car._translated(m, Vector3(0, -lowest, 0))


## One material per texture page of an .art file: cut out where the texel is clear.
static func art_materials(art: PackedByteArray) -> Array:
	var mats := []
	for img in art_images(art):
		Nfs3Car._bleed_cutout(img)
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		mats.append(m)
	return mats


func find(name_part: String) -> Dictionary:
	for p in parts:
		if (p.name as String).contains(name_part):
			return p
	return {}


## The images of a cop.art file (the officer's texture pages): each a little-endian width
## and height, then that many BGRA texels, top row first.
static func art_images(d: PackedByteArray) -> Array[Image]:
	var out: Array[Image] = []
	var at := 0
	while at + 8 <= d.size():
		var w := d.decode_u32(at)
		var h := d.decode_u32(at + 4)
		if w == 0 or h == 0 or w > 1024 or h > 1024 or at + 8 + w * h * 4 > d.size():
			break
		var px := d.slice(at + 8, at + 8 + w * h * 4)
		for i in range(0, px.size(), 4):
			var b := px[i]
			px[i] = px[i + 2]
			px[i + 2] = b
		out.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px))
		at += 8 + w * h * 4
	return out


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))

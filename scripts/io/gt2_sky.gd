class_name Gt2Sky
## A Gran Turismo 2 course's sky (bgsobj/<name>.bso, its textures in the .bsp, as a course's
## .trp): a dome round the camera, drawn behind everything (the backdrop hills too).
##
## The .bso: "BG", at 0xC its vertex count, at 0x10 its polygon counts by kind (u16 each: flat
## triangles, quads; gouraud triangles, quads; textured flat triangles, quads; gouraud), from
## 0x20 the vertices (s16 x, height, z, 0; a dome 4096 across, mirrored in z as the course's
## objects), then the polygons in that order: two u32 of 12-bit vertex indices (a | b << 12,
## c | d << 12), then the PS1 GPU packet that draws it twice (one per frame buffer): a tag
## (its length in words in the top byte), colour and code, then per corner its screen place
## (filled in when drawn), colour (gouraud) and UVs (textured: the first with the palette, the
## second with the page).

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, %s;
uniform sampler2DArray textures : source_color, filter_linear, repeat_disable;
uniform float alpha = 1.0;
uniform float depth = 1.2e-7;
void vertex() {
	// Round the camera, wherever it is, and as far off as can be: behind everything drawn,
	// the backdrop too (track.gdshader's far_away, which stands just in front of this), yet
	// in front of the cleared depth even in a 24-bit depth buffer. Its faces are painted in
	// their packets' order, as the PS1 did, over each other: one surface, in that order.
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + VERTEX, 1.0));
	POSITION.z = POSITION.w * depth;
}
void fragment() {
	// UV2.x: the image; UV2.y 1 on a textured face, its tint 128 as it is (stored /255).
	vec4 c = texture(textures, vec3(UV, UV2.x));
	if (c.a < 0.5) {
		discard;
	}
	// The PS1 tints in gamma space.
	ALBEDO = c.rgb * pow(COLOR.rgb * mix(1.0, 255.0 / 128.0, UV2.y), vec3(2.2));
	%s
}
"""
## The dome's radius in the scene (m): any size draws the same, round the camera; this keeps it
## past the near plane.
const RADIUS := 200.0
## The dome's open top: its highest ring (its edges this share of the highest vertex's height
## up, or more), when that's higher than this share of its radius.
const CAP_HEIGHT := 0.3
const CAP_RING := 0.97
## The dome's depth (reversed Z, in w): two steps of a 24-bit depth buffer up from the cleared
## 0; track.gdshader's far_away backdrop stands in front of it (at w * 3.6e-7 and up).
const SKY_DEPTH := 1.2e-7
## PS1 semi-transparency (the page's bits 5-6): 0 half and half, 1 added, 2 taken away, 3 a
## quarter added.
enum Blend { OPAQUE, HALF, ADD, SUB, QUARTER }

static var _shaders := {}


## The sky `index` (.crsinfo's: its place among bgsobj's skies) as a node, or null.
static func build(index: int) -> MeshInstance3D:
	var vol := Gt2Track.vol
	if vol == null or index < 0:
		return null
	var names := Array(vol.list("bgsobj")).filter(func(f: String) -> bool: return f.ends_with(".bso.gz"))
	if index >= names.size():
		return null
	var stem: String = names[index].trim_suffix(".bso.gz")
	var d := vol.read("bgsobj/%s.bso.gz" % stem)
	if d.size() < 0x20 or d[0] != 0x42 or d[1] != 0x47:
		return null
	# (The textures read as a course's, their lookup by palette and page too.)
	var tex := Gt2Track.new()
	tex._read_textures(vol.read("bgsobj/%s.bsp.gz" % stem))
	var n_verts := d.decode_u32(0xC)
	var verts := PackedVector3Array()
	for k in n_verts:
		var q := 0x20 + k * 8
		verts.append(Vector3(d.decode_s16(q), d.decode_s16(q + 2), -d.decode_s16(q + 4)) * (RADIUS / 4096.0))
	var surfaces := {}   # blend -> SurfaceTool
	var edges := {}      # Vector2i(a, b), a < b -> [faces it's on, colour at a, colour at b]
	var p := 0x20 + n_verts * 8
	while p + 16 <= d.size():
		var words := d[p + 11]
		if words == 0:
			break
		_add_poly(d, p, verts, tex, surfaces, edges)
		p += 8 + 2 * (4 + words * 4)
	_add_cap(verts, edges, surfaces, tex._white)
	var mesh := ArrayMesh.new()
	var layers := _layers(tex.images)
	for blend: int in surfaces:
		var st: SurfaceTool = surfaces[blend]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(layers, blend))
	var mi := MeshInstance3D.new()
	mi.name = "Gt2Sky"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	return mi


## The dome is open at the top (the PS1's camera never looked up): its rim up there (the
## edges of one face only, high up) closed with a fan to the zenith, in the rim's colours.
static func _add_cap(verts: PackedVector3Array, edges: Dictionary, surfaces: Dictionary, white: int) -> void:
	var high := 0.0
	for e: Vector2i in edges:
		high = maxf(high, maxf(verts[e.x].y, verts[e.y].y))
	if high < RADIUS * CAP_HEIGHT:
		return
	var rim := []
	var top := Vector3.ZERO
	var colour := Color(0, 0, 0)
	for e: Vector2i in edges:
		var info: Array = edges[e]
		if info[0] != 1 or minf(verts[e.x].y, verts[e.y].y) < high * CAP_RING:
			continue
		rim.append([e, info[1], info[2]])
		top += verts[e.x] + verts[e.y]
		colour += info[1] + info[2]
	if rim.size() < 3:
		return
	top /= rim.size() * 2
	top.y = maxf(top.y, RADIUS)
	colour /= rim.size() * 2
	var s := _surface(surfaces, Blend.OPAQUE)
	for r: Array in rim:
		for c: Array in [[verts[r[0].x], r[1]], [verts[r[0].y], r[2]], [top, colour]]:
			s.set_color(c[1])
			s.set_uv(Vector2.ZERO)
			s.set_uv2(Vector2(white, 0.0))
			s.add_vertex(c[0])


static func _surface(surfaces: Dictionary, blend: int) -> SurfaceTool:
	if not surfaces.has(blend):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[blend] = st
	return surfaces[blend]


static func _add_poly(d: PackedByteArray, p: int, verts: PackedVector3Array, tex: Gt2Track, surfaces: Dictionary,
		edges: Dictionary) -> void:
	var w0 := d.decode_u32(p)
	var w1 := d.decode_u32(p + 4)
	var code := d[p + 15]
	var quad := code & 0x08 != 0
	var gouraud := code & 0x10 != 0
	var textured := code & 0x04 != 0
	var n := 4 if quad else 3
	var idx := [w0 & 0xFFF, (w0 >> 12) & 0xFFF, w1 & 0xFFF, (w1 >> 12) & 0xFFF]
	for k in n:
		if idx[k] >= verts.size():
			return
	# The packet's words per corner: its place, its colour (gouraud), its UVs (textured).
	var per := 1 + int(gouraud) + int(textured)
	var at := p + 12   # the first colour and code
	var cols: Array[Color] = []
	var uvs: Array[Vector2i] = []
	var clut := 0
	var page := 0
	for k in n:
		var c := at + k * per * 4 if gouraud else at
		cols.append(Color(d[c] / 255.0, d[c + 1] / 255.0, d[c + 2] / 255.0))
		if textured:
			var u := at + 8 + k * per * 4
			uvs.append(Vector2i(d[u], d[u + 1]))
			if k == 0:
				clut = d.decode_u16(u + 2)
			elif k == 1:
				page = d.decode_u16(u + 2)
	var img := tex._white
	var uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	if textured:
		var got := tex._uvs(clut, page, uvs)
		img = got[0]
		uv = got[1]
		# A raw texture (code bit 0) isn't tinted.
		if code & 0x01:
			for k in n:
				cols[k] = Color(128 / 255.0, 128 / 255.0, 128 / 255.0)
	var blend := Blend.OPAQUE
	if code & 0x02:
		blend = [Blend.HALF, Blend.ADD, Blend.SUB, Blend.QUARTER][(page >> 5) & 3] if textured else Blend.HALF
	var s := _surface(surfaces, blend)
	# (Its outline and the colours it shows at its corners, for the cap: _add_cap.)
	var shown: Array[Color] = []
	var avg := _average(tex.images[img]) if textured else Color.WHITE
	for k in n:
		shown.append(Color(avg.r * cols[k].r, avg.g * cols[k].g, avg.b * cols[k].b) * (255.0 / 128.0 if textured else 1.0))
	for k in n:
		# (The outline of a strip quad: 0 1 3 2.)
		var a: int = [0, 1, 3, 2][k] if quad else k
		var b: int = [0, 1, 3, 2][(k + 1) % 4] if quad else (k + 1) % 3
		var e := Vector2i(mini(idx[a], idx[b]), maxi(idx[a], idx[b]))
		var c_lo := shown[a] if idx[a] <= idx[b] else shown[b]
		var c_hi := shown[b] if idx[a] <= idx[b] else shown[a]
		if edges.has(e):
			edges[e][0] += 1
		else:
			edges[e] = [1, c_lo, c_hi]
	# A PS1 quad is a strip: 0 1 2, then 1 3 2.
	for tri in ([[0, 1, 2], [1, 3, 2]] if quad else [[0, 1, 2]]):
		for k: int in tri:
			s.set_color(cols[k])
			s.set_uv(uv[k])
			s.set_uv2(Vector2(img, 1.0 if textured else 0.0))
			s.add_vertex(verts[idx[k]])


## An image's average colour (as stored, gamma), its clear texels left out.
static func _average(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += Color(c.r, c.g, c.b, 1.0)
	return sum / sum.a if sum.a > 0.0 else Color.WHITE


## The images as one array (each stretched to the biggest's size: its UVs are 0..1).
static func _layers(images: Array[Image]) -> Texture2DArray:
	var size := Vector2i(1, 1)
	for im in images:
		size = size.max(im.get_size())
	var layers: Array[Image] = []
	for im in images:
		var l := im.duplicate()
		l.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		layers.append(l)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	return arr


static func _material(layers: Texture2DArray, blend: int) -> ShaderMaterial:
	if not _shaders.has(blend):
		var sh := Shader.new()
		var mode: String = ["blend_mix", "blend_mix", "blend_add", "blend_sub", "blend_add"][blend]
		sh.code = SHADER % [mode, "" if blend == Blend.OPAQUE else "ALPHA = alpha;"]
		_shaders[blend] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[blend]
	m.set_shader_parameter("textures", layers)
	m.set_shader_parameter("alpha", [1.0, 0.5, 1.0, 1.0, 0.25][blend])
	# (The see-through ones over the rest of the sky, still behind the backdrop.)
	m.set_shader_parameter("depth", SKY_DEPTH * (1.0 if blend == Blend.OPAQUE else 1.5))
	return m

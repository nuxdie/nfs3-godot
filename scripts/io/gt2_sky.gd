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
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
// A textured face's tint is 128 as it is (its colours are stored /255).
uniform float tint_scale = 1.0;
uniform float alpha = 1.0;
void vertex() {
	// Round the camera, wherever it is, and as far off as can be: behind everything drawn.
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + VERTEX, 1.0));
	POSITION.z = POSITION.w * 1e-6;
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	// The PS1 tints in gamma space.
	ALBEDO = c.rgb * pow(COLOR.rgb * tint_scale, vec3(2.2));
	%s
}
"""
## The dome's radius in the scene (m): any size draws the same, round the camera; this keeps it
## past the near plane.
const RADIUS := 200.0
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
	var surfaces := {}   # [image, blend, textured] -> SurfaceTool
	var p := 0x20 + n_verts * 8
	while p + 16 <= d.size():
		var words := d[p + 11]
		if words == 0:
			break
		_add_poly(d, p, verts, tex, surfaces)
		p += 8 + 2 * (4 + words * 4)
	var mesh := ArrayMesh.new()
	for key: Array in surfaces:
		var st: SurfaceTool = surfaces[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(tex.images[key[0]], key[1], key[2]))
	var mi := MeshInstance3D.new()
	mi.name = "Gt2Sky"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	return mi


static func _add_poly(d: PackedByteArray, p: int, verts: PackedVector3Array, tex: Gt2Track, surfaces: Dictionary) -> void:
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
	var key := [img, blend, textured]
	if not surfaces.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = st
	var s: SurfaceTool = surfaces[key]
	# A PS1 quad is a strip: 0 1 2, then 1 3 2.
	for tri in ([[0, 1, 2], [1, 3, 2]] if quad else [[0, 1, 2]]):
		for k: int in tri:
			s.set_color(cols[k])
			s.set_uv(uv[k])
			s.add_vertex(verts[idx[k]])


static func _material(img: Image, blend: int, textured: bool) -> ShaderMaterial:
	if not _shaders.has(blend):
		var sh := Shader.new()
		var mode: String = ["blend_mix", "blend_mix", "blend_add", "blend_sub", "blend_add"][blend]
		sh.code = SHADER % [mode, "" if blend == Blend.OPAQUE else "ALPHA = alpha;"]
		_shaders[blend] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[blend]
	m.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("tint_scale", 255.0 / 128.0 if textured else 1.0)
	m.set_shader_parameter("alpha", [1.0, 0.5, 1.0, 1.0, 0.25][blend])
	return m

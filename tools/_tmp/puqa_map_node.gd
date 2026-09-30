extends Node
## `-- <track> x z size`: overhead picture at (x, z) of every SimD segment (numbered, with
## an arrow at its end) over the track, the route's segments thicker.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var w := TrackWorld.load_track(id)
	add_child(w.root)
	w.light(self, false, false, get_viewport())
	var crp := Crp.load_file(Game.track_dir(id))
	var simd := Nfs5Track._read_simd(crp)
	var t: Crp.Entry = crp.misc_of("SimT")[0]
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 20
	var at := 0
	var cols := [Color.RED, Color.CYAN, Color.MAGENTA, Color.YELLOW, Color.ORANGE, Color.WHITE, Color.LIME, Color.DODGER_BLUE]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for k in t.count:
		var n := crp.data.decode_u32(t.offset + k * 4)
		var c: Color = cols[k % cols.size()]
		for i in range(at, at + n - 1):
			var p: Vector3 = simd[i].pos + Vector3.UP * 3
			var q: Vector3 = simd[i + 1].pos + Vector3.UP * 3
			var s: Vector3 = (q - p).cross(Vector3.UP).normalized() * 0.8
			for v in [p - s, q - s, q + s, p - s, q + s, p + s]:
				im.surface_set_color(c)
				im.surface_add_vertex(v)
		var mid: Vector3 = simd[at + n / 2].pos
		var l := Label3D.new()
		l.text = "%d" % k
		l.font_size = 64
		l.pixel_size = float(a[3]) / 2500.0
		l.outline_size = 30
		l.modulate = c
		l.no_depth_test = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = mid + Vector3.UP * 20
		add_child(l)
		at += n
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	for g in w.root.find_children("*", "GeometryInstance3D", true, false):
		g.visibility_range_end = 0.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(a[3])
	cam.far = 1000
	cam.global_position = Vector3(float(a[1]), 400, float(a[2]))
	cam.look_at(Vector3(float(a[1]), 0, float(a[2])), Vector3.FORWARD)
	cam.make_current()
	for k in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shots/qa/%s_map_%s_%s.png" % [id, a[1], a[2]])
	get_tree().quit()

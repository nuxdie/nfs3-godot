extends Node
## Raw PU people parts, each its own colour: -- <car id> <Article:frame> ... [--tag=]
func _opt(args: Array, n: String, d: String) -> String:
	for a: String in args:
		if a.begins_with("--" + n + "="):
			return a.get_slice("=", 1)
	return d

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	Game.scan_data()
	var dir := DataPath.find_ci(Game.pu_root, "Carmodel")
	var ci := Game.cars.find_custom(func(c: Dictionary) -> bool: return c.id == pos[0])
	var rec: Dictionary = Game._pu_cars[Game.cars[ci].path]
	var crp := Crp.load_file(DataPath.find_ci(dir, rec.model + ".crp"))
	var cols := [Color(0.9, 0.9, 0.9), Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.95), Color(0.3, 0.9, 0.3), Color(0.9, 0.8, 0.2), Color(0.8, 0.3, 0.9)]
	var box := AABB()
	var first := true
	for k in range(1, pos.size()):
		var nm: String = pos[k].get_slice(":", 0)
		var fr := int(pos[k].get_slice(":", 1))
		for art in crp.articles:
			if art.name != nm: continue
			var b := crp.sub(art, "Base")
			if pos[k].get_slice(":", 1) == "r": fr = crp.data[b.offset + 77]
			print(nm, " frame ", fr, " of ", crp.data[b.offset + 76])
			var verts := crp.vec3s(crp.sub(art, "vt", 1 | fr << 4))
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for kk in 256:
				var pe := crp.sub(art, "pr", 1 << 12 | kk)
				if pe == null: break
				if pos[k].get_slice_count(":") > 2 and int(pos[k].get_slice(":", 2)) != kk: continue
				var p := crp.part(pe)
				var vi: PackedInt32Array = p.vertex
				for t3 in range(0, vi.size() - 2, 3):
					for c in [0, 2, 1]:
						var v := verts[vi[t3 + c]]
						var w := Vector3(-v.x, v.y, v.z) * Vector3(1, 1, -1)  # face +Z like ours
						st.add_vertex(w)
						box = AABB(w, Vector3.ZERO) if first else box.expand(w)
						first = false
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			var m := StandardMaterial3D.new()
			m.albedo_color = cols[(k - 1) % cols.size()]
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if k == 1 and _opt(args, "ghost", "0") == "1":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = 0.35
			mi.material_override = m
			add_child(mi)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 160, 0); add_child(sun)
	var cam := Camera3D.new(); cam.fov = 35; add_child(cam); cam.make_current()
	var c := box.get_center() + Vector3(0, float(_opt(args, "dy", "0.2")), 0)
	var d := float(_opt(args, "dist", "1.3"))
	var views := [Vector3(0, 0.1, 1), Vector3(-1, 0.1, 0), Vector3(1, 0.1, 0), Vector3(0, 1, -0.05), Vector3(0, 0.2, -1), Vector3(-0.7, 0.3, -0.7)]
	var w := 400
	var sheet := Image.create(w * 3, w * 2, false, Image.FORMAT_RGBA8)
	for i in views.size():
		cam.global_position = c + views[i].normalized() * d
		cam.look_at(c, Vector3.UP if absf(views[i].normalized().y) < 0.9 else Vector3.FORWARD)
		for k in 4: await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var s := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
		img.resize(w, w)
		sheet.blit_rect(img, Rect2i(0, 0, w, w), Vector2i(w * (i % 3), w * (i / 3)))
	sheet.save_png("res://shots/ppl_%s.png" % _opt(args, "tag", "x"))
	print("saved")
	get_tree().quit()

extends SceneTree
## Headless check of the GT2 loaders: ./godot --headless --path . -s tools/_tmp/gt2_probe.gd

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	print("image: ", img)
	var t0 := Time.get_ticks_msec()
	var vol := Gt2Vol.open(img)
	if vol == null:
		print("no vol")
		quit()
		return
	print("vol open ms ", Time.get_ticks_msec() - t0, " root ", vol.list(""))
	t0 = Time.get_ticks_msec()
	var table := Gt2Car.car_table(vol)
	print("table ", table.size(), " ms ", Time.get_ticks_msec() - t0)
	for r in table.slice(0, 5):
		print("  ", r.id, " ", r.name, " ", r.make, " ", r.year, " colours ", r.colours.size(), " ", r.colours[0])
	for id in ["a26sn", "ld7cn", "hiasn", "a-a7r"]:
		var rec: Dictionary = {}
		for r in table:
			if r.id == id:
				rec = r
		if rec.is_empty():
			print(id, " not listed")
			continue
		t0 = Time.get_ticks_msec()
		var c := Gt2Car.load_car(vol, rec)
		var faces := 0
		for b in c.body_parts:
			faces += (b.mesh as Mesh).get_faces().size() / 3
		print(id, " ", c.display_name, " err='", c.error, "' tris ", faces, " half ", c.half_size, " wheels ", c.wheels.map(func(w): return w.center), " ms ", Time.get_ticks_msec() - t0)
		print("   info ", c.info)
		print("   mass ", c.carp_value(2), " top ", c.carp_value(15) * 3.6, " gears ", c.carp.get(8), " fd ", c.carp_value(11), " tyre ", c.carp.get(36), " front ", c.carp_value(25))
		if c.texture:
			c.texture.get_image().save_png("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f0b80688-5c8f-4d8c-8592-b4bc1de5eb94/scratchpad/atlas_%s.png" % id)
	quit()

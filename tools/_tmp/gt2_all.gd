extends SceneTree
## Loads every listed GT2 car: ./godot --headless --path . -s tools/_tmp/gt2_all.gd

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	var table := Gt2Car.car_table(vol)
	var t0 := Time.get_ticks_msec()
	var bad := 0
	var no_paint := 0
	for rec in table:
		var c := Gt2Car.load_car(vol, rec)
		var tris := 0
		for b in c.body_parts:
			tris += (b.mesh as Mesh).get_faces().size() / 3
		if c.error != "" or tris < 50 or c.half_size.z < 1.0 or c.half_size.z > 3.5 or c.carp_value(2) < 500:
			bad += 1
			print("BAD ", rec.id, " ", rec.name, " err=", c.error, " tris ", tris, " half ", c.half_size, " mass ", c.carp_value(2))
		if c.colours.size() > 1 and c.texture and c.texture.get_image().get_pixel(0, 0).a < 0.0:
			no_paint += 1
	print("loaded ", table.size(), " bad ", bad, " ms ", Time.get_ticks_msec() - t0)
	quit()

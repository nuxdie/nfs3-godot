extends SceneTree
## Prints the lamps the GT2 loader finds: ./godot --headless --path . -s tools/_tmp/gt2_lamps.gd

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	var table := Gt2Car.car_table(vol)
	var counts := {}
	var t0 := Time.get_ticks_msec()
	for rec in table:
		var c := Gt2Car.load_car(vol, rec)
		var k := {"H": 0, "T": 0, "B": 0}
		for l in c.lights:
			k[l.kind] += 1
		var key := "H%d T%d B%d" % [k.H, k.T, k.B]
		counts[key] = counts.get(key, 0) + 1
		if rec.id in ["a26sn", "hiasn", "ld7cn", "a-a7r"]:
			print(rec.id, " ", key, " ", c.lights.map(func(l): return l.kind + str(l.pos.snapped(Vector3.ONE * 0.01))))
	print("ms ", Time.get_ticks_msec() - t0)
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for key in keys.slice(0, 20):
		print(key, ": ", counts[key])
	quit()

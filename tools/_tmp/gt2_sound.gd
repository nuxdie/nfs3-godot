extends SceneTree
## Dumps a GT2 car's engine voices as WAVs: ./godot --headless --path . -s tools/_tmp/gt2_sound.gd

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	for rec in Gt2Car.car_table(vol):
		if rec.id != "a26sn":
			continue
		var c := Gt2Car.load_car(vol, rec)
		var t0 := Time.get_ticks_msec()
		var vs := c.engine_voices()
		print("voices ", vs.size(), " ms ", Time.get_ticks_msec() - t0, " turbo ", c._turbo, " sound ", c._sound)
		for i in vs.size():
			var v: Dictionary = vs[i]
			print(i, " rpm ", v.rpm, " exhaust ", v.exhaust, " gain ", v.gain, " rate ", v.stream.mix_rate, " samples ", v.stream.data.size() / 2, " table@0,208,415 ", v.table.decode_s8(0), ",", v.table.decode_s8(208), ",", v.table.decode_s8(415))
			v.stream.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f0b80688-5c8f-4d8c-8592-b4bc1de5eb94/scratchpad/es_%02d.wav" % i)
	quit()

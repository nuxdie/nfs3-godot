extends Node
## Loads every Hot Pursuit 2 car's sounds the way CarAudio does and reports what decodes.


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var game: Node = get_node("/root/Game")
	print("hp2_root ", game.hp2_root)
	var s := GameSounds.shared()
	print("hp2 gen ", s.hp2 != null, " siren ", s.hp2_siren != null and s.hp2_siren.stream(0) != null)
	for p in [0, 10, 40, 41, 42, 45]:
		print(" gen ", p, " ", s.hp2.stream(p) != null)
	for rec: Dictionary in Nfs6Car.car_table(game.hp2_root):
		var c := Nfs6Car.load_car(rec)
		var line := "%-28s" % rec.name
		var eng := c.sound_bank("careng.bnk")
		var n := 0
		if eng:
			for p in eng.patch_ids():
				if eng.stream(p) and eng.stream(p).loop_mode != AudioStreamWAV.LOOP_DISABLED:
					n += 1
		var ctb: Array = CarAudio._engine_table(c.sound_files.get("careng.ctb", PackedByteArray()))
		var ltb: Array = CarAudio._engine_table(c.sound_files.get("careng.ltb", PackedByteArray()))
		line += " careng=%d loops ctb=%d ltb=%d" % [n, ctb.size(), ltb.size()]
		var o := c.sound_bank("ocar.bnk")
		line += " ocar=%s" % ("%d,%d" % [int(o.stream(0) != null), int(o.stream(1) != null)] if o else "-")
		var h := c.sound_bank("horn.bnk")
		line += " horn=%s" % ("ok" if h and h.stream(0) else "-")
		print(line)
		if eng and rec.folder.get_file() == "F50":
			for p in eng.patch_ids():
				eng.stream(p).save_to_wav(out.path_join("f50_eng_%02d.wav" % p))
			h.stream(0).save_to_wav(out.path_join("f50_horn.wav"))
	get_tree().quit()

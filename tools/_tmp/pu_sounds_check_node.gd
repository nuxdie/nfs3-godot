extends Node
## `godot --headless --path . -s tools/_tmp/pu_sounds_check.gd -- <out dir>`: decodes Porsche
## Unleashed's banks the way the game does and writes some to WAVs for comparison.


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var game: Node = get_node("/root/Game")
	print("pu_root ", game.pu_root)
	var s := GameSounds.shared()
	print("pu ", s.pu != null, " pu_fe ", s.pu_fe != null, " gen ", s.gen != null)
	var ok := 0
	var bad := []
	for p in s.pu.patch_ids():
		for l in s.pu.layer_count(p):
			if s.pu.stream(p, l):
				ok += 1
			else:
				bad.append("%d:%d" % [p, l])
	print("snd_coll decoded ", ok, " failed ", bad)
	for p in [5, 42, 64, 118, 10, 6]:
		s.pu.stream(p).save_to_wav(out.path_join("coll_%03d.wav" % p))
	s.pu.stream(5, 1).save_to_wav(out.path_join("coll_005_1.wav"))
	for i in 3:
		var st := s.pu_fe.stream(GameSounds.PU_MENU[i])
		print("fe ", GameSounds.PU_MENU[i], " stereo ", st.stereo if st else null)
	var recs: Array = Nfs5Car.car_table(game.pu_root)
	for want in ["sd1a", "sd9", "maz2", "Sbus"]:
		for rec: Dictionary in recs:
			if rec.sound == want:
				var c := Nfs5Car.load_car(game.pu_root, rec)
				var line := "%s %s:" % [rec.name, want]
				for f in ["careng.bnk", "ocar.bnk", "ocarex.bnk"]:
					var b := c.sound_bank(f)
					var n := 0
					if b:
						for p in b.patch_ids():
							if b.stream(p):
								n += 1
					line += " %s=%s" % [f, str(n) if b else "-"]
					if b and b.stream(0):
						b.stream(0).save_to_wav(out.path_join("%s_%s.wav" % [want, f.get_basename()]))
				print(line)
				break
	get_tree().quit()

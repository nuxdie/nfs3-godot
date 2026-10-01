extends SceneTree
const HP2 := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Audio/Sfx/"
const HS := "/home/n/NFSHS-revive/need-for-speed-high-stakes/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - High Stakes/Data/Audio/Sfx/"
func dump(b: EaBnk, pre: String):
	for p in b.patch_ids():
		for l in b.layer_count(p):
			var s := b.stream(p, l)
			if s:
				s.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/wav/%s_%03d_%d.wav" % [pre, p, l])
func _init():
	DirAccess.make_dir_recursive_absolute("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/wav")
	for f in ["gen", "genopp", "siren"]:
		dump(EaBnk.parse(FileAccess.get_file_as_bytes(HP2 + f + ".bnk")), "hp2" + f)
	dump(EaBnk.parse(FileAccess.get_file_as_bytes(HS + "gen.bnk")), "hsgen")
	var v := Viv.load_file(HP2 + "oppbnk.viv")
	for k in ["348.bnk", "neo.bnk"]:
		dump(EaBnk.parse(v.files[k]), "opp" + k.get_basename())
	v = Viv.load_file(HP2 + "hornz.viv")
	for k in ["911horn.bnk", "genhorn.bnk"]:
		dump(EaBnk.parse(v.files[k]), "horn" + k.get_basename())
	quit()

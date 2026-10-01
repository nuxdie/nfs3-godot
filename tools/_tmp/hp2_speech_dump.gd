extends SceneTree
## Dumps HP2's speech clips to WAVs: <out>/<viv>/<dat>_<NN>.wav. Args: viv names, or all.
const SP := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Audio/Speech/English/"
func _init():
	var out := "/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/speech"
	var only := OS.get_cmdline_user_args()
	var n := 0
	for vn in ["radio", "frontend", "disploc", "rtrloc", "19loc", "27loc", "31loc", "46loc"]:
		if not only.is_empty() and not vn in only:
			continue
		var v := Viv.load_file(SP + vn + ".viv")
		DirAccess.make_dir_recursive_absolute(out + "/" + vn)
		for k: String in v.files:
			var s := Hp2Speech.parse(v.files[k])
			if s == null:
				print("none ", vn, "/", k)
				continue
			for i in s.count():
				var w := s.clip(i)
				if w == null:
					print("bad ", vn, "/", k, " ", i)
					continue
				w.save_to_wav("%s/%s/%s_%02d.wav" % [out, vn, k.get_basename(), i])
				n += 1
	print("clips ", n)
	quit()

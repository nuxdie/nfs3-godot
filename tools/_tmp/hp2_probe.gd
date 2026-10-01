extends SceneTree
const HP2 := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Audio/"
func _init():
	for f in ["Sfx/gen.bnk", "Sfx/siren.bnk", "Sfx/genopp.bnk", "Sfx/fesfx.bnk"]:
		var b := EaBnk.parse(FileAccess.get_file_as_bytes(HP2 + f))
		print("== ", f, " patches ", b.patch_ids().size())
		for p in b.patch_ids():
			for l in b.layer_count(p):
				var t: Dictionary = b._patches[p][l]
				var s := ""
				for k in t: s += "%x=%d " % [k, t[k]]
				var st := b.stream(p, l)
				print(p, ":", l, " ", s, " ok=", st != null)
	var v := Viv.load_file(HP2 + "Sfx/careng.viv")
	print(v.files.keys())
	var b2 := EaBnk.parse(v.files[v.files.keys()[0]])
	for p in b2.patch_ids():
		for l in b2.layer_count(p):
			var t: Dictionary = b2._patches[p][l]
			var s := ""
			for k in t: s += "%x=%d " % [k, t[k]]
			print(p, ":", l, " ", s, " ok=", b2.stream(p, l) != null)
	for vn in ["oppbnk.viv", "hornz.viv", "cartable.viv"]:
		var vv := Viv.load_file(HP2 + "Sfx/" + vn)
		print(vn, " ", vv.files.keys())
	quit()

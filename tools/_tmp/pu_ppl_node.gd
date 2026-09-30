extends Node
func _ready() -> void:
	Game.scan_data()
	var dir := DataPath.find_ci(Game.pu_root, "Carmodel")
	var id: String = OS.get_cmdline_user_args()[0]
	var ci := Game.cars.find_custom(func(c: Dictionary) -> bool: return c.id == id)
	var rec: Dictionary = Game._pu_cars[Game.cars[ci].path]
	print(rec)
	var f := DataPath.find_ci(dir, rec.model + ".crp")
	print(f)
	var crp := Crp.load_file(f)
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null: continue
		var bi := crp.data.slice(base.offset + 68, base.offset + 84)
		if bi[10] in [0x81, 0x89]:
			var tr := crp.sub(art, "tr", 1)
			var vt := crp.vec3s(crp.sub(art, "vt", 1 | bi[9] << 4))
			var bb := AABB(vt[0], Vector3.ZERO) if vt.size() > 0 else AABB()
			for v in vt: bb = bb.expand(v)
			print("%-16s slot %d var %d lvl %x frames %d rest %d tr %s nv %d box %s" % [art.name, bi[0], bi[1], bi[10], bi[8], bi[9], tr != null, vt.size(), bb])
	for art in crp.articles:
		if not (art.name.begins_with("DriverBody") or art.name.begins_with("LeftHand") or art.name.begins_with("RightHand") or art.name.begins_with("Legs") or art.name.begins_with("LeftArm") or art.name.begins_with("RightArm") or art.name == "Passenger"): continue
		var base := crp.sub(art, "Base")
		var rest: int = crp.data[base.offset + 68 + 9]
		var vt := crp.vec3s(crp.sub(art, "vt", 1 | rest << 4))
		var m := Vector3.ZERO
		var bb := AABB(vt[0], Vector3.ZERO)
		for v in vt: m += v; bb = bb.expand(v)
		var trs := ""
		var tr := crp.sub(art, "tr", 1)
		if tr != null: trs = str(_tr(crp, tr))
		print("%-13s mean %s xmid %.3f %s" % [art.name, m / vt.size(), bb.get_center().x, trs])
	get_tree().quit()
	return
	for art in crp.articles:
		if art.name not in ["LeftHand1", "RightHand1", "DriverBody1", "LeftArm1", "RightArm1"]: continue
		var base := crp.sub(art, "Base")
		var n: int = crp.data[base.offset + 68 + 8]
		for fr in n:
			var e := crp.sub(art, "vt", 1 | fr << 4)
			if e == null: continue
			var vt := crp.vec3s(e)
			if art.name.begins_with("Driver"):
				# shoulders: the vertices with the extreme |x - mid| among the top third
				var bb := AABB(vt[0], Vector3.ZERO)
				for v in vt: bb = bb.expand(v)
				var top := bb.end.y
				var l := Vector3(INF, 0, 0); var r := Vector3(-INF, 0, 0)
				for v in vt:
					if v.y > top - 0.25:
						if v.x < l.x: l = v
						if v.x > r.x: r = v
				print("%s f%d top %.3f  xmin %s  xmax %s" % [art.name, fr, top, l, r])
			else:
				# shoulder end: the rearmost (max z) 15% of vertices
				var zs := []
				for v in vt: zs.append(v.z)
				zs.sort()
				var cut: float = zs[int(zs.size() * 0.85)]
				var c := Vector3.ZERO; var k := 0
				var hand := Vector3.ZERO; var hk := 0
				for v in vt:
					if v.z >= cut: c += v; k += 1
					if v.z <= zs[int(zs.size() * 0.15)]: hand += v; hk += 1
				print("%s f%d shoulder %s hand %s" % [art.name, fr, c / k, hand / hk])
	get_tree().quit()

func _tr(crp: Crp, e) -> Array:
	var out := []
	for k in 12: out.append(snappedf(crp.data.decode_float(e.offset + 16 + k * 4), 0.001))
	return out

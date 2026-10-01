extends SceneTree
func _init() -> void:
	var root := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Cars/"
	for car in ["Vanq", "911t", "Clkgtr", "Tsuv"]:
		var b := Eagl.parse(FileAccess.get_file_as_bytes(root + car + "/animbank.o"))
		var bank: int = b.symbols["__AnimationBank:::Animation1"]
		var n := b.u32(bank + 4)
		var line: String = car + ": "
		for i in n:
			var clip := b.u32(b.u32(bank + 12) + i * 4)
			var cname := b.c_string(b.u32(b.u32(bank + 16) + i * 4))
			var kinds := []
			for k in b.u32(clip + 8) & 0xFFFF:
				var part := b.u32(clip + 12 + k * 4)
				var kind := b.u32(part) & 0xFFFF
				var s := "%x" % kind
				if kind == 0x14:
					var desc := b.data.decode_u16(part + 0x10)
					var count := desc >> 8
					var data := part + 0x14 + count * 2
					var first := b.data.decode_u16(part + 0x14)
					var mx := 0.0
					for j in count:
						var o := data + b.data.decode_u16(part + 0x14 + j * 2) - first
						var v := Vector3(b.data.decode_float(o), b.data.decode_float(o + 4), b.data.decode_float(o + 8))
						mx = maxf(mx, v.length())
					s += "(n%d max%.2f)" % [count, mx]
				kinds.append(s)
			line += "%s f%d %s; " % [cname, b.u32(clip + 8) >> 16, kinds]
		print(line)
	var sk := Eagl.parse(Viv.load_file(root + "Vanq/car.viv").get_file("skeleton.o"))
	print(sk.symbols.keys().filter(func(k): return k.begins_with("__Bone")))
	quit()

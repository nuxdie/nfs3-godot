extends SceneTree
func _process(_d):
	var v: Gt2Vol = root.get_node("Game")._gt2_vol
	var d := v.read(".crsinfo")
	for i in d.decode_u16(6):
		var p := 8 + i * 24
		var at := d.decode_u32(p)
		var name := d.slice(at, d.find(0, at)).get_string_from_utf8()
		var s := ""
		for k in range(8, 24):
			s += "%02x " % d[p + k]
		var extra := ""
		for k in [12, 16, 20]:
			var o := d.decode_u32(p + k)
			if o > 0 and o < d.size():
				extra += " [%d]=%s" % [k, d.slice(o, d.find(0, o)).get_string_from_utf8()]
		print("%-28s %s%s" % [name, s, extra])
	print(v.list("bgsobj"))
	quit()
	return true

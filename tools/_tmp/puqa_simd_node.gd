extends Node
## `-- <track>`: SimD's unread words (offset 0 and 52) per segment: the values they take.
func _ready() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var crp := Crp.load_file(Game.track_dir(id))
	var e: Crp.Entry = crp.misc_of("SimD")[-1]
	var t: Crp.Entry = crp.misc_of("SimT")[0]
	var d := crp.data
	var at := 0
	for k in t.count:
		var n := d.decode_u32(t.offset + k * 4)
		var w0 := {}
		var w52 := {}
		for i in range(at, at + n):
			var p := e.offset + i * 80
			w0["%08x" % d.decode_u32(p)] = w0.get("%08x" % d.decode_u32(p), 0) + 1
			w52["%08x" % d.decode_u32(p + 52)] = w52.get("%08x" % d.decode_u32(p + 52), 0) + 1
		print("seg %2d n %4d  w0 %s  w52 %s" % [k, n, str(w0.keys().slice(0, 5)), str(w52.keys().slice(0, 5))])
		at += n
	var others := []
	for m in crp.misc:
		others.append("%s%d(%d)" % [m.id, m.index, m.count])
	print(" ".join(others.slice(0, 80)))
	get_tree().quit()

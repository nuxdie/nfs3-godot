extends Node
## `-- <track> <article> <part hex>`: the part's raw header, info and index rows, and the
## first corners' vertex positions as the loader reads them.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var crp := Crp.load_file(Game.track_dir(a[0]))
	var d := crp.data
	for art in crp.articles:
		if not a[1] in art.name:
			continue
		var pe := crp.sub(art, "pr", a[2].hex_to_int())
		var o := pe.offset
		var words := []
		for w in 12:
			words.append("%08x" % d.decode_u32(o + w * 4))
		print("count %d length %d  hdr %s" % [pe.count, pe.length, " ".join(words)])
		var n_info := d.decode_s32(o + 40)
		var n_index := d.decode_s32(o + 44)
		var at := o + 48
		for i in n_info:
			var r := []
			for w in 4:
				r.append("%08x" % d.decode_u32(at + w * 4))
			print("  info %s" % " ".join(r))
			at += 16
		for i in n_index:
			print("  index row %08x %08x" % [d.decode_u32(at), d.decode_u32(at + 4)])
			at += 8
		var raw := []
		for k in mini(pe.length - (at - o), 96):
			raw.append(d[at + k])
		print("  bytes after rows: %s" % [raw])
		var verts := crp.vec3s(crp.sub(art, "vt"))
		var p := crp.part(pe)
		for k in mini(12, p.vertex.size()):
			print("   corner %d -> v%d %s" % [k, p.vertex[k], verts[p.vertex[k]].snappedf(0.1)])
	get_tree().quit()

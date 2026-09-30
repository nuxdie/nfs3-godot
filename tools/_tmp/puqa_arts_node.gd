extends Node
## `-- <track> <name substring>`: matching articles: flags, sub-entry ids, box.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var crp := Crp.load_file(Game.track_dir(a[0]))
	for art in crp.articles:
		if not a[1] in art.name:
			continue
		var base := crp.sub(art, "Base")
		var flags := crp.data.decode_u32(base.offset) if base else 0
		var ids := {}
		for key in art.subs:
			var id: String = key.get_slice(":", 0)
			var idx := int(key.get_slice(":", 1))
			ids[id] = ids.get(id, []) + ["%x" % idx]
		var vt := crp.sub(art, "vt")
		print("%-40s %08x %s" % [art.name, flags, ids])
	get_tree().quit()

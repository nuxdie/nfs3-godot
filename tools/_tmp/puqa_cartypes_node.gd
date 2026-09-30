extends Node
## Primitive types (u16 at a part's start) over every Carmodel/*.crp.
func _ready() -> void:
	var dir := Game.find_ci(Game.pu_root, "carmodel")
	var total := {}
	var with1 := []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() != "crp":
			continue
		var crp := Crp.load_file(dir.path_join(f))
		if crp.error != "":
			continue
		var n1 := 0
		for art in crp.articles:
			for key in art.subs:
				if not key.begins_with("pr:"):
					continue
				var ty := crp.data.decode_u16(art.subs[key].offset)
				total[ty] = total.get(ty, 0) + 1
				if ty == 1:
					n1 += 1
		if n1 > 0:
			with1.append("%s:%d" % [f, n1])
	print("car part types %s; files with type 1: %s" % [total, with1])
	get_tree().quit()

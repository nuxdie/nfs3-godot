class_name DataPath
## Case-insensitive path lookup (a Windows install uses mixed case: "GameData/Tracks/Trk000").


## Returns the real absolute path of `rel` under `base`, or "" when it doesn't exist.
static func find_ci(base: String, rel: String) -> String:
	if base == "":
		return ""
	var cur := base
	for part in rel.split("/", false):
		var exact := cur.path_join(part)
		if DirAccess.dir_exists_absolute(exact) or FileAccess.file_exists(exact):
			cur = exact
			continue
		var d := DirAccess.open(cur)
		if d == null:
			return ""
		var found := ""
		for e in Array(d.get_directories()) + Array(d.get_files()):
			if e.to_lower() == part.to_lower():
				found = e
				break
		if found == "":
			return ""
		cur = cur.path_join(found)
	return cur

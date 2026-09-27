class_name Viv
## Reader for "BIGF" (.viv) archives. Entry names are lower-cased.

var files := {}


static func load_file(path: String) -> Viv:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 16 or d.slice(0, 4).get_string_from_ascii() != "BIGF":
		return null
	var v := Viv.new()
	var count := _be32(d, 8)
	var p := 16
	for i in count:
		if p + 8 > d.size():
			break
		var pos := _be32(d, p)
		var size := _be32(d, p + 4)
		p += 8
		var name_end := p
		while name_end < d.size() and d[name_end] != 0:
			name_end += 1
		var name := d.slice(p, name_end).get_string_from_ascii().to_lower()
		p = name_end + 1
		# A truncated archive: leave out entries that run past the end rather than hand back half a file.
		if pos + size <= d.size():
			v.files[name] = d.slice(pos, pos + size)
	return v


static func _be32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


func get_file(name: String) -> PackedByteArray:
	return files.get(name.to_lower(), PackedByteArray())

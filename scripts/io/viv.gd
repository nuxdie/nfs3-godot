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


## Just the directory of an archive too big to read whole: entry name (lower-cased) ->
## Vector2i(offset, size); read one with read_entry.
static func index(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		return out
	var head := f.get_buffer(16)
	if head.size() < 16 or head.slice(0, 4).get_string_from_ascii() != "BIGF":
		return out
	var d := head + f.get_buffer(maxi(_be32(head, 12) - 16, 0))   # the header's length
	var p := 16
	for i in _be32(head, 8):
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
		if pos + size <= f.get_length():
			out[name] = Vector2i(pos, size)
	return out


static func read_entry(path: String, at: Vector2i) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(at.x)
	return f.get_buffer(at.y)


static func _be32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


func get_file(name: String) -> PackedByteArray:
	return files.get(name.to_lower(), PackedByteArray())

class_name Gt2Vol
## Gran Turismo 2's GT2.VOL ("GTFS"): every file of the game but the executables and music,
## most gzipped. Read in place from the disc image (raw 2352-byte sectors, .bin, or a plain
## 2048-byte .iso) or from a GT2.VOL copied off it.
##
## Layout: "GTFS", then from 0x14 a table of u32 offsets o[] up to the file table (where the
## first one points). File k's data starts at o[k] & ~0x7FF (sector aligned) and runs to the
## next one's sector less o[k] & 0x7FF, its padding. The file table: 32-byte records
## {u32 time, u16 index, u8 flags, char name[25]}, a directory's first a ".." (flags 1 =
## directory, its index that of its first record; 0x80 = the directory's last). A file's index
## is one past its offset's (o[index - 1]).

const SECTOR := 2048
const RAW_SECTOR := 2352

var path := ""
var error := ""
var _f: FileAccess
var _raw := false       # 2352-byte sectors
var _raw_skip := 24     # sync, header (and Mode 2's subheader) before a raw sector's data
var _base := 0          # where GT2.VOL starts: its first sector (image) or 0 (a bare GT2.VOL)
var _offsets := PackedInt64Array()
var _files := {}        # "dir/name" (lower case) -> [start, size]
var _dirs := {}         # "dir" -> PackedStringArray of its entries (files and directories)
var _disc := {}         # the disc's root files (an image's): "NAME.EXT" -> Vector2i(first sector, size)


## The archive in the image or GT2.VOL at `file`, or null when it holds none.
static func open(file: String) -> Gt2Vol:
	var v := Gt2Vol.new()
	v.path = file
	v._f = FileAccess.open(file, FileAccess.READ)
	if v._f == null:
		return null
	if not v._find_vol() or not v._read_table():
		return null
	return v


## A disc image of GT2's (Simulation or Arcade disc) among `dir`'s files, or "". The
## Simulation disc first: it has every car.
static func find_image(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var found := ""
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "vol" and f.to_lower() == "gt2.vol":
			return dir.path_join(f)
		if ext in ["bin", "iso", "img"] and (found == "" or "simulation" in f.to_lower()):
			found = dir.path_join(f)
	return found


## A file in the disc image's root ("MUSIC.DAT"): Vector2i(its first sector, its size), or (-1, 0).
func disc_file(name: String) -> Vector2i:
	return _disc.get(name.to_upper(), Vector2i(-1, 0))


## Whether the image keeps whole sectors (a .bin): only then is CD-XA audio (MUSIC.DAT) there.
func raw_sectors() -> bool:
	return _raw


## Bytes `from`..`to` of whole sector `lba` (2352 bytes: sync, header, subheader, data) of a
## raw image.
func raw_sector(lba: int, from := 0, to := RAW_SECTOR) -> PackedByteArray:
	if not _raw:
		return PackedByteArray()
	_f.seek(lba * RAW_SECTOR + from)
	return _f.get_buffer(to - from)


func has(file: String) -> bool:
	return _files.has(file.to_lower())


## The entries of directory `dir` ("" the root), as named in the archive.
func list(dir: String) -> PackedStringArray:
	return _dirs.get(dir.to_lower(), PackedStringArray())


## File `file` ("carobj/a222n.cdo.gz"), gunzipped if it is gzipped; empty if there's none.
func read(file: String) -> PackedByteArray:
	var e: Array = _files.get(file.to_lower(), [])
	if e.is_empty():
		return PackedByteArray()
	var b := _read_at(e[0], e[1])
	if b.size() > 18 and b[0] == 0x1F and b[1] == 0x8B:
		# gzip's trailer holds the size unpacked (mod 2^32: these are all far smaller).
		var n := b.decode_u32(b.size() - 4)
		var out := b.decompress(n, FileAccess.COMPRESSION_GZIP)
		return out if out.size() == n else b.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return b


func _read_at(pos: int, size: int) -> PackedByteArray:
	if not _raw:
		_f.seek(_base + pos)
		return _f.get_buffer(size)
	var out := PackedByteArray()
	while out.size() < size:
		var p := pos + out.size()
		var off := p % SECTOR
		_f.seek((_base + p / SECTOR) * RAW_SECTOR + _raw_skip + off)
		var chunk := _f.get_buffer(mini(SECTOR - off, size - out.size()))
		if chunk.is_empty():
			break
		out.append_array(chunk)
	return out


## Sectors `lba`.. of the image (2048 bytes each).
func _sectors(lba: int, count: int) -> PackedByteArray:
	if not _raw:
		_f.seek(lba * SECTOR)
		return _f.get_buffer(count * SECTOR)
	var out := PackedByteArray()
	for k in count:
		_f.seek((lba + k) * RAW_SECTOR + _raw_skip)
		out.append_array(_f.get_buffer(SECTOR))
	return out


## Where GT2.VOL is: the file itself, or in the image's ISO 9660 root directory.
func _find_vol() -> bool:
	_f.seek(0)
	var head := _f.get_buffer(16)
	if head.size() < 16:
		error = "empty file"
		return false
	if head.slice(0, 4).get_string_from_ascii() == "GTFS":
		_base = 0
		return true
	var sync := PackedByteArray([0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0])
	_raw = head.slice(0, 12) == sync
	_raw_skip = 24 if not _raw or head[15] == 2 else 16
	var pvd := _sectors(16, 1)
	if pvd.slice(1, 6).get_string_from_ascii() != "CD001":
		error = "no ISO 9660 volume"
		return false
	var root_lba := pvd.decode_u32(156 + 2)
	var root_size := pvd.decode_u32(156 + 10)
	var dir := _sectors(root_lba, ceili(root_size / float(SECTOR)))
	var i := 0
	while i < root_size:
		var n := dir[i]
		if n == 0:
			i = (i / SECTOR + 1) * SECTOR   # (records don't cross sectors: the rest is padding)
			continue
		var name := dir.slice(i + 33, i + 33 + dir[i + 32]).get_string_from_ascii().get_slice(";", 0)
		_disc[name.to_upper()] = Vector2i(dir.decode_u32(i + 2), dir.decode_u32(i + 10))
		i += n
	if not _disc.has("GT2.VOL"):
		error = "no GT2.VOL on the disc"
		return false
	_base = _disc["GT2.VOL"].x
	if not _raw:
		_base *= SECTOR
	return true


func _read_table() -> bool:
	var head := _read_at(0, 0x18)
	if head.slice(0, 4).get_string_from_ascii() != "GTFS":
		error = "not a GTFS archive"
		return false
	var table_at := head.decode_u32(0x14) & ~0x7FF
	if table_at <= 0x14 or table_at > 0x100000:
		error = "bad offset table"
		return false
	var t := _read_at(0x14, table_at - 0x14)
	_offsets.resize(t.size() / 4)
	for k in _offsets.size():
		_offsets[k] = t.decode_u32(k * 4)
	# The file table runs to where the first file's data starts (the second offset).
	var names := _read_at(table_at, (_offsets[1] & ~0x7FF) - table_at)
	_walk(names, 0, "")
	return not _files.is_empty()


func _walk(names: PackedByteArray, rec: int, dir: String) -> void:
	var entries := PackedStringArray()
	while rec * 32 + 32 <= names.size():
		var p := rec * 32
		var idx := names.decode_u16(p + 4)
		var flags := names[p + 6]
		var name := names.slice(p + 7, p + 32).get_string_from_ascii()
		if name != "..":
			var full := dir.path_join(name) if dir != "" else name
			entries.append(name)
			if flags & 1:
				_walk(names, idx, full.to_lower())
			elif idx >= 1 and idx < _offsets.size():
				var start := _offsets[idx - 1] & ~0x7FF
				var size := (_offsets[idx] & ~0x7FF) - start - (_offsets[idx - 1] & 0x7FF)
				_files[full.to_lower()] = [start, size]
		if flags & 0x80:
			break
		rec += 1
	_dirs[dir] = entries

class_name EaMusic
## EA's streamed music, decoded a block at a time: High Stakes' .asf songs and NFS3's
## interactive .mus ones.
##
## An .asf is one stream of blocks, each an id and a size (header included): "SCHl" (a "PT"
## header of tagged values, as in EaBnk: 0x82 channels, 0x83 codec, 0x84 rate), "SCCl"
## (block count), "SCDl" (audio), "SCLl" (loop point), "SCEl" (end). A .mus is many such
## streams ("sections"), each starting on a 4-byte boundary, and a .lin or .map file beside it
## ("PFDx") says which section follows which:
##   header: id, ?, first section, section count, record size, 3 ?, record count
##   per section, 28 bytes: ?, branch count, 2 ?, 8 branches of (low, high, next section)
##   then record count x record size bytes (unused here)
##   then per section its offset in the .mus, 32-bit big-endian
## A section picks its next one by a roll of 0..100 against the branches' low..high ranges
## (a .lin has one branch each, 0..100: the song start to finish; a .map several, which
## is how NFS3 varies it). The chain loops back on itself; the song counts as over where it
## first comes back to a section it has played (once `min_length_s` has gone by, else it
## goes round again), and an .asf at its end.
##
## Audio is 16-bit PCM when the header has no codec tag (NFS3's menu music: each "SCDl" its
## sample count, then the samples, channels interleaved), else (0x83 = 7) EA ADPCM: each "SCDl" holds its sample count and each channel's two starting
## samples (16-bit), then frames of 28 samples: stereo, a byte of predictors (left high
## nibble, right low), a byte of shifts, then 28 bytes each holding a left (high) and right
## (low) sample; mono, one byte of predictor and shift and 14 bytes, high nibble first.

const XA_COEF := [[0, 0], [240, 0], [460, -208], [392, -220]]

var rate := 22050
var channels := 2
var min_length_s := 0.0              # a song shorter than this plays its loop again
var finished := false                # played through (next_block then returns nothing)
var played := 0                      # frames handed out so far
var _pcm := false

var _data: PackedByteArray
var _offsets := PackedInt32Array()   # section starts; [0] for an .asf
var _branches: Array = []            # per section: Array of [low, high, next]; [] ends (loops to the first)
var _first := 0
var _section := -1
var _pos := 0                        # next block to read in _data
var _rng := RandomNumberGenerator.new()
var _seen := {}                      # sections played this time round


## An .asf, or null if it isn't one this can decode.
static func open_asf(path: String) -> EaMusic:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var m := EaMusic.new()
	m._data = FileAccess.get_file_as_bytes(path)
	m._offsets = PackedInt32Array([0])
	m._branches = [[]]
	return m if m._read_header(0) else null


## A .mus with its .lin or .map (`map_path`), or null.
static func open_mus(path: String, map_path: String) -> EaMusic:
	if path == "" or map_path == "" or not FileAccess.file_exists(path) or not FileAccess.file_exists(map_path):
		return null
	var map := FileAccess.get_file_as_bytes(map_path)
	if map.size() < 12 or map.slice(0, 4).get_string_from_ascii() != "PFDx":
		return null
	var m := EaMusic.new()
	m._data = FileAccess.get_file_as_bytes(path)
	m._first = map[5]
	var count := map[6]
	var table := 12 + count * 28 + map[11] * map[7]
	if map.size() < table + count * 4:
		return null
	for i in count:
		var p := 12 + i * 28
		var branches := []
		for k in mini(map[p + 1], 8):
			var b := p + 4 + k * 3
			branches.append([map[b], map[b + 1], map[b + 2]])
		m._branches.append(branches)
		var q := table + i * 4
		m._offsets.append((map[q] << 24) | (map[q + 1] << 16) | (map[q + 2] << 8) | map[q + 3])
	if m._first >= count or not m._read_header(m._offsets[m._first]):
		return null
	return m


## The next block of audio as stereo frames (mono doubled), moving on to the next section
## at the end of one; empty at the song's end (`finished`) or if the data is broken.
func next_block() -> PackedVector2Array:
	if finished:
		return PackedVector2Array()
	for guard in 64:
		if _section < 0:
			_start(_first)
		if _pos + 8 > _data.size():
			return PackedVector2Array()
		var id := _data.slice(_pos, _pos + 4).get_string_from_ascii()
		var size := _data.decode_u32(_pos + 4)
		if size < 8:
			return PackedVector2Array()
		var at := _pos
		_pos += size
		match id:
			"SCDl":
				var out := _decode(at + 8, size - 8)
				played += out.size()
				return out
			"SCEl":
				var next := _pick_next()
				if _seen.has(next):
					if played >= min_length_s * rate:
						finished = true
						return PackedVector2Array()
					_seen.clear()
				_start(next)
	return PackedVector2Array()


func _start(section: int) -> void:
	_section = clampi(section, 0, _offsets.size() - 1)
	_pos = _offsets[_section]
	_seen[_section] = true


func _pick_next() -> int:
	var branches: Array = _branches[_section] if _section < _branches.size() else []
	if branches.is_empty():
		return _first
	var roll := _rng.randi_range(0, 100)
	for b: Array in branches:
		if roll >= b[0] and roll <= b[1]:
			return b[2]
	return branches[-1][2]


func _read_header(at: int) -> bool:
	var d := _data
	if at + 12 > d.size() or d.slice(at, at + 4).get_string_from_ascii() != "SCHl":
		return false
	var p := at + 8
	if d[p] != 0x50 or d[p + 1] != 0x54:   # "PT"
		return false
	p += 4
	var codec := 0
	var end := at + d.decode_u32(at + 4)
	while p < end:
		var t := d[p]
		p += 1
		if t == 0xFF:
			break
		if t == 0xFC or t == 0xFD or t == 0xFE:
			continue
		var n := d[p]
		p += 1
		var v := 0
		for k in n:
			v = (v << 8) | d[p + k]
		p += n
		match t:
			0x82: channels = v
			0x83: codec = v
			0x84: rate = v
	# 0 PCM, 7 EA ADPCM. (Split blocks, newer games', aren't handled.)
	_pcm = codec == 0
	return (codec == 0 or codec == 7) and (channels == 1 or channels == 2)


func _decode(p: int, size: int) -> PackedVector2Array:
	var d := _data
	var n := d.decode_u32(p)
	var out := PackedVector2Array()
	if n == 0 or n > 1 << 20:
		return out
	out.resize(n)
	var stereo := channels == 2
	if _pcm:
		n = mini(n, (size - 4) / (4 if stereo else 2))
		out.resize(n)
		for k in n:
			var at := p + 4 + k * (4 if stereo else 2)
			var l := d.decode_s16(at) / 32768.0
			out[k] = Vector2(l, d.decode_s16(at + 2) / 32768.0 if stereo else l)
		return out
	var cur_l := d.decode_s16(p + 4)
	var prev_l := d.decode_s16(p + 6)
	var cur_r := d.decode_s16(p + 8) if stereo else 0
	var prev_r := d.decode_s16(p + 10) if stereo else 0
	var i := p + (12 if stereo else 8)
	var end := p + size
	var o := 0
	while o < n and i < end:
		var todo := mini(28, n - o)
		if stereo:
			if i + 2 + todo > end:
				break
			var pred := d[i]
			var shifts := d[i + 1]
			i += 2
			var l1: int = XA_COEF[(pred >> 4) & 3][0]
			var l2: int = XA_COEF[(pred >> 4) & 3][1]
			var r1: int = XA_COEF[pred & 3][0]
			var r2: int = XA_COEF[pred & 3][1]
			var ls := (shifts >> 4) + 8
			var rs := (shifts & 0x0F) + 8
			for k in todo:
				var b := d[i]
				i += 1
				var hl := b >> 4
				var hr := b & 0x0F
				var l := clampi((((((hl - 16) if hl > 7 else hl) << 28) >> ls) + cur_l * l1 + prev_l * l2 + 128) >> 8, -32768, 32767)
				var r := clampi((((((hr - 16) if hr > 7 else hr) << 28) >> rs) + cur_r * r1 + prev_r * r2 + 128) >> 8, -32768, 32767)
				prev_l = cur_l
				cur_l = l
				prev_r = cur_r
				cur_r = r
				out[o] = Vector2(l / 32768.0, r / 32768.0)
				o += 1
		else:
			if i + 15 > end:
				break
			var hdr := d[i]
			i += 1
			var c1: int = XA_COEF[(hdr >> 4) & 3][0]
			var c2: int = XA_COEF[(hdr >> 4) & 3][1]
			var sh := (hdr & 0x0F) + 8
			for k in 28:
				var b := d[i + (k >> 1)]
				var nib := (b >> 4) if (k & 1) == 0 else (b & 0x0F)
				var v := clampi((((((nib - 16) if nib > 7 else nib) << 28) >> sh) + cur_l * c1 + prev_l * c2 + 128) >> 8, -32768, 32767)
				prev_l = cur_l
				cur_l = v
				if k < todo:
					out[o] = Vector2(v / 32768.0, v / 32768.0)
					o += 1
			i += 14
	if o < n:
		out.resize(o)
	return out

class_name Hp2Speech
## Hot Pursuit 2's speech (Audio/Speech/English/*.viv): each .dat in them is a run of short
## EA streams, one line each, every one starting on a 256-byte boundary: "SCHl" (a "PT"
## header as in EaBnk: 0x84 rate, 24000; 0x85 sample count; 0xA0 codec2 4, MicroTalk), "SCCl",
## "SCDl" blocks (the block's sample count, 4 bytes unused, then MicroTalk carrying on from
## the block before: EaMicroTalk.decode_blocks) and "SCEl". The variations of a line
## sit side by side in one .dat (19Arrest: 22 ways of saying it).
##
## speechdr.viv holds a .hdr for each (files\radio\19Arrest.hdr): an event id (16-bit), ff ff,
## a field count, the clip count, 6 bytes; then per clip its offset in the .dat (256-byte
## units, big-endian) and its fields, one byte each. What the fields say (by transcribing the
## lines): the officers' files end with the speaker (1: 19, 2: 27, 3: 31, 5: 46); a unit
## (AddCount, DispAdd, DispAddDown) is 0..5 for 27, 31, 19, 46, 54, 28; SpeedB's first is
## the speed, 100 + 20 x it mph; Arrest's second, 0 for "you are under arrest".

var _data: PackedByteArray
var _starts := PackedInt32Array()
var _fields: Array[PackedByteArray] = []   # per clip, from the .hdr (set_header); empty without


## A .dat's clips, or null if it has none.
static func parse(d: PackedByteArray) -> Hp2Speech:
	var s := Hp2Speech.new()
	s._data = d
	var p := 0
	while p + 4 <= d.size():
		if d[p] == 0x53 and d[p + 1] == 0x43 and d[p + 2] == 0x48 and d[p + 3] == 0x6C:   # "SCHl"
			s._starts.append(p)
			p += maxi(d.decode_u32(p + 4), 4)
			p = (p + 3) & ~3
		else:
			p += 4
	return s if not s._starts.is_empty() else null


func count() -> int:
	return _starts.size()


## Reads the clips' fields from the .dat's .hdr.
func set_header(h: PackedByteArray) -> void:
	_fields.clear()
	if h.size() < 12:
		return
	var nf := h[4]
	var p := 12
	for i in h[5]:
		if p + 2 + nf > h.size():
			break
		_fields.append(h.slice(p + 2, p + 2 + nf))
		p += 2 + nf


## The clips whose field `field` is `value` (all of them if the .hdr isn't there).
func clips_where(field: int, value: int) -> Array:
	if _fields.size() != _starts.size():
		return range(_starts.size())
	return range(_starts.size()).filter(func(i: int) -> bool: return field < _fields[i].size() and _fields[i][field] == value)


## Clip `i` as a sound (decoding takes a few ms a second of speech), or null.
func clip(i: int) -> AudioStreamWAV:
	if i < 0 or i >= _starts.size():
		return null
	var d := _data
	var p := _starts[i]
	var end := _starts[i + 1] if i + 1 < _starts.size() else d.size()
	var rate := 22050
	var blocks := []
	while p + 8 <= end:
		var id := d.slice(p, p + 4).get_string_from_ascii()
		var size := d.decode_u32(p + 4)
		if size < 8:
			break
		if id == "SCHl":
			rate = _rate(p + 8, p + size)
		elif id == "SCDl" and size > 16:
			var n := d.decode_u32(p + 8)
			if n > 0 and n < 1 << 16:
				blocks.append([p + 16, n])
		elif id == "SCEl":
			break
		p += size
	if blocks.is_empty():
		return null
	var pcm := EaMicroTalk.decode_blocks(d, blocks)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = pcm
	return w


func _rate(p: int, end: int) -> int:
	var d := _data
	if d[p] != 0x50 or d[p + 1] != 0x54:   # "PT"
		return 22050
	p += 4
	while p + 2 <= end:
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
		if t == 0x84:
			return v
	return 22050

class_name EaBnk
## Reader for EA's "BNKl" sound banks (.bnk): NFS3's gamedata/audio/sfx/*.bnk and the engine
## banks in each car.viv, and High Stakes' the same. A bank is a table of patches, each
## a "PT" header of tagged values (one or more layers, split by 0xFE) followed later by
## the sample data. Version 2 (NFS3's shared banks) has a 12-byte header, version 4 (the
## car banks, all of High Stakes') a 20-byte one; the table after it holds, per patch, the
## offset of its header from that table entry (0 or -1 when the slot is empty).
##
## Tags used here (byte tag, byte length, big-endian value):
##   0x0E volume 0..127 (127 when absent)   0x10 fine tune, signed, in cents
##   0x82 channels (1)                      0x83 codec: 0 PCM, 7 EA-XA ADPCM, 9 MicroTalk (speech)
##   0x84 sample rate (22050)               0x85 sample count
##   0x86 loop start, 0x87 loop end (last looped sample)   0x88 data offset in the file
## The rest (priority, pan, bend range, random pitch...) are kept in `tags` unread.
## Samples are decoded to AudioStreamWAVs on first use and cached.

const DEFAULT_RATE := 22050
const CODEC_EAXA := 7
const CODEC_MICROTALK := 9
## EA-XA predictor pairs, picked by a frame's high nibble.
const XA_COEF := [[0, 0], [240, 0], [460, -208], [392, -220]]

var _data: PackedByteArray
var _patches := {}   # patch -> Array of layer Dictionaries (tag -> value)
var _streams := {}   # "patch:layer" -> AudioStreamWAV, or null when it can't be decoded


static func parse(d: PackedByteArray) -> EaBnk:
	if d.size() < 20 or d.slice(0, 4).get_string_from_ascii() != "BNKl":
		return null
	var b := EaBnk.new()
	b._data = d
	var version := d.decode_u16(4)
	var count := d.decode_u16(6)
	var table := 12 if version == 2 else 20
	for i in count:
		var slot := table + i * 4
		if slot + 4 > d.size():
			break
		var off := d.decode_u32(slot)
		if off == 0 or off == 0xFFFFFFFF:
			continue
		var layers := b._read_header(slot + off)
		if not layers.is_empty():
			b._patches[i] = layers
	return b


func has(patch: int) -> bool:
	return _patches.has(patch)


func patch_ids() -> Array:
	return _patches.keys()


func layer_count(patch: int) -> int:
	return _patches[patch].size() if _patches.has(patch) else 0


## A tag's value on one layer of `patch`, or `default`.
func tag(patch: int, t: int, default := 0, layer := 0) -> int:
	if not _patches.has(patch) or layer >= _patches[patch].size():
		return default
	return _patches[patch][layer].get(t, default)


## The layer's volume, 0..1 (tag 0x0E).
func volume(patch: int, layer := 0) -> float:
	return tag(patch, 0x0E, 127, layer) / 127.0


## The layer's fine tune (tag 0x10) as a pitch factor.
func tune(patch: int, layer := 0) -> float:
	var c := tag(patch, 0x10, 0, layer)
	if c >= 128:
		c -= 256
	return pow(2.0, c / 1200.0)


## The layer's sound, looping if it has a loop; null for a missing patch or an unknown codec.
func stream(patch: int, layer := 0) -> AudioStreamWAV:
	var key := "%d:%d" % [patch, layer]
	if not _streams.has(key):
		_streams[key] = _decode(patch, layer)
	return _streams[key]


func _read_header(p: int) -> Array:
	var d := _data
	if p + 4 > d.size() or d[p] != 0x50 or d[p + 1] != 0x54:   # "PT"
		return []
	p += 4
	var layers: Array = [{}]
	while p < d.size():
		var t := d[p]
		p += 1
		if t == 0xFF:
			break
		if t == 0xFC or t == 0xFD:
			continue
		if t == 0xFE:
			layers.append({})
			continue
		if p >= d.size():
			break
		var n := d[p]
		p += 1
		var v := 0
		for k in n:
			if p + k < d.size():
				v = (v << 8) | d[p + k]
		p += n
		layers[-1][t] = v
	# A layer with no samples (the tags before the first 0xFD are the patch's own) is folded
	# into the next one.
	var out := []
	var carry := {}
	for l: Dictionary in layers:
		var merged := carry.duplicate()
		merged.merge(l, true)
		if merged.has(0x85) and merged.has(0x88):
			out.append(merged)
			carry = {}
		else:
			carry = merged
	return out


func _decode(patch: int, layer: int) -> AudioStreamWAV:
	if not _patches.has(patch) or layer >= _patches[patch].size():
		return null
	var h: Dictionary = _patches[patch][layer]
	var n: int = h[0x85]
	var ch: int = h.get(0x82, 1)
	var off: int = h[0x88]
	var codec: int = h.get(0x83, 0)
	var pcm: PackedByteArray
	if codec == 0:
		if ch < 1 or ch > 2 or off + n * ch * 2 > _data.size():
			return null
		pcm = _data.slice(off, off + n * ch * 2)
	elif codec == CODEC_EAXA and ch == 1:
		pcm = _eaxa(off, n)
		if pcm.is_empty():
			return null
	elif codec == CODEC_MICROTALK and ch == 1 and off < _data.size():
		pcm = EaMicroTalk.decode(_data, off, n)
	else:
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = h.get(0x84, DEFAULT_RATE)
	w.stereo = ch == 2
	w.data = pcm
	var ls: int = h.get(0x86, -1)
	var le: int = mini(h.get(0x87, n - 1) + 1, n)
	if ls >= 0 and le > ls + 1:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = ls
		w.loop_end = le
	return w


## EA-XA ADPCM, mono: frames of one header byte (predictor, shift) and 14 bytes of 4-bit
## samples, 28 samples a frame. Returns 16-bit little-endian PCM, or empty if it runs short.
func _eaxa(off: int, n: int) -> PackedByteArray:
	var d := _data
	var frames := ceili(n / 28.0)
	if off + frames * 15 > d.size():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(frames * 56)
	var h1 := 0
	var h2 := 0
	var o := 0
	var p := off
	for f in frames:
		var hdr := d[p]
		var c1: int = XA_COEF[(hdr >> 4) & 3][0]
		var c2: int = XA_COEF[(hdr >> 4) & 3][1]
		var shift := (hdr & 0x0F) + 8
		p += 1
		for k in 14:
			var byte := d[p]
			p += 1
			for nib: int in [byte >> 4, byte & 0x0F]:
				# The nibble as the top of a signed 32-bit word, shifted down.
				var v := (nib << 28) >> shift if nib < 8 else ((nib - 16) << 28) >> shift
				v = (v + h1 * c1 + h2 * c2 + 128) >> 8
				v = clampi(v, -32768, 32767)
				out.encode_s16(o, v)
				o += 2
				h2 = h1
				h1 = v
	out.resize(n * 2)
	return out

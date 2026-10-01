class_name Gt2Music
extends EaMusic
## Gran Turismo 2's music: MUSIC.DAT on its disc, CD-XA audio (Mode 2 Form 2 sectors, stereo,
## 37.8 kHz, 4-bit ADPCM). Each song is one of its 22 channels (the subheader's second byte),
## every fourth sector over one stretch of the file; the short ones (seconds) are jingles.
## Needs the disc as a raw image (.bin): an .iso keeps only 2048 bytes a sector and loses it.
##
## A sector: 24 bytes of sync, header and subheader (file, channel, submode, coding: 0x01
## stereo 37.8 kHz 4-bit), then 18 sound groups of 128 bytes: 16 header bytes (each sound
## unit's filter and shift: units 0..3 at 4..7, 4..7 at 12..15), and 28 words of 4 bytes
## whose nibbles are the 8 units' samples (unit u in byte u / 2, low nibble first), left
## the even units, right the odd: 2016 stereo frames.

const GROUPS := 18
const STRIDE := 4                 # the channels are interleaved one sector each

var channel := 0
var _vol: Gt2Vol
var _sectors := PackedInt32Array()   # the song's sectors (absolute), in order
var _next := 0
var _hist := PackedInt32Array([0, 0, 0, 0])   # left s1, s2, right s1, s2

static var _maps := {}    # image path -> {channel: PackedInt32Array of its sectors}


## The image's songs: channel -> length (s), longest stretches only (`min_s` and up).
static func songs(vol: Gt2Vol, min_s := 30.0) -> Dictionary:
	var out := {}
	var map := _map(vol)
	for c: int in map:
		var s: float = map[c].size() * 2016.0 / 37800.0
		if s >= min_s:
			out[c] = s
	return out


## Song `ch` of the image, or null.
static func open(vol: Gt2Vol, ch: int) -> Gt2Music:
	var map := _map(vol)
	if not map.has(ch):
		return null
	var m := Gt2Music.new()
	m._vol = vol
	m.channel = ch
	m._sectors = map[ch]
	m.rate = 37800
	m.length_frames = m._sectors.size() * 2016
	return m


## Which sectors of MUSIC.DAT are which channel's (read once per image: a subheader each).
static func _map(vol: Gt2Vol) -> Dictionary:
	if vol == null or not vol.raw_sectors():
		return {}
	if _maps.has(vol.path):
		return _maps[vol.path]
	var map := {}
	var f := vol.disc_file("MUSIC.DAT")
	if f.x >= 0:
		for k in f.y / Gt2Vol.SECTOR:
			var h := vol.raw_sector(f.x + k, 16, 20)
			# (Audio sectors only: submode bit 2. The coding is stereo 37.8 kHz 4-bit throughout.)
			if h.size() < 4 or not h[2] & 0x04 or h[3] != 0x01:
				continue
			if not map.has(h[1]):
				map[h[1]] = []   # (an Array: a packed one in a Dictionary appends to a copy)
			map[h[1]].append(f.x + k)
	for c: int in map:
		map[c] = PackedInt32Array(map[c])
	_maps[vol.path] = map
	return map


func next_block() -> PackedVector2Array:
	if finished:
		return PackedVector2Array()
	if _next >= _sectors.size():
		if played >= min_length_s * rate or _sectors.is_empty():
			finished = true
			return PackedVector2Array()
		_next = 0   # (shorter than min_length_s: once more)
	var d := _vol.raw_sector(_sectors[_next], 24, 24 + GROUPS * 128)
	_next += 1
	var out := _decode_xa(d)
	played += out.size()
	return out


func _decode_xa(d: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(GROUPS * 4 * 28)
	var o := 0
	for g in mini(GROUPS, d.size() / 128):
		var gp := g * 128
		for pair in 4:
			for side in 2:
				var unit := pair * 2 + side
				var param := d[gp + 4 + unit] if unit < 4 else d[gp + 8 + unit]
				var shift := maxi(12 - (param & 15), 0)
				var coef: Array = XA_COEF[(param >> 4) & 3]
				var k0: int = coef[0]
				var k1: int = coef[1]
				var h := side * 2
				var s1 := _hist[h]
				var s2 := _hist[h + 1]
				var nib_shift := (unit & 1) * 4
				var byte_at := gp + 16 + (unit >> 1)
				for i in 28:
					var t := (d[byte_at + i * 4] >> nib_shift) & 15
					if t >= 8:
						t -= 16
					var v := clampi((t << shift) + ((s1 * k0 + s2 * k1 + 128) >> 8), -32768, 32767)
					s2 = s1
					s1 = v
					# (A packed array's element is a copy: set it whole.)
					out[o + i] = Vector2(v / 32768.0, 0.0) if side == 0 else Vector2(out[o + i].x, v / 32768.0)
				_hist[h] = s1
				_hist[h + 1] = s2
			o += 28
	return out

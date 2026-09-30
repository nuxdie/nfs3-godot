class_name EaMicroTalk
## EA MicroTalk ("UTK", MT10:1), the speech codec of NFS3's and High Stakes' speech banks
## (EaBnk codec 9): multipulse CELP / RELP, 432 samples a frame from a variable-length,
## LSB-first bit stream that runs on from frame to frame. Ported from utkdec.c in vgmstream,
## itself from Andrew D'Addesio's public-domain utkencode (github.com/daddesio/utkencode;
## wiki.niotso.org/UTK).
##
## The stream opens with a header (1 bit reduced bandwidth, 4 bits multipulse threshold, 4 bits
## base gain, 6 bits gain step). Each frame: 12 reflection coefficients (6 bits for the first
## four, 5 for the rest, indices into RC), eased in over its four subframes; per subframe of
## 108 samples a pitch lag (8 bits) and gain (4), a fixed gain index (6) and the excitation,
## either Huffman-coded pulses (multipulse) or a 3-level residual (RELP), at half rate with
## the rest interpolated when bandwidth is reduced. A 12th-order lattice-derived LPC filter
## makes the speech.

const FRAME := 432

const RC := [
	0.0, -0.996776, -0.990327, -0.983879, -0.977431, -0.970982, -0.964534, -0.958085,
	-0.951637, -0.930754, -0.90496, -0.879167, -0.853373, -0.827579, -0.801786, -0.775992,
	-0.750198, -0.724405, -0.698611, -0.670635, -0.619048, -0.56746, -0.515873, -0.464286,
	-0.412698, -0.361111, -0.309524, -0.257937, -0.206349, -0.154762, -0.103175, -0.051587,
	0.0, 0.051587, 0.103175, 0.154762, 0.206349, 0.257937, 0.309524, 0.361111,
	0.412698, 0.464286, 0.515873, 0.56746, 0.619048, 0.670635, 0.698611, 0.724405,
	0.750198, 0.775992, 0.801786, 0.827579, 0.853373, 0.879167, 0.90496, 0.930754,
	0.951637, 0.958085, 0.964534, 0.970982, 0.977431, 0.983879, 0.990327, 0.996776,
]
## Huffman lookup by the next 8 bits, per model (normal, large-pulse) -> command.
const CODEBOOK := [[
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 17, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 21,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 18, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 25,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 17, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 22,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 18, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 0,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 17, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 21,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 18, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 26,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 17, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 22,
	4, 6, 5, 9, 4, 6, 5, 13, 4, 6, 5, 10, 4, 6, 5, 18, 4, 6, 5, 9, 4, 6, 5, 14, 4, 6, 5, 10, 4, 6, 5, 2,
], [
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 23, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 27,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 24, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 1,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 23, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 28,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 24, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 3,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 23, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 27,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 24, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 1,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 23, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 28,
	4, 11, 7, 15, 4, 12, 8, 19, 4, 11, 7, 16, 4, 12, 8, 24, 4, 11, 7, 15, 4, 12, 8, 20, 4, 11, 7, 16, 4, 12, 8, 3,
	]]
## Per command: the model after it, the bits it takes, its pulse.
const CMD_MODEL := [1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
const CMD_BITS := [8, 7, 8, 7, 2, 2, 2, 3, 3, 4, 4, 3, 3, 5, 5, 4, 4, 6, 6, 5, 5, 7, 7, 6, 6, 8, 8, 7, 7]
const CMD_PULSE := [0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 1.0, -1.0, 1.0, -2.0, 2.0, -2.0, 2.0, -3.0, 3.0, -3.0, 3.0, -4.0, 4.0, -4.0, 4.0, -5.0, 5.0, -5.0, 5.0, -6.0, 6.0, -6.0, 6.0]

var _d: PackedByteArray
var _p := 0
var _bits := 0
var _count := 0
var _reduced := false
var _threshold := 0
var _gains := PackedFloat32Array()
var _rc := PackedFloat32Array()
var _history := PackedFloat32Array()
## The last 324 samples (the adaptive codebook the pitch lag reads back into), then the frame.
var _buf := PackedFloat32Array()


## `n` samples of MicroTalk from `d` at `off`, as 16-bit little-endian PCM.
static func decode(d: PackedByteArray, off: int, n: int) -> PackedByteArray:
	var m := EaMicroTalk.new()
	m._d = d
	m._p = off
	m._rc.resize(12)
	m._history.resize(12)
	m._buf.resize(324 + FRAME)
	m._gains.resize(64)
	var out := PackedByteArray()
	out.resize(n * 2)
	var o := 0
	var first := true
	while o < n:
		if first:
			m._header()
			first = false
		m._frame()
		for i in mini(FRAME, n - o):
			out.encode_s16((o + i) * 2, clampi(roundi(m._buf[324 + i]), -32768, 32767))
		o += FRAME
	return out


func _byte() -> int:
	if _p < _d.size():
		_p += 1
		return _d[_p - 1]
	return 0


func _read(n: int) -> int:
	var r := _bits & ((1 << n) - 1)
	_bits >>= n
	_count -= n
	if _count < 8:
		_bits |= _byte() << _count
		_count += 8
	return r


func _header() -> void:
	_bits = _byte()
	_count = 8
	_reduced = _read(1) == 1
	_threshold = 32 - _read(4)
	_gains[0] = 8.0 * (1 + _read(4))
	var step := 1.04 + _read(6) * 0.001
	for i in range(1, 64):
		_gains[i] = _gains[i - 1] * step


func _excitation(multipulse: bool, out: PackedFloat32Array, at: int, stride: int) -> void:
	var i := 0
	if multipulse:
		var model := 0
		while i < 108:
			var cmd: int = CODEBOOK[model][_bits & 0xFF]
			model = CMD_MODEL[cmd]
			_read(CMD_BITS[cmd])
			if cmd > 3:
				out[at + i] = CMD_PULSE[cmd]
				i += stride
			elif cmd > 1:
				# A run of 7..70 zeros.
				var zeros := 7 + _read(6)
				if i + zeros * stride > 108:
					zeros = (108 - i) / stride
				for z in zeros:
					out[at + i] = 0.0
					i += stride
			else:
				# A pulse of 7 or more.
				var x := 7
				while _read(1) == 1:
					x += 1
				if _read(1) == 0:
					x = -x
				out[at + i] = x
				i += stride
	else:
		while i < 108:
			match _bits & 3:
				1:
					out[at + i] = -2.0
					_read(2)
				3:
					out[at + i] = 2.0
					_read(2)
				_:
					out[at + i] = 0.0
					_read(1)
			i += stride


func _frame() -> void:
	var multipulse := false
	var delta := PackedFloat32Array()
	delta.resize(12)
	for i in 12:
		var idx: int
		if i == 0:
			idx = _read(6)
			multipulse = idx < _threshold
		elif i < 4:
			idx = _read(6)
		else:
			idx = 16 + _read(5)
		delta[i] = (RC[idx] - _rc[i]) * 0.25
	var ex := PackedFloat32Array()
	ex.resize(118)   # 5 either side for the interpolation
	for s in 4:
		var lag := _read(8)
		var pitch_gain := _read(4) / 15.0
		var gain := _gains[_read(6)]
		if not _reduced:
			_excitation(multipulse, ex, 5, 1)
		else:
			var align := _read(1)
			var zero := _read(1)
			_excitation(multipulse, ex, 5 + align, 2)
			var b := 5 + (1 - align)
			if zero == 1:
				for j in 54:
					ex[b + 2 * j] = 0.0
			else:
				for j in 5:
					ex[j] = 0.0
					ex[113 + j] = 0.0
				for k in range(0, 108, 2):
					var e := b + k
					ex[e] = (ex[e - 5] + ex[e + 5]) * 0.01803268 - (ex[e - 3] + ex[e + 3]) * 0.11459156 \
						+ (ex[e - 1] + ex[e + 1]) * 0.59738597
				gain *= 0.5
		for j in 108:
			var back := maxi(108 * s + 216 - lag + j, 0)
			_buf[324 + 108 * s + j] = gain * ex[5 + j] + pitch_gain * _buf[back]
	for i in 324:
		_buf[i] = _buf[324 + 108 + i]
	for s in 4:
		for j in 12:
			_rc[j] += delta[j]
		_synthesise(12 * s, 1 if s < 3 else 33)


## The LPC filter over `blocks` of 12 samples from `offset` in the frame.
func _synthesise(offset: int, blocks: int) -> void:
	var lpc := _lpc()
	var h := _history
	var p := 324 + offset
	for b in blocks:
		for j in 12:
			var x := _buf[p]
			for k in j:
				x += lpc[k] * h[k - j + 12]
			for k in range(j, 12):
				x += lpc[k] * h[k - j]
			h[11 - j] = x
			_buf[p] = x
			p += 1


## Reflection coefficients to LPC.
func _lpc() -> PackedFloat32Array:
	var rc := _rc
	var t1 := PackedFloat32Array()
	var t2 := PackedFloat32Array()
	var lpc := PackedFloat32Array()
	t1.resize(12)
	t2.resize(12)
	lpc.resize(12)
	for i in range(10, -1, -1):
		t2[i + 1] = rc[i]
	t2[0] = 1.0
	for i in 12:
		var x := -(rc[11] * t2[11])
		for j in range(10, -1, -1):
			x -= rc[j] * t2[j]
			t2[j + 1] = x * rc[j] + t2[j]
		t2[0] = x
		t1[i] = x
		for j in i:
			x -= t1[i - 1 - j] * lpc[j]
		lpc[i] = x
	return lpc

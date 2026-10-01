class_name Gt2Seq
extends EaMusic
## Gran Turismo 2's sequenced music, played on its own instruments: sound/spu_02..10.seq (GT
## Mode's screens) with gtmseq.ins, arcade.seq with arcseq.ins. Rendered a stretch at a time
## on a worker thread, well ahead of where it plays; the intro once, then the loop.
##
## .seq ("SEQG", after xan1242's gtseq2midi): at 8 the sequence count (1), then per sequence
## its master volume, its tempo (240000000 / it = bpm, 120 ticks a beat) and 16 tracks'
## offsets. A track: events, each a MIDI-style variable-length delta then 0 (nothing), 1
## (loop start, 1 byte), 2 (end, 2 bytes), 3 instrument, 4 volume, 5 pan, 6 tempo (1 byte each),
## below 0x80 a pitch bend (two 7-bit bytes, 0x3000 the middle, +-0x1000 the bend range of 3
## semitones), 0x80.. a note (its number + 0x80, velocity, then its length as a delta).
##
## .ins ("INST"): at 0x14 where the samples start, at 0x18 the key regions' count and offset,
## at 0x20 the instruments' count and offset (a u32 offset each to: a region count, a byte,
## a u16, then that many region indices). A region, 20 bytes: u16 sample offset / 8, u16 (?),
## a byte (?), the root note, volume, -, u16 pan (high byte, 0x40 the middle), a byte, -, the
## lowest and highest key, -, ADSR1, ADSR2 (the PS1 sound chip's envelope words). Samples:
## Sony ADPCM at 44.1 kHz, looping where their frames say (flags: 4 loop start, 1 end).

const RATE := 22050
const SPU_RATE := 44100.0
const TRACKS := 16
const PPQN := 120.0
const BEND_RANGE := 3.0
const BLOCK := 32                  # frames between envelope updates
const CHUNK_S := 1.0               # what the thread renders at a time
const GAIN := 0.45

var _seq := PackedByteArray()
var _ins := PackedByteArray()
var _samples_at := 0
var _regions: Array[Dictionary] = []
var _programs: Array[PackedInt32Array] = []
var _decoded := {}                 # region index -> [PackedFloat32Array, loop start or -1]
var _events: Array = []            # [tick, track, kind, a, b, c], by tick
var _tick_s := 0.01
var _loop_tick := -1
var _end_tick := 0
var _loop_frame := 0
var _end_frame := 0

var _out := PackedVector2Array()   # rendered so far (the thread appends under _lock)
var _tail := PackedVector2Array()  # what still sounds past the end, mixed into the loop's start
var _done := false
var _lock := Mutex.new()
var _task := -1
var _at := 0                      # next frame to hand out
var _passes := 0                   # times round the loop


## Sequence `name` ("spu_08", "arcade") of the disc, or null.
static func open(vol: Gt2Vol, name: String) -> Gt2Seq:
	if vol == null:
		return null
	var seq := vol.read("sound/%s.seq" % name)
	var ins := vol.read("sound/%s.ins" % ("arcseq" if name == "arcade" else "gtmseq"))
	var m := Gt2Seq.new()
	m.rate = RATE
	if not m._parse_ins(ins) or not m._parse_seq(seq):
		return null
	m.length_frames = m._end_frame
	m._task = WorkerThreadPool.add_task(m._render)
	return m


func _parse_ins(d: PackedByteArray) -> bool:
	if d.size() < 0x28 or d.slice(0, 4).get_string_from_ascii() != "INST":
		return false
	_ins = d
	_samples_at = d.decode_u32(0x14)
	var n_reg := d.decode_u32(0x18)
	var reg_at := d.decode_u32(0x1C)
	var n_prog := d.decode_u32(0x20)
	var prog_at := d.decode_u32(0x24)
	for k in n_reg:
		var p := reg_at + k * 20
		if p + 20 > d.size():
			return false
		_regions.append({"addr": d.decode_u16(p) * 8, "root": d[p + 5], "vol": d[p + 6] / 127.0,
			"pan": d[p + 9] / 127.0, "lo": d[p + 12], "hi": d[p + 13],
			"adsr1": d.decode_u16(p + 16), "adsr2": d.decode_u16(p + 18)})
	for k in n_prog:
		var o := d.decode_u32(prog_at + k * 4)
		var ids := PackedInt32Array()
		if o + 4 <= d.size():
			for i in d[o]:
				ids.append(d[o + 4 + i])
		_programs.append(ids)
	return not _regions.is_empty()


func _parse_seq(d: PackedByteArray) -> bool:
	if d.size() < 20 + TRACKS * 4 or d.slice(0, 4).get_string_from_ascii() != "SEQG":
		return false
	_seq = d
	var tempo := d.decode_u32(16)
	if tempo <= 0:
		return false
	_tick_s = 60.0 / (240000000.0 / tempo) / PPQN
	for tr in TRACKS:
		var p := d.decode_u32(20 + tr * 4)
		var t := 0
		while p < d.size():
			var dv := _vlv(d, p)
			t += dv.x
			p = dv.y
			var c := d[p]
			if c == 0:
				p += 1
			elif c == 1:
				if _loop_tick < 0:
					_loop_tick = t
				p += 2
			elif c == 2:
				_end_tick = maxi(_end_tick, t)
				break
			elif c <= 6:
				if c != 6:
					_events.append([t, tr, c, d[p + 1], 0, 0])
				p += 2
			elif c < 0x80:
				_events.append([t, tr, 7, ((c & 0x7F) << 7) | (d[p + 1] & 0x7F), 0, 0])
				p += 2
			elif c <= 0xEC:
				var ln := _vlv(d, p + 2)
				_events.append([t, tr, 8, c & 0x7F, d[p + 1], ln.x])
				p = ln.y
			else:
				break
	_events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if _loop_tick < 0 or _loop_tick >= _end_tick:
		_loop_tick = 0
	_loop_frame = roundi(_loop_tick * _tick_s * RATE)
	_end_frame = roundi(_end_tick * _tick_s * RATE)
	return _end_frame > 0


## A variable-length number at `p` (7 bits a byte, high first): Vector2i(value, after it).
static func _vlv(d: PackedByteArray, p: int) -> Vector2i:
	var v := 0
	for k in 4:
		if p + k >= d.size():
			return Vector2i(v, p + k)
		var b := d[p + k]
		v = (v << 7) | (b & 0x7F)
		if b < 0x80:
			return Vector2i(v, p + k + 1)
	return Vector2i(v, p + 4)


# ---------------------------------------------------------------- playing it

func next_block() -> PackedVector2Array:
	if finished:
		return PackedVector2Array()
	_lock.lock()
	var have := _out.size()
	var done := _done
	_lock.unlock()
	if _at >= _end_frame and done:
		if played >= min_length_s * rate or _end_frame <= _loop_frame:
			finished = true
			return PackedVector2Array()
		_at = _loop_frame
		_passes += 1
	if _at >= have:
		# (The thread is behind: a moment of silence rather than an end.)
		var hush := PackedVector2Array()
		hush.resize(512)
		played += hush.size()
		return hush
	_lock.lock()
	var out := _out.slice(_at, mini(_at + 2048, mini(have, _end_frame)))
	_lock.unlock()
	if _passes > 0 and _at - _loop_frame < _tail.size():
		for i in out.size():
			var k := _at - _loop_frame + i
			if k >= _tail.size():
				break
			out[i] += _tail[k]
	_at += out.size()
	played += out.size()
	return out


# ---------------------------------------------------------------- the synthesiser (thread)

## Renders the song start to end (and what still sounds after it, the tail) in CHUNK_S steps.
func _render() -> void:
	var voices: Array[Dictionary] = []
	var tracks: Array[Dictionary] = []
	for tr in TRACKS:
		tracks.append({"prog": 0, "vol": 1.0, "pan": 0.5, "bend": 0.0})
	var ev := 0
	var frame := 0
	var chunk := int(CHUNK_S * RATE)
	while frame < _end_frame:
		var to := mini(frame + chunk, _end_frame)
		var buf := PackedVector2Array()
		buf.resize(to - frame)
		var at := frame
		while at < to:
			# Events due before the next block.
			var block_end := mini(at + BLOCK, to)
			while ev < _events.size() and int(_events[ev][0] * _tick_s * RATE) < block_end:
				_event(_events[ev], tracks, voices, int(_events[ev][0] * _tick_s * RATE))
				ev += 1
			_mix(voices, buf, at - frame, block_end - at, at)
			at = block_end
		_lock.lock()
		_out.append_array(buf)
		_lock.unlock()
		frame = to
	# The tail: up to 2 s more of whatever is still sounding.
	var tail := PackedVector2Array()
	tail.resize(2 * RATE)
	for v in voices:
		v.off = mini(v.off, _end_frame)
	var at := 0
	while at < tail.size() and not voices.is_empty():
		_mix(voices, tail, at, mini(BLOCK, tail.size() - at), _end_frame + at)
		at += BLOCK
	tail.resize(at)
	_lock.lock()
	_tail = tail
	_done = true
	_lock.unlock()


func _event(e: Array, tracks: Array[Dictionary], voices: Array[Dictionary], at: int) -> void:
	var t: Dictionary = tracks[e[1]]
	match e[2]:
		3:
			t.prog = e[3]
		4:
			t.vol = e[3] / 127.0
		5:
			t.pan = e[3] / 127.0
		7:
			t.bend = clampf((e[3] - 0x3000) / 4096.0, -1.0, 1.0) * BEND_RANGE
			for v in voices:
				if v.track == e[1]:
					v.step = _step(v.note, v.root, t.bend)
		8:
			var r := _region(t.prog, e[3])
			if r < 0:
				return
			var reg: Dictionary = _regions[r]
			var smp: Array = _sample(r)
			if (smp[0] as PackedFloat32Array).is_empty():
				return
			var pan := clampf(t.pan + (reg.pan - 0.5), 0.0, 1.0)
			var amp: float = GAIN * (e[4] / 127.0) * t.vol * reg.vol
			voices.append({"track": e[1], "note": e[3], "root": reg.root, "data": smp[0], "loop": smp[1],
				"pos": 0.0, "step": _step(e[3], reg.root, t.bend),
				"gl": amp * minf(1.0, 2.0 * (1.0 - pan)), "gr": amp * minf(1.0, 2.0 * pan),
				"off": at + roundi(e[5] * _tick_s * RATE), "adsr1": reg.adsr1, "adsr2": reg.adsr2,
				"phase": 0, "level": 0.0})


func _step(note: int, root: int, bend: float) -> float:
	return pow(2.0, (note - root + bend) / 12.0) * SPU_RATE / RATE


## The instrument's region for `note`, or -1.
func _region(prog: int, note: int) -> int:
	if prog < 0 or prog >= _programs.size():
		return -1
	for r in _programs[prog]:
		if r < _regions.size() and note >= _regions[r].lo and note <= _regions[r].hi:
			return r
	return -1


## Region `r`'s sample decoded: [samples (-1..1), loop start or -1].
func _sample(r: int) -> Array:
	if _decoded.has(r):
		return _decoded[r]
	const F0 := [0, 60, 115, 98, 122]
	const F1 := [0, 0, -52, -55, -60]
	var d := _ins
	var p: int = _samples_at + _regions[r].addr
	var out := PackedFloat32Array()
	var loop := -1
	var s1 := 0
	var s2 := 0
	var frames := 0
	while p + 16 <= d.size() and frames < 20000:
		var pred := mini(d[p] >> 4, 4)
		var shift := d[p] & 15
		var flags := d[p + 1]
		if flags & 4 and loop < 0:
			loop = out.size()
		var f0: int = F0[pred]
		var f1: int = F1[pred]
		for i in 28:
			var t := ((d[p + 2 + (i >> 1)] >> ((i & 1) * 4)) & 15) << 12
			if t & 0x8000:
				t -= 0x10000
			var v := clampi((t >> shift) + ((s1 * f0 + s2 * f1 + 32) >> 6), -32768, 32767)
			s2 = s1
			s1 = v
			out.append(v / 32768.0)
		p += 16
		frames += 1
		if flags & 1 and frames > 1:
			if not flags & 2:
				loop = -1   # (an end without repeat: a one-shot)
			break
	_decoded[r] = [out, loop]
	return _decoded[r]


## Adds `n` frames of every voice into `buf` at `at` (song frame `song_at`), its envelope held
## over the block; drops the voices that have died away.
func _mix(voices: Array[Dictionary], buf: PackedVector2Array, at: int, n: int, song_at: int) -> void:
	var k := voices.size() - 1
	while k >= 0:
		var v: Dictionary = voices[k]
		if v.phase < 3 and song_at >= v.off:
			v.phase = 3
		var env := _envelope(v, n * 2)   # (the sound chip's envelope steps at 44.1 kHz)
		var data: PackedFloat32Array = v.data
		var size := data.size()
		var loop: int = v.loop
		var pos: float = v.pos
		var step: float = v.step
		var gl: float = v.gl * env
		var gr: float = v.gr * env
		var dead: bool = v.phase == 4
		for i in n:
			var ip := int(pos)
			if ip >= size - 1:
				if loop < 0 or loop >= size - 2:
					dead = true
					break
				pos = loop + fmod(pos - loop, float(size - 1 - loop))
				ip = int(pos)
			var s := lerpf(data[ip], data[ip + 1], pos - ip)
			buf[at + i] += Vector2(s * gl, s * gr)
			pos += step
		v.pos = pos
		if dead:
			voices.remove_at(k)
		k -= 1


## The voice's level (0..1) after `ticks` more of its ADSR (psx-spx's rules, a block at a
## time; the decay's and release's rates are 4 and 5 bits of a 7-bit rate's top: their shift): attack up to full, decay to the sustain level, sustain, and from its note's end
## release to nothing (phase 4: gone).
func _envelope(v: Dictionary, ticks: int) -> float:
	var a1: int = v.adsr1
	var a2: int = v.adsr2
	var level: float = v.level * 32767.0
	match v.phase:
		0:
			level = _env_step(level, (a1 >> 15) & 1, false, (a1 >> 10) & 0x1F, 7 - ((a1 >> 8) & 3), ticks)
			if level >= 32767.0:
				level = 32767.0
				v.phase = 1
		1:
			var sustain := ((a1 & 0xF) + 1) * 2048.0
			level = _env_step(level, 1, true, (a1 >> 4) & 0xF, -8, ticks)
			if level <= sustain:
				level = sustain
				v.phase = 2
		2:
			var dec := (a2 >> 14) & 1 == 1
			var st := (a2 >> 6) & 3
			level = _env_step(level, (a2 >> 15) & 1, dec, (a2 >> 8) & 0x1F, -8 + st if dec else 7 - st, ticks)
		3:
			level = _env_step(level, (a2 >> 5) & 1, true, a2 & 0x1F, -8, ticks)
			if level <= 16.0:
				level = 0.0
				v.phase = 4
	v.level = clampf(level, 0.0, 32767.0) / 32767.0
	return v.level


## `ticks` of one envelope phase: every 1 << (shift - 11) ticks the level moves by
## step << (11 - shift); exponential falls scale that by the level, exponential rises go a
## quarter as fast above 0x6000.
static func _env_step(level: float, exp_mode: int, falling: bool, shift: int, step: int, ticks: int) -> float:
	var per_tick := float(step << maxi(0, 11 - shift)) / float(1 << maxi(0, shift - 11))
	if exp_mode and falling:
		return level * pow(maxf(1.0 + per_tick / 32768.0, 0.0), ticks)
	if exp_mode and not falling and level > 0x6000:
		per_tick *= 0.25
	return level + per_tick * ticks

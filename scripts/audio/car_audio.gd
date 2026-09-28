class_name CarAudio
extends AudioStreamPlayer3D
## Synthesised car sounds: engine (harmonics locked to rpm), tyre squeal
## (band-limited noise) and, for cops, a two-tone siren. Each is a short loop
## synthesised once and shared by every car; per frame only pitch and volume
## change, so the cost doesn't grow with the sample rate or the number of cars.

const RATE := 22050
## Firing frequency the engine loop is baked at; pitch_scale moves it to the car's rpm.
const ENGINE_BASE_HZ := 100.0
const ENGINE_PEAK := 0.47  # loudest engine level (full throttle); volume is relative to this

var car: Car
var siren := false
var _skid: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _base_db := 0.0
var _vol := 0.0

static var _engine_loop: AudioStreamWAV
static var _skid_loop: AudioStreamWAV
static var _siren_loop: AudioStreamWAV


func _ready() -> void:
	car = get_parent() as Car
	_bake()
	_base_db = volume_db
	stream = _engine_loop
	unit_size = 12.0
	max_distance = 250.0
	_skid = _child_player(_skid_loop)
	_siren = _child_player(_siren_loop)
	play()


func _child_player(s: AudioStreamWAV) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.volume_db = _base_db
	p.bus = bus
	add_child(p)
	return p


func _process(dt: float) -> void:
	if car == null:
		return
	var f := car.rpm / 60.0 * 2.0   # firing frequency (4-stroke V8-ish)
	pitch_scale = maxf(f / ENGINE_BASE_HZ, 0.05)
	var target_vol := 0.22 + clampf(car.throttle, 0.0, 1.0) * 0.25
	# Same smoothing as a per-sample lerp of 0.002 at RATE: settles in ~20 ms.
	_vol = lerpf(_vol, target_vol, 1.0 - exp(-dt * RATE * 0.002))
	volume_db = _base_db + linear_to_db(_vol / ENGINE_PEAK)

	var skid := clampf(car.slip * 1.6 - 0.25, 0.0, 1.0) if car.grounded_wheels > 0 and absf(car.speed) > 4.0 else 0.0
	_set_level(_skid, skid)
	_set_level(_siren, 1.0 if siren else 0.0)


func _set_level(p: AudioStreamPlayer3D, level: float) -> void:
	if level <= 0.001:
		if p.playing:
			p.stop()
		return
	p.volume_db = _base_db + linear_to_db(level)
	if not p.playing:
		p.play()


static func _bake() -> void:
	if _engine_loop:
		return
	# Engine: a soft sawtooth plus sub-harmonic gives a throaty note. The sub-harmonic
	# repeats every 2 firing periods, so a whole number of those loops seamlessly.
	var period := int(RATE / (ENGINE_BASE_HZ * 0.5))
	var eng := PackedFloat32Array()
	for i in period * 4:
		var ph := fmod(i * ENGINE_BASE_HZ / RATE, 1.0)
		var ph2 := fmod(i * ENGINE_BASE_HZ * 0.5 / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		eng.append((saw * 0.55 + sin(ph2 * TAU) * 0.45 + sin(ph * TAU * 2.0) * 0.15) * ENGINE_PEAK)
	_engine_loop = _wav(eng)

	# Tyre squeal: band-passed noise, one second of it.
	var sk := PackedFloat32Array()
	var lp := 0.0
	var bp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in RATE:
		lp += (rng.randf() * 2.0 - 1.0 - lp) * 0.35
		bp += (lp - bp) * 0.08
		sk.append((lp - bp) * 0.9)
	_skid_loop = _wav(sk)

	# Siren: 0.6 s at 740 Hz then 0.6 s at 590 Hz, both whole numbers of cycles.
	var sr := PackedFloat32Array()
	var sp := 0.0
	for i in int(RATE * 1.2):
		var tone := 740.0 if i < RATE * 0.6 else 590.0
		sp = fmod(sp + tone / RATE, 1.0)
		sr.append((0.5 - absf(sp - 0.5)) * 0.8 - 0.2)
	_siren_loop = _wav(sr)


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w

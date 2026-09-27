class_name CarAudio
extends AudioStreamPlayer3D
## Synthesised car sounds mixed into one generator: engine (harmonics locked
## to rpm), tyre squeal (band-limited noise) and, for cops, a two-tone siren.

const RATE := 22050.0

var car: Car
var siren := false
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _siren_phase := 0.0
var _siren_t := 0.0
var _noise_lp := 0.0
var _noise_bp := 0.0
var _vol := 0.0


func _ready() -> void:
	car = get_parent() as Car
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	unit_size = 12.0
	max_distance = 250.0
	play()
	_pb = get_stream_playback()


func _process(_dt: float) -> void:
	if _pb == null or car == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var rpm := car.rpm
	var load := clampf(car.throttle, 0.0, 1.0)
	var f := rpm / 60.0 * 2.0   # firing frequency (4-stroke V8-ish)
	var inc := f / RATE
	var inc2 := f * 0.5 / RATE
	var skid := clampf(car.slip * 1.6 - 0.25, 0.0, 1.0) if car.grounded_wheels > 0 and absf(car.speed) > 4.0 else 0.0
	var target_vol := 0.22 + load * 0.25
	for i in frames:
		_vol = lerpf(_vol, target_vol, 0.002)
		_phase = fmod(_phase + inc, 1.0)
		_phase2 = fmod(_phase2 + inc2, 1.0)
		# A soft sawtooth plus sub-harmonic gives a throaty engine note.
		var saw := _phase * 2.0 - 1.0
		var s := (saw * 0.55 + sin(_phase2 * TAU) * 0.45 + sin(_phase * TAU * 2.0) * 0.15) * _vol
		if skid > 0.0:
			var n := randf() * 2.0 - 1.0
			_noise_lp += (n - _noise_lp) * 0.35
			_noise_bp += (_noise_lp - _noise_bp) * 0.08
			s += (_noise_lp - _noise_bp) * skid * 0.9
		if siren:
			_siren_t += 1.0 / RATE
			var tone := 740.0 if fmod(_siren_t, 1.2) < 0.6 else 590.0
			_siren_phase = fmod(_siren_phase + tone / RATE, 1.0)
			s += (0.5 - absf(_siren_phase - 0.5)) * 0.8 - 0.2
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))

class_name CarAudio
extends AudioStreamPlayer3D
## A car's sounds. With the game's data they're its own: the engine from the banks in its
## car.viv, and tyres, scraping, crashes, the horn, road noise and the siren from the shared
## banks (GameSounds). Without, they're synthesised: engine harmonics locked to rpm, tyre
## squeal (band-limited noise) and a two-tone siren, each a short loop made once and shared
## by every car; per frame only pitch and volume change.
##
## The engine, as the games play it:
## - High Stakes (careng.bnk with careng.ctb and .ltb, the car being driven): up to 16 loops,
##   8 for cruising (off the throttle, .ctb) and 8 under load (.ltb). Each table gives its
##   patch and a volume for each of 512 engine speeds (rpm / redline x 416), so recordings
##   at different rpm fade into one another as it revs; the throttle crossfades the two
##   sets, and patches 64 and up (the exhaust) are mixed against the rest (the engine
##   itself). All play at one pitch, 1.25 x (rpm / redline + 0.2) (AudioEng_Set/Update).
## - NFS3 (car.bnk), and every car the camera isn't on (ocar.bnk, ocareng.bnk): patch 0 is the
##   engine, one loop (with, in NFS3, a thin whine layered on) at that same pitch. NFS3's
##   car.bnk adds patch 1, the engine off the throttle, crossfaded with it.
## Patch 3 of the same bank is the car's horn. Traffic, whose car files have no banks, uses
## the shared genocar.bnk or otruck.bnk (engine 0, horn 1). An upshift drops the engine to
## its off-throttle sound until the new gear takes up (AudioCmn_CheckState's gear-shift dip).
## - Porsche Unleashed: the car being driven has High Stakes' tabled engine (Nfs5Car); the
##   others, traffic included, loop their set's engine (ocar.bnk) and exhaust (ocarex.bnk)
##   together. Its cars slide, knock, scrape and hoot with its own snd_coll.bnk (GameSounds.pu).
## - Hot Pursuit 2: the car being driven has the tabled engine too, its twelve recordings
##   (load and coast, engine and exhaust, three rpm each) put together by Nfs6Car; the cars
##   around you crossfade their oppbnk.viv bank's patch 1 (on the throttle) with 0 (off);
##   traffic loops genopp.bnk. Each has its own horn (horn.bnk), and they use HP2's gen.bnk
##   and siren (GameSounds.hp2).

const RATE := 22050
## Firing frequency the engine loop is baked at; pitch_scale moves it to the car's rpm.
const ENGINE_BASE_HZ := 100.0
const ENGINE_PEAK := 0.47  # loudest engine level (full throttle); volume is relative to this
const ESP_SCALE := 416.0   # engine speed table index at the redline (AudioEng timbreScale)
## Chase-camera mix of the exhaust (patches 64+) against the engine, 0..128 (outCarExhaust).
const EXHAUST_MIX := 43
const HORN_PATCH := 3
const DECEL_PATCH := 1
const TRUCK_MASS := 3000.0   # kg: traffic this heavy gets the truck engine
const OTHERS_DB := -4.0    # the cars the camera isn't on, a little under the one it is

var car: Car
var siren := false
var _skid: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _road: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _base_db := 0.0
var _vol := 0.0
var _gas := 0.0               # the throttle as the sound hears it: quick to rise, slower to fall
var _built_for: Car
var _built_player := false
## Sampled engine loops: {player, table (PackedByteArray of 512 signed volumes, or empty),
## load (1 under load, 0 cruising, -1 either), exhaust (bool), gain, tune}
var _voices: Array[Dictionary] = []
var _crossfade := false      # the engine has off-throttle loops to fade the load ones against
var _sounds: GameSounds
var _gen: EaBnk              # the shared bank this car's tyres, knocks, road and horn come from
var _pu_gen := false         # _gen is Porsche Unleashed's (GameSounds.PU_PATCHES)
var _hp2_gen := false        # _gen is Hot Pursuit 2's (GameSounds.HP2_IMPACTS)
var _skid_patch := -1
var _effects: CarEffects
var _crash_cool := 0.0
var _last_gear := 1
var _hushed := false         # stopped while the car is far off
var _shift_t := 0.0          # s left of an upshift, engine off the load

static var _engine_loop: AudioStreamWAV
static var _skid_loop: AudioStreamWAV
static var _siren_loop: AudioStreamWAV


func _ready() -> void:
	if car == null:
		car = get_parent() as Car
	_bake()
	_sounds = GameSounds.shared()
	_base_db = volume_db
	bus = Game.BUS_SFX
	unit_size = 12.0
	max_distance = 250.0
	_skid = _child_player(_skid_loop)
	_siren = _child_player(_siren_loop)
	_scrape = _child_player(null)
	_road = _child_player(null)
	_horn = _child_player(null)


func _child_player(s: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.volume_db = _base_db
	p.bus = bus
	add_child(p)
	return p


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car != _built_for or car.is_player != _built_player:
		_build()
	# Out past the detail range (Car.far): silent, and no work.
	if car.far and not car.is_player:
		if not _hushed:
			_hushed = true
			stop()
			for c in get_children():
				if c is AudioStreamPlayer3D:
					c.stop()
		return
	if _hushed:
		_hushed = false
		if stream:
			play()
	# Quick to open, slower to close (PlayersRampedGasLevel: half the gap a tick up, an eighth down).
	if car.gear > _last_gear and _last_gear >= 1:
		_shift_t = car.shift_delay
	_last_gear = car.gear
	_shift_t = maxf(_shift_t - dt, 0.0)
	var g := clampf(car.throttle, 0.0, 1.0) if _shift_t <= 0.0 else 0.0
	_gas = lerpf(_gas, g, 1.0 - exp(-dt * (40.0 if g > _gas else 8.0)))
	if _voices.is_empty():
		_synth_engine(dt)
	else:
		_sampled_engine()
	_tyres()
	_body(dt)
	_set_level(_siren, 1.0 if siren else 0.0)
	_horn_update()


# ------------------------------------------------------------------ engine

func _build() -> void:
	_built_for = car
	_built_player = car.is_player
	_effects = null
	for v in _voices:
		v.player.queue_free()
	_voices.clear()
	if _horn.playing:
		_horn.stop()
	_horn.stream = null
	var data := car.car_data
	# Porsche Unleashed's and Hot Pursuit 2's cars with their game's sounds; the rest with
	# NFS3's or High Stakes' if there.
	_hp2_gen = _sounds != null and _sounds.hp2 != null and (data is Nfs6Car or (_sounds.gen == null and _sounds.pu == null))
	_pu_gen = not _hp2_gen and _sounds != null and _sounds.pu != null and (data is Nfs5Car or _sounds.gen == null)
	_gen = _sounds.hp2 if _hp2_gen else _sounds.pu if _pu_gen else _sounds.gen if _sounds else null
	_siren.stop()
	_siren.stream = _siren_stream(data)
	_skid_patch = -1
	_skid.stop()
	_skid.stream = _skid_loop
	_scrape.stream = _gen_stream(GameSounds.SCRAPE)
	_road.stream = _gen_stream(GameSounds.ROAD)
	var bank: EaBnk = null
	if data != null and data.has_method("sound_bank"):
		if car.is_player:
			bank = data.sound_bank("careng.bnk")
			if bank and not _hs_voices(bank, data):
				bank = null
			if bank == null:
				bank = data.sound_bank("car.bnk")
				if bank:
					_single_voices(bank, true)
		# The simpler engine the games give the cars around you (or the full bank's, if that's all there is).
		for f in ["ocar.bnk", "ocareng.bnk", "car.bnk", "careng.bnk"]:
			if not _voices.is_empty():
				break
			bank = data.sound_bank(f)
			if bank and data is Nfs6Car and f == "ocar.bnk" and not data.traffic:
				_hp2_opponent_voices(bank)
			elif bank:
				_single_voices(bank, false)
				# Porsche Unleashed's: the exhaust's loop beside the engine's.
				if f == "ocar.bnk" and data.sound_bank("ocarex.bnk"):
					_single_voices(data.sound_bank("ocarex.bnk"), false)
	if _voices.is_empty() and _sounds and data != null:
		# Traffic: the shared engines, a truck's for the heavy ones.
		bank = _sounds.traffic_truck if car.mass > TRUCK_MASS and _sounds.traffic_truck else _sounds.traffic_car
		if bank:
			_single_voices(bank, false)
			if bank.stream(1):
				_horn.stream = bank.stream(1)
			bank = null
	# (Porsche Unleashed's engine banks have no horn: its horns are in snd_coll.bnk. Hot
	# Pursuit 2's cars bring theirs apart.)
	var own_horn: EaBnk = data.sound_bank("horn.bnk") if data is Nfs6Car else null
	if own_horn and own_horn.stream(0):
		_horn.stream = own_horn.stream(0)
	elif bank and bank.stream(HORN_PATCH) and not (data is Nfs5Car or data is Nfs6Car):
		_horn.stream = bank.stream(HORN_PATCH)
	elif _horn.stream == null and _pu_gen and car.mass > TRUCK_MASS:
		_horn.stream = _gen.stream(GameSounds.PU_TRUCK_HORN)
	elif _horn.stream == null:
		_horn.stream = _gen_stream(GameSounds.HORN)
	_crossfade = _voices.any(func(v: Dictionary) -> bool: return v.load == 0)
	stream = null if not _voices.is_empty() else _engine_loop
	if stream and not playing:
		play()
	elif stream == null and playing:
		stop()


## High Stakes' tabled engine; false if the car file lacks the tables.
func _hs_voices(bank: EaBnk, data: Object) -> bool:
	var ctb := _engine_table(data.sound_files.get("careng.ctb", PackedByteArray()))
	var ltb := _engine_table(data.sound_files.get("careng.ltb", PackedByteArray()))
	if ctb.is_empty() or ltb.is_empty():
		return false
	for set in [[ctb, 0], [ltb, 1]]:
		for ch: Dictionary in set[0]:
			var patch: int = ch.patch
			if not bank.has(patch) or bank.stream(patch) == null:
				continue
			# The exhaust: patches 64 and up, or Hot Pursuit 2's channels 4.. (its patches run on).
			var exhaust: bool = patch >= 64 or (data is Nfs6Car and ch.channel >= 4)
			_add_voice(bank.stream(patch), ch.table, set[1], exhaust, bank.volume(patch), bank.tune(patch))
	return not _voices.is_empty()


## An engine definition (.ctb / .ltb, AudioEng_tDef): 8 patch numbers at 32 and, at 296
## and 328, 8 offsets (each from its own field) to 512-byte volume and pitch-bend tables.
## Returns [{patch, channel, table}] for the channels in use, or [] if it doesn't parse.
static func _engine_table(d: PackedByteArray) -> Array:
	var out := []
	if d.size() < 360 or d.slice(0, 4).get_string_from_ascii() != "CRDl":
		return out
	for i in 8:
		var patch := d.decode_s8(32 + i)
		if patch < 0:
			continue
		var at := 296 + i * 4
		var t := at + d.decode_s32(at)
		if t < 0 or t + 512 > d.size():
			continue
		out.append({"patch": patch, "channel": i, "table": d.slice(t, t + 512)})
	return out


## NFS3's engine (patch 0, all its layers), and off the throttle patch 1 when `full`.
func _single_voices(bank: EaBnk, full: bool) -> void:
	for l in bank.layer_count(0):
		if bank.stream(0, l):
			_add_voice(bank.stream(0, l), PackedByteArray(), 1 if full else -1, false, bank.volume(0, l), bank.tune(0, l))
	if full and not _voices.is_empty() and bank.stream(DECEL_PATCH) and bank.stream(DECEL_PATCH).loop_mode != AudioStreamWAV.LOOP_DISABLED:
		for l in bank.layer_count(DECEL_PATCH):
			if bank.stream(DECEL_PATCH, l):
				_add_voice(bank.stream(DECEL_PATCH, l), PackedByteArray(), 0, false, bank.volume(DECEL_PATCH, l), bank.tune(DECEL_PATCH, l))
	else:
		# No off-throttle recording: the one loop plays throughout.
		for v in _voices:
			v.load = -1


## Hot Pursuit 2's cars you aren't driving: patch 1 on the throttle, crossfaded with 0 off it.
func _hp2_opponent_voices(bank: EaBnk) -> void:
	for pl in [[1, 1], [0, 0]]:
		if bank.stream(pl[0]):
			_add_voice(bank.stream(pl[0]), PackedByteArray(), pl[1], false, bank.volume(pl[0]), bank.tune(pl[0]))
	if _voices.size() < 2:
		for v in _voices:
			v.load = -1


func _siren_stream(data: Object) -> AudioStream:
	if _sounds == null:
		return _siren_loop
	if data is Nfs6Car and _sounds.hp2_siren and _sounds.hp2_siren.stream(GameSounds.SIREN):
		return _sounds.hp2_siren.stream(GameSounds.SIREN)
	if _sounds.siren and _sounds.siren.stream(GameSounds.SIREN):
		return _sounds.siren.stream(GameSounds.SIREN)
	if _sounds.pu and _sounds.pu.stream(GameSounds.PU_SIREN):
		return _sounds.pu.stream(GameSounds.PU_SIREN)
	if _sounds.hp2_siren and _sounds.hp2_siren.stream(GameSounds.SIREN):
		return _sounds.hp2_siren.stream(GameSounds.SIREN)
	return _siren_loop


func _add_voice(s: AudioStreamWAV, table: PackedByteArray, load: int, exhaust: bool, gain: float, tune: float) -> void:
	var p := _child_player(s)
	p.max_distance = max_distance if car.is_player else 150.0
	_voices.append({"player": p, "table": table, "load": load, "exhaust": exhaust, "gain": gain, "tune": tune})


func _sampled_engine() -> void:
	var ratio := maxf(car.rpm, 0.0) / maxf(car.redline, 1000.0)
	var pitch := clampf(1.25 * (ratio + 0.2), 0.1, 4.0)
	var esp := clampi(int(ratio * ESP_SCALE), 0, 511)
	var gas := _gas
	for v in _voices:
		var level: float = v.gain
		var table: PackedByteArray = v.table
		if not table.is_empty():
			level *= maxf(table.decode_s8(esp), 0) / 127.0
			level *= _xfade(1.0 - EXHAUST_MIX / 128.0) if v.exhaust else _xfade(EXHAUST_MIX / 128.0)
		match v.load:
			1:
				level *= _xfade(gas) if _crossfade else lerpf(0.55, 1.0, gas)
			0:
				level *= _xfade(1.0 - gas)
			_:
				level *= lerpf(0.55, 1.0, gas)
		var p: AudioStreamPlayer3D = v.player
		p.pitch_scale = pitch * v.tune
		_set_level(p, level)


## Equal-power crossfade gain for share `x` (0..1) of the mix.
static func _xfade(x: float) -> float:
	return sin(clampf(x, 0.0, 1.0) * PI * 0.5)


func _synth_engine(dt: float) -> void:
	var f := car.rpm / 60.0 * 2.0   # firing frequency (4-stroke V8-ish)
	pitch_scale = maxf(f / ENGINE_BASE_HZ, 0.05)
	var target_vol := 0.22 + clampf(car.throttle, 0.0, 1.0) * 0.25
	# Same smoothing as a per-sample lerp of 0.002 at RATE: settles in ~20 ms.
	_vol = lerpf(_vol, target_vol, 1.0 - exp(-dt * RATE * 0.002))
	volume_db = _base_db + linear_to_db(_vol / ENGINE_PEAK) + (0.0 if car.is_player else OTHERS_DB)


# ------------------------------------------------------------------ tyres, body, horn

func _tyres() -> void:
	var skid := clampf(car.slip * 1.6 - 0.25, 0.0, 1.0) if car.grounded_wheels > 0 and absf(car.speed) > 4.0 else 0.0
	if _gen:
		var patch := _patch(GameSounds.TYRES_TARMAC)
		if car.off_road > 0.5:
			patch = _patch(GameSounds.TYRES_GRAVEL)
		elif car.surface_grip < 0.95:
			patch = _patch(GameSounds.TYRES_WET)
		if patch != _skid_patch and _gen.stream(patch):
			_skid_patch = patch
			_skid.stop()
			_skid.stream = _gen.stream(patch)
		# The slide bends it up to its bend range (tag 0x0A, semitones) either way.
		var bend := float(_gen.tag(_skid_patch, 0x0A, 4))
		_skid.pitch_scale = pow(2.0, lerpf(-0.5, 0.6, skid) * bend / 12.0)
		skid *= 0.8
	_set_level(_skid, skid)


func _body(dt: float) -> void:
	_crash_cool = maxf(_crash_cool - dt, 0.0)
	if _effects == null:
		for c in car.get_children():
			if c is CarEffects:
				_effects = c
				break
	var scrape := clampf((_effects.scrape_speed - 1.0) / 12.0, 0.0, 1.0) if _effects else 0.0
	if _scrape.stream:
		_scrape.pitch_scale = lerpf(0.85, 1.15, scrape)
		_set_level(_scrape, scrape * 0.9)
	# Road noise for the car the camera is on: louder and higher with speed.
	var road := clampf(absf(car.speed) / 60.0, 0.0, 1.0) if car.is_player and car.grounded_wheels > 0 else 0.0
	if _road.stream:
		_road.pitch_scale = lerpf(0.7, 1.3, road)
		_set_level(_road, road * 0.35)


func _horn_update() -> void:
	if _horn.stream == null:
		return
	if car.horn and not _horn.playing:
		_horn.volume_db = _base_db
		_horn.play()
	elif not car.horn and _horn.playing:
		_horn.stop()


## A crash: one of the impact sounds, heavier the harder it hit.
func _on_crashed(impulse: float) -> void:
	if _crash_cool > 0.0 or _gen == null:
		return
	_crash_cool = 0.12
	var force := clampf(impulse * 4.0, 0.0, 127.0)   # ChooseImpactSample's 0..127 scale
	var patch := GameSounds.IMPACT_LIGHT
	var layer := 0
	if _pu_gen:
		# One of the three, and its layer for how hard (tags 0x01..0x02).
		patch = GameSounds.PU_IMPACTS.pick_random()
		for l in _gen.layer_count(patch):
			if force >= _gen.tag(patch, 0x01, 0, l) and force <= _gen.tag(patch, 0x02, 127, l):
				layer = l
				break
	elif force > 110.0:
		patch = GameSounds.IMPACT_HEAVY
	elif force > 60.0:
		patch = GameSounds.IMPACT_MEDIUM if randf() < 0.5 else GameSounds.IMPACT_WALL
	elif force > 30.0:
		patch = GameSounds.IMPACT_HARD
	# Hot Pursuit 2's: its own crashes, every layer at once.
	var layers := [layer]
	if _hp2_gen:
		patch = GameSounds.HP2_IMPACTS.get(patch, patch)
		layers = range(_gen.layer_count(patch))
	for l: int in layers:
		var s := _gen.stream(patch, l)
		if s == null:
			continue
		# Tag 0x11: a random pitch spread, cents.
		var spread := _gen.tag(patch, 0x11, 0, l) * 0.5
		var pitch := pow(2.0, randf_range(-spread, spread) / 1200.0)
		var gain := clampf(force / 90.0, 0.35, 1.0) * (_gen.volume(patch, l) if _hp2_gen else 1.0)
		GameSounds.play_once(car, s, _base_db + linear_to_db(gain), pitch, bus)


func _enter_tree() -> void:
	var c := get_parent() as Car
	if c and not c.crashed.is_connected(_on_crashed):
		c.crashed.connect(_on_crashed)


func _exit_tree() -> void:
	var c := get_parent() as Car
	if c and c.crashed.is_connected(_on_crashed):
		c.crashed.disconnect(_on_crashed)


## One of the shared sounds (GameSounds' numbers), from this car's bank.
func _gen_stream(id: int) -> AudioStreamWAV:
	return _gen.stream(_patch(id)) if _gen else null


## GameSounds' number `id` in this car's bank.
func _patch(id: int) -> int:
	return GameSounds.PU_PATCHES.get(id, id) if _pu_gen else id


func _set_level(p: AudioStreamPlayer3D, level: float) -> void:
	if level <= 0.004:   # -48 dB: stop it rather than mix silence
		if p.playing:
			p.stop()
		return
	p.volume_db = _base_db + linear_to_db(level) + (0.0 if car.is_player else OTHERS_DB)
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

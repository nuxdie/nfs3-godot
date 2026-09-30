class_name Weather
extends Node3D
## The track's atmosphere as the camera moves round it: the .hrz file's fog regions (fog
## that thickens and changes colour along stretches of track), and with the weather on,
## rain or snow around the camera, lightning and thunder. Rain and snow come and go on the
## track's on / fade off / off / fade on cycle, and on some tracks only fall on part of it.
## They don't fall under bridges or in tunnels (RainCover), and they cost the cars grip
## wherever the road is open to the sky: rain as the road gets wet, snow all the time.

const TICKS_PER_SECOND := 64.0    # the .hrz timings are whole seconds at this rate
## Strikes per roll as a fraction of the file's percentage: taken literally there's a strike
## every few seconds, far more than the original shows.
const LIGHTNING_SCALE := 0.2
const DROPS := [2500, 4000, 6000]   # by Game.quality, near the camera...
const FAR_DROPS := [1500, 3000, 4500]   # ...and out to ~40 m, so it rains over the scenery too
const WET_GRIP := 0.8     # tyre grip on a soaked road...
const SNOW_GRIP := 0.68   # ...and on a snowy one
const WET_TIME := 20.0    # seconds of rain to soak the road
const DRY_TIME := 90.0    # seconds for it to dry once the rain stops
## Render layer bit of the rain and snow, which reflection probes leave out.
const PRECIP_LAYER := 8

var path: TrackPath

var _h: Nfs3Horizon
var _env: Environment
var _track_mat: ShaderMaterial
var _base_fog_color: Color
var _base_fog_density: float
var _base_tint := Vector3.ONE
var _base_bg_energy := 1.0
var _base_ambient_energy := 1.0
var _node := -1
var _fog_color: Color
var _fog_density: float

var _precip: MeshInstance3D
var _mat: ShaderMaterial        # the dense layer round the camera
var _far_precip: MeshInstance3D
var _far_mat: ShaderMaterial    # a sparser, wider one: the chase camera sits right behind the
                                # car, so the near layer alone only ever rains between the two
var _cycle := PackedFloat32Array()   # seconds: on, fading off, off, fading on
var _t := 0.0
var _amount := 0.0
var _last_cam := Vector3.INF
var _cam_vel := Vector3.ZERO
var _snow := false
var _cover: RainCover
var _wet := 0.0            # 0 dry - 1 soaked (always 1 in snow)
var _grip_t := 0.0

var _lightning := false
var _next_roll := 0.0
var _flash := 0.0
var _flash_t := 0.0
var _thunder_in := -1.0
var _thunder_vol := 0.0
var _rain_audio: AudioStreamPlayer
var _rain_gain := 1.0     # the game's rain recording is ~12 dB under the synthesised hiss
var _thunder_audio: AudioStreamPlayer


## `h` is the track's horizon (null on the procedural track: plain rain, no regions).
## `track_root` holds the track's meshes, for working out what's under cover.
func setup(h: Nfs3Horizon, p_path: TrackPath, env: Environment, track_mat: ShaderMaterial,
		track_root: Node3D) -> void:
	_h = h
	path = p_path
	_env = env
	_track_mat = track_mat
	_base_fog_color = env.fog_light_color
	_base_fog_density = env.fog_density
	_fog_color = _base_fog_color
	_fog_density = _base_fog_density
	_base_bg_energy = env.background_energy_multiplier
	_base_ambient_energy = env.ambient_light_energy
	if track_mat:
		var t: Variant = track_mat.get_shader_parameter("night_tint")
		_base_tint = t if t is Vector3 else Vector3.ONE
	if not Game.weather:
		return
	var kind := h.precip if h else Nfs3Horizon.Precip.RAIN
	if kind == Nfs3Horizon.Precip.NONE:
		kind = Nfs3Horizon.Precip.RAIN
	for k in (h.precip_cycle if h else PackedInt32Array()):
		_cycle.append(k / TICKS_PER_SECOND)
	_snow = kind == Nfs3Horizon.Precip.SNOW
	_wet = 1.0   # the race starts with the rain already on (the cycle begins "on")
	_build_precip(_snow)
	_cover = RainCover.new()
	add_child(_cover)
	_cover.built.connect(_on_cover_built)
	_cover.build(track_root, path, preload("res://shaders/track_additive.gdshader"))
	if h and h.lightning_chance > 0 and h.lightning_ticks > 0:
		_lightning = true
		_next_roll = h.lightning_ticks / TICKS_PER_SECOND
	_build_audio(kind == Nfs3Horizon.Precip.SNOW)


## How wet the road looks, 0 dry - 1 soaked (snow isn't wet).
func road_wetness() -> float:
	return 0.0 if _snow or _mat == null else _wet


## The fog density for an .hrz percentage.
static func fog_density(percent: float) -> float:
	return 0.0003 + percent * 0.00006


func _build_precip(snow: bool) -> void:
	var fsh := Fsh.load_file(Game.find_ci(Game.data_root, "gamedata/render/pc/weather.fsh")) \
		if Game.has_game_data() else null
	# DRP1 is a falling streak, DRP2 a soft round flake (the rest are windscreen splats).
	var img: Image = fsh.by_name.get("DRP2" if snow else "DRP1") if fsh else null
	if img == null:
		img = _fallback_sprite(snow)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/precipitation.gdshader")
	_mat.set_shader_parameter("sprite", ImageTexture.create_from_image(img))
	var wind := Vector2.ZERO
	if _h:
		# The clouds' wind, gentler down here.
		wind = Vector2.from_angle(deg_to_rad(_h.wind_dir)) * _h.wind_mph * 0.447 * 0.3
	_mat.set_shader_parameter("wind", wind)
	if snow:
		_mat.set_shader_parameter("fall_speed", 1.8)
		_mat.set_shader_parameter("wobble", 0.35)
		_mat.set_shader_parameter("width", 0.11)
		_mat.set_shader_parameter("min_length", 0.11)
		_mat.set_shader_parameter("streak_time", 0.008)
		_mat.set_shader_parameter("opacity", 2.5)
		_mat.set_shader_parameter("box", Vector3(26, 12, 26))
	else:
		_mat.set_shader_parameter("fall_speed", 10.0)
		_mat.set_shader_parameter("opacity", 0.9)
		_mat.set_shader_parameter("width", 0.025)
		_mat.set_shader_parameter("min_length", 0.5)
		_mat.set_shader_parameter("streak_time", 0.02)
		_mat.set_shader_parameter("box", Vector3(24, 12, 24))
	var bright := 0.3 if Game.night else 0.72
	if snow:
		bright = 0.35 if Game.night else 0.95
	_mat.set_shader_parameter("tint", Vector3(bright, bright * 1.02, bright * 1.06))

	# Farther drops: bigger and longer so they still read at 30-40 m.
	_far_mat = _mat.duplicate() as ShaderMaterial
	if snow:
		_far_mat.set_shader_parameter("box", Vector3(70, 18, 70))
		_far_mat.set_shader_parameter("box_below", 8.0)
		_far_mat.set_shader_parameter("width", 0.16)
		_far_mat.set_shader_parameter("min_length", 0.16)
		_far_mat.set_shader_parameter("opacity", 2.0)
	else:
		_far_mat.set_shader_parameter("box", Vector3(90, 20, 90))
		_far_mat.set_shader_parameter("box_below", 8.0)
		_far_mat.set_shader_parameter("width", 0.035)
		_far_mat.set_shader_parameter("min_length", 1.2)
		_far_mat.set_shader_parameter("opacity", 1.8)
	# Last in the transparent pass: the scenery is drawn there too, and sorting by distance
	# (this mesh's bounds are centred on the world origin) put it over the rain.
	_mat.render_priority = 100
	_far_mat.render_priority = 100
	_precip = _layer(_mat, DROPS[Game.quality], 3)
	_far_precip = _layer(_far_mat, FAR_DROPS[Game.quality], 4)


## `n` drops drawn with `mat`: one quad each, its corners all at the drop's random seed.
func _layer(mat: ShaderMaterial, n: int, seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf())
		var extra := Vector2(rng.randf(), rng.randf())   # show threshold, speed variation
		for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(seed)
			uvs.append(c)
			uv2s.append(extra)
		var b := i * 4
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	# The shader moves every vertex next to the camera; never cull it.
	mesh.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = PRECIP_LAYER
	add_child(mi)
	return mi


func _on_cover_built() -> void:
	_mat.set_shader_parameter("cover", _cover.texture)
	_mat.set_shader_parameter("cover_rect", Vector4(_cover.rect.position.x, _cover.rect.position.y,
		_cover.rect.size.x, _cover.rect.size.y))
	_mat.set_shader_parameter("cover_y_min", _cover.y_min)
	_mat.set_shader_parameter("cover_y_range", _cover.y_range)
	_mat.set_shader_parameter("has_cover", true)
	for k in ["cover", "cover_rect", "cover_y_min", "cover_y_range", "has_cover"]:
		_far_mat.set_shader_parameter(k, _mat.get_shader_parameter(k))
	# The road stays dry under cover too.
	if _track_mat:
		for k in ["cover", "cover_rect", "cover_y_min", "cover_y_range", "has_cover"]:
			_track_mat.set_shader_parameter(k, _mat.get_shader_parameter(k))


static func _fallback_sprite(snow: bool) -> Image:
	var w := 8
	var h := 8 if snow else 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5).length() * 2.0
			var v := clampf(1.0 - d, 0.0, 1.0) if snow else clampf(1.0 - absf(x + 0.5 - w * 0.5) / (w * 0.5), 0.0, 1.0) * (y + 0.5) / h
			img.set_pixel(x, y, Color(v, v, v))
	return img


func _build_audio(snow: bool) -> void:
	var bank := GameSounds.shared()
	var rain := bank.rain if bank else null
	if not snow:
		_rain_audio = AudioStreamPlayer.new()
		# The game's rain on the roof if there's one, else a synthesised hiss.
		var game_rain := rain.stream(GameSounds.RAIN) if rain else null
		_rain_audio.stream = game_rain if game_rain else _rain_loop()
		_rain_gain = 4.0 if game_rain else 1.0
		_rain_audio.volume_db = -80.0
		_rain_audio.bus = Game.BUS_SFX
		add_child(_rain_audio)
		_rain_audio.play()
	if _lightning:
		_thunder_audio = AudioStreamPlayer.new()
		_thunder_audio.bus = Game.BUS_SFX
		var claps := AudioStreamRandomizer.new()
		if rain:
			for patch: int in GameSounds.THUNDER:
				if rain.stream(patch):
					claps.add_stream(-1, rain.stream(patch))
		_thunder_audio.stream = claps if claps.streams_count > 0 else _thunder()
		add_child(_thunder_audio)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or path == null:
		return
	var eye := cam.global_position
	_node = path.closest(eye, _node)
	_update_fog(dt)
	if _mat:
		_update_precip(dt, eye)
	if _lightning:
		_update_lightning(dt)
	_apply()


# ------------------------------------------------------------------ fog

func _update_fog(dt: float) -> void:
	var col := _base_fog_color
	var dens := _base_fog_density
	if _h:
		for r in _h.fog_regions:
			var s: Array = r.slices
			var n := path.size()
			var into := posmod(_node - s[0], n)
			var span := posmod(s[2] - s[0], n)
			if span == 0 or into > span:
				continue
			var mid := posmod(s[1] - s[0], n)
			var i := 0 if into <= mid else 1
			var a: float = 0.0 if i == 0 else mid
			var b: float = mid if i == 0 else span
			var f := clampf((into - a) / maxf(b - a, 1.0), 0.0, 1.0)
			col = (r.colors[i] as Color).lerp(r.colors[i + 1], f)
			dens = fog_density(lerpf(r.densities[i], r.densities[i + 1], f))
			break
	# Ease toward it: a respawn or region edge shouldn't snap the fog.
	var k := 1.0 - exp(-dt * 2.0)
	_fog_color = _fog_color.lerp(col, k)
	_fog_density = lerpf(_fog_density, dens, k)


# ------------------------------------------------------------------ rain and snow

func _update_precip(dt: float, eye: Vector3) -> void:
	_t += dt
	var target := _cycle_amount(_t) * _region_amount(_node)
	_amount = move_toward(_amount, target, dt * 0.5)
	var cam := get_viewport().get_camera_3d() as ChaseCamera
	if cam and cam.target:
		# The car's motion, not the camera's: orbiting with the mouse swings the camera round
		# the car, and that shouldn't tilt the streaks.
		_cam_vel = _cam_vel.lerp(cam.target.linear_velocity, 1.0 - exp(-dt * 12.0))
	elif _last_cam != Vector3.INF and dt > 0.0:
		var v := (eye - _last_cam) / dt
		# A respawn or camera switch jumps: ignore it.
		if v.length() < 120.0:
			_cam_vel = _cam_vel.lerp(v, 1.0 - exp(-dt * 12.0))
	_last_cam = eye
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("amount", _amount)
		m.set_shader_parameter("cam_pos", eye)
		m.set_shader_parameter("cam_vel", _cam_vel)
	_precip.visible = _amount > 0.001
	_far_precip.visible = _precip.visible
	if _rain_audio:
		# Muffled in a tunnel or under a bridge.
		var under := 0.25 if _cover.covered(eye, 2.0) else 1.0
		_rain_audio.volume_db = linear_to_db(maxf(_amount * 0.35 * under * _rain_gain, 0.0001))


func _cycle_amount(t: float) -> float:
	if _cycle.size() < 4:
		return 1.0
	var total := _cycle[0] + _cycle[1] + _cycle[2] + _cycle[3]
	if total <= 0.0:
		return 1.0
	t = fmod(t, total)
	if t < _cycle[0]:
		return 1.0
	t -= _cycle[0]
	if t < _cycle[1]:
		return 1.0 - t / _cycle[1]
	t -= _cycle[1]
	if t < _cycle[2]:
		return 0.0
	return (t - _cycle[2]) / maxf(_cycle[3], 0.001)


## 1 on the stretch the weather covers, ramping over `precip_fade` nodes at its ends.
func _region_amount(n: int) -> float:
	if _h == null or _h.precip_start == _h.precip_end:
		return 1.0
	var size := path.size()
	var span := posmod(_h.precip_end - _h.precip_start, size)
	var into := posmod(n - _h.precip_start, size)
	if into > span:
		return 0.0
	var fade := maxf(_h.precip_fade, 1.0)
	return clampf(minf(into, span - into) / fade, 0.0, 1.0)


# ------------------------------------------------------------------ grip

func _physics_process(dt: float) -> void:
	if _mat == null:
		return
	if not _snow:
		_wet = move_toward(_wet, _amount, dt / (WET_TIME if _amount > _wet else DRY_TIME))
	# Only a few times a second: the road doesn't change under a car much faster.
	_grip_t -= dt
	if _grip_t > 0.0:
		return
	_grip_t = 0.1
	var open := lerpf(1.0, SNOW_GRIP if _snow else WET_GRIP, _wet)
	for c in get_parent().get_children():
		if c is Car:
			c.surface_grip = 1.0 if _cover.covered(c.global_position) else open


# ------------------------------------------------------------------ lightning

func _update_lightning(dt: float) -> void:
	_next_roll -= dt
	# Only while it's actually pouring.
	if _next_roll <= 0.0:
		# Reset rather than add: a long frame (the level loading) mustn't bank up rolls.
		_next_roll = _h.lightning_ticks / TICKS_PER_SECOND
		if _amount > 0.5 and randf() * 100.0 < _h.lightning_chance * LIGHTNING_SCALE:
			_flash_t = 0.0
			_flash = 1.0
			# Closer strikes are louder and follow sooner.
			var near := randf()
			_thunder_in = lerpf(2.5, 0.3, near)
			_thunder_vol = lerpf(-14.0, -2.0, near)
	if _flash > 0.0:
		_flash_t += dt
		# A bright strike, a short gap and a weaker re-strike, then dark.
		var f := 0.0
		if _flash_t < 0.08:
			f = 1.0
		elif _flash_t > 0.16 and _flash_t < 0.22:
			f = 0.6
		elif _flash_t >= 0.22:
			f = 0.6 * exp(-(_flash_t - 0.22) * 10.0)
		_flash = f if _flash_t < 1.0 else 0.0
	if _thunder_in >= 0.0:
		_thunder_in -= dt
		if _thunder_in < 0.0 and _thunder_audio:
			_thunder_audio.volume_db = _thunder_vol
			_thunder_audio.pitch_scale = randf_range(0.8, 1.1)
			_thunder_audio.play()


var _applied_flash := 0.0


func _apply() -> void:
	var f := _flash
	# Only when something changed: each set is a change to the environment on the render side.
	var fog := _fog_color.lerp(Color(0.85, 0.88, 1.0), f * 0.6)
	if fog != _env.fog_light_color:
		_env.fog_light_color = fog
	if _fog_density != _env.fog_density:
		_env.fog_density = _fog_density
	if not _lightning or (f == 0.0 and _applied_flash == 0.0):
		return
	_applied_flash = f
	# The background multiplier doesn't re-render the sky's radiance map, so it's cheap.
	_env.background_energy_multiplier = _base_bg_energy * (1.0 + f * 2.0)
	_env.ambient_light_energy = _base_ambient_energy * (1.0 + f * 3.0)
	if _track_mat:
		_track_mat.set_shader_parameter("night_tint", _base_tint + Vector3.ONE * f * 0.7)


# ------------------------------------------------------------------ sound

const RATE := 22050

## Rain on the roof: two bands of noise, one second, looped.
static func _rain_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var s := PackedFloat32Array()
	var lp := 0.0
	var lp2 := 0.0
	for i in RATE:
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.5
		lp2 += (w - lp2) * 0.05
		# Occasional louder drops.
		var tick := (rng.randf() * 2.0 - 1.0) * 0.8 if rng.randf() < 0.002 else 0.0
		s.append((lp - lp2) * 0.5 + lp2 * 0.6 + tick)
	var wav := _wav(s)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = s.size()
	return wav


## A crack and a long rolling rumble: brown noise under a swelling, decaying envelope.
static func _thunder() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(RATE * 4.0)
	var s := PackedFloat32Array()
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		brown = clampf(brown + w * 0.04, -1.0, 1.0) * 0.998
		lp += (w - lp) * 0.3
		var crack := lp * exp(-t * 18.0) * 0.8
		var roll := 1.0 + 0.5 * sin(t * 5.0) * sin(t * 1.7)
		var env := minf(t / 0.15, 1.0) * exp(-t * 0.9) * roll
		s.append(clampf(brown * env * 2.2 + crack, -1.0, 1.0))
	return _wav(s)


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w

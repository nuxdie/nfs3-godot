class_name CarEffects
extends Node3D
## Visual feedback from a car's tyres and body: skid marks where the tyres slide on paved
## ground, smoke off the rear wheels when they slide hard there, dust in the ground's colour
## when they run on loose ground (TrackSurface), sparks where the body scrapes a wall
## or another car, and a splash when it goes into a stream or a lake. Add as a child of the Car.

const SEG_LEN := 0.5        # metres of tread per skid mark segment
const MARK_SLIP := 0.45     # wheel slip that starts laying rubber
const SMOKE_SLIP := 0.65    # ... and that starts smoking
const SPARK_SPEED := 4.0    # m/s of sliding contact that throws sparks
const DUST_SPEED := 6.0     # m/s on loose ground that kicks up dust even without sliding
const HEAVY_SLIP := 0.75    # above this a mark uses NFS3's dense tread texture, below it the streaky one
const SMOKE_CARRY := 0.3    # share of the car's velocity tyre smoke leaves with
const DUST_CARRY := 0.25

var marks: SkidMarks

var _car: Car
var _last: Array = []       # per wheel: where its current mark strip ended, or null
var _smoke: Array[CPUParticles3D] = []   # per rear wheel
var _dust: Array[CPUParticles3D] = []    # per rear wheel
var _sparks: CPUParticles3D
var _splash: CPUParticles3D
var _wet := false           # in a stream or a lake last step
var _spark_t := 0.0
var _crash_t := 0.0         # a crash was reported; spark at its contact once physics has it
var _crash_v := 0.0         # ... and how fast the car was going into it, m/s
var _prev_v := 0.0          # the car's speed last step: by the time a crash is reported it's stopped


func _init(skid_marks: SkidMarks) -> void:
	marks = skid_marks


func _ready() -> void:
	_car = get_parent() as Car
	_last.resize(_car.wheel_states().size())
	var sfx := Nfs3Sfx.shared(Game.data_root)
	for w in _car.wheel_states():
		if not w.front:
			var s := _smoke_emitter(sfx)
			add_child(s)
			_smoke.append(s)
			var d := _dust_emitter(sfx)
			add_child(d)
			_dust.append(d)
	_sparks = _spark_emitter()
	add_child(_sparks)
	_splash = _splash_emitter()
	add_child(_splash)
	_car.crashed.connect(func(_i: float) -> void:
		_crash_t = 0.1
		_crash_v = maxf(_prev_v, _i))


func _physics_process(dt: float) -> void:
	var wheels := _car.wheel_states()
	var moving := absf(_car.speed) > 2.0
	# Weak GPUs: only the player's car smokes (overdraw is what they run out of).
	var smoke_ok := Game.quality != Game.Quality.LOW or _car.is_player
	var k := 0
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var dust := Color(0, 0, 0, 0)
		if w.contact and moving:
			dust = TrackSurface.dust(w.hit.collider, w.hit.shape, w.hit.get("face_index", -1))
		var loose := dust.a > 0.0
		# Rubber only on paved ground; on dirt and grass the dust does the talking.
		var sliding: bool = w.contact and moving and w.slip > MARK_SLIP and not loose
		if not sliding:
			_last[i] = null
		else:
			var p: Vector3 = w.ground
			if _last[i] == null or p.distance_to(_last[i]) > SEG_LEN * 6.0:   # new strip, or a reset
				_last[i] = p
			elif p.distance_to(_last[i]) >= SEG_LEN:
				# Left and right wheels use different textures of each pair, so the two
				# strips of a slide don't look copied.
				var variant := (0 if w.slip > HEAVY_SLIP else 2) + i % 2
				marks.add(_last[i], p, w.normal, clampf(0.35 + w.slip * 0.5, 0.0, 0.85), variant,
						_car.tyre_width[0 if w.front else 1])
				_last[i] = p
		if not w.front:
			var s := _smoke[k]
			var d := _dust[k]
			k += 1
			s.emitting = smoke_ok and w.contact and moving and not loose and w.slip > SMOKE_SLIP
			if s.emitting:
				s.global_position = w.ground + w.normal * 0.4
				_carry(s, w.normal, SMOKE_CARRY)
				# A tyre just past the limit wisps; one sliding flat out billows.
				s.color.a = remap(minf(w.slip, 1.0), SMOKE_SLIP, 1.0, 0.4, 1.0)
			d.emitting = smoke_ok and loose and (absf(_car.speed) > DUST_SPEED or w.slip > MARK_SLIP)
			if d.emitting:
				d.global_position = w.ground + w.normal * 0.3
				_carry(d, w.normal, DUST_CARRY)
				var c := dust * (1.0 if not Game.night else 0.3)
				c.a = 1.0
				d.color = c

	_spark_t = maxf(_spark_t - dt, 0.0)
	_crash_t = maxf(_crash_t - dt, 0.0)
	# A crash sparks at any contact; otherwise only a fast enough slide along one does.
	var scrape := _scrape_point(0.0 if _crash_t > 0.0 else SPARK_SPEED)
	if scrape.size() > 0:
		var crash := _crash_t > 0.0
		# A slide throws a tight jet along the wall; a hit bursts wide, as hard as it landed.
		var v: float = maxf(scrape[2], clampf(_crash_v * 0.4, 5.0, 14.0)) if crash else scrape[2]
		_sparks.global_position = scrape[0]
		_sparks.direction = scrape[1]
		_sparks.spread = 70.0 if crash else 25.0
		_sparks.initial_velocity_min = v * 0.4
		_sparks.initial_velocity_max = v
		_spark_t = maxf(_spark_t, 0.2 if crash else 0.05)
		_crash_t = 0.0
	_sparks.emitting = _spark_t > 0.0
	# Going into a stream or a lake throws up spray, higher the faster the car hits it.
	var wet := _car.water_depth > 0.0
	if wet and not _wet:
		var v := clampf(_car.linear_velocity.length() * 0.3, 3.0, 12.0)
		_splash.global_position = _car.global_position + Vector3.UP * _car.water_depth
		_splash.initial_velocity_min = v * 0.5
		_splash.initial_velocity_max = v
		_splash.restart()
	_wet = wet
	_prev_v = _car.linear_velocity.length()


## Puffs leave with a share of the car's speed, dragged along in its wake, and the damping
## bleeds it off: they billow beside and behind the car rather than vanishing past the
## camera the moment they're made.
func _carry(p: CPUParticles3D, up: Vector3, share: float) -> void:
	var v := _car.linear_velocity * share + up * 1.2
	p.direction = v.normalized()
	p.initial_velocity_min = v.length() * 0.7
	p.initial_velocity_max = v.length()


## [position, spark direction, spark speed] of the body's fastest-sliding contact faster
## than `min_speed`, or [].
func _scrape_point(min_speed: float) -> Array:
	var st := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	if st == null:
		return []
	var best := min_speed
	var out := []
	for i in st.get_contact_count():
		if st.get_contact_collider_object(i) is KnockableProp:
			continue
		var pos := st.get_contact_local_position(i)   # global, despite the name
		var n := st.get_contact_local_normal(i)
		if n.dot(_car.global_position - pos) < 0.0:
			n = -n   # off the wall, towards the car
		var rel := st.get_contact_local_velocity_at_position(i) - st.get_contact_collider_velocity_at_position(i)
		var slide := rel - n * rel.dot(n)
		var v := slide.length()
		if v >= best:
			best = v
			# Shavings carry on the way the bodywork was going, fanning off the wall and up.
			var dir := slide * 0.12 + n * 0.8 + Vector3.UP * 0.5
			out = [pos, dir.normalized(), clampf(v * 0.5, 5.0, 14.0)]
	return out


# Gradient ramps below: set both ends before add_point(), as the added point only takes
# its sorted index once the gradient is next read (set_color(1) would hit it, not the end).

func _smoke_emitter(sfx: Nfs3Sfx) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.top_level = true   # placed in world space each frame
	p.local_coords = false
	p.emitting = false
	p.amount = 48
	p.lifetime = 1.8
	p.direction = Vector3.UP   # and speed: set while emitting (_carry)
	p.spread = 25.0
	p.gravity = Vector3(0, 0.8, 0)   # drifts up
	p.damping_min = 7.0
	p.damping_max = 11.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.angle_min = 0.0
	p.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(0.3, 0.8))
	sc.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = sc
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.0
	var textured := sfx != null and sfx.smoke != null
	# Unshaded, so it's toned down by hand at night rather than glowing in the dark.
	# NFS3's cloud is densest in the middle and thins out to its edges on its own.
	var shade := 0.9 * (1.0 if not Game.night else 0.27)
	var peak := 1.0 if textured else 0.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(shade, shade, shade, 0.0))
	ramp.set_color(1, Color(shade, shade, shade, 0.0))
	ramp.add_point(0.08, Color(shade, shade, shade, peak))
	ramp.add_point(0.45, Color(shade, shade, shade, peak * 0.6))
	p.color_ramp = ramp
	var m := _sprite_material(false)
	if textured:
		m.albedo_texture = sfx.smoke
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Low, slow-rising puffs trailing behind a wheel on loose ground; `color` is set to the
## ground's dust colour while emitting.
func _dust_emitter(sfx: Nfs3Sfx) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.amount = 72   # spaced out at speed: 72 over 2 s is a puff every ~0.8 m at 100 km/h
	p.lifetime = 2.0
	p.direction = Vector3.UP   # and speed: set while emitting (_carry)
	p.spread = 35.0
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 6.0
	p.damping_max = 10.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.angle_min = 0.0
	p.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = sc
	p.scale_amount_min = 3.0
	p.scale_amount_max = 4.5
	var textured := sfx != null and sfx.puff != null
	var peak := 1.0 if textured else 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.08, Color(1, 1, 1, peak))
	ramp.add_point(0.5, Color(1, 1, 1, peak * 0.6))
	p.color_ramp = ramp
	var m := _sprite_material(false)
	if textured:
		m.albedo_texture = sfx.puff
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Streaks of hot metal: each spark is a thin quad stretched along its velocity (turned
## about that line to face the camera). Aimed and sped each frame by the scrape.
func _spark_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.amount = 96
	p.lifetime = 0.45
	p.lifetime_randomness = 0.5
	p.spread = 25.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -9.8, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.0, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.55, 0.12, 1.0))
	p.color_ramp = ramp
	var m := _sprite_material(true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.4)
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A one-shot burst of white water thrown up round the car as it goes in (restart() fires
## it), falling back under gravity.
func _splash_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Splash"
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 64
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 40.0
	p.gravity = Vector3(0, -9.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.95, 1.0, 0.9))
	ramp.set_color(1, Color(0.8, 0.88, 0.95, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _sprite_material(false)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Soft round camera-facing sprite tinted by the particle colour.
static func _sprite_material(additive: bool) -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.5))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_fog = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this the billboard drops each particle's scale: the scale curves do nothing,
	# and slots not yet emitted (zero transform, opaque black) draw as unit-size black discs.
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = t
	return m

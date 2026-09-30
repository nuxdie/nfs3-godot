class_name CarExhaust
extends Node3D
## A Porsche Unleashed car's exhaust, at its tail pipes' ends (Nfs5Car.exhausts): the
## game's "Tail pipe smoke" (its carpart.ini system, sprite SMX1 from particle.fsh), puffing
## at idle, thick when the throttle goes down at low speed, blown away at speed; and the
## pops of flame the pipes spit on a hard upshift or lifting off at high revs.

## Smoke: puffs a second (the emitter's amount over its lifetime) and their size (m), from
## leaving the pipe to thinned out; its density at idle, flat out, and at speed (swept away).
const SMOKE_LIFE := 0.9
const SMOKE_START := 0.22
const SMOKE_END := 0.8
const IDLE_DENSITY := 0.12
const SPEED_CLEAR := 25.0     # m/s by which the car outruns its smoke
## Backfires: over this share of the redline, a flash (s) at the pipes, a few in a row.
const POP_REVS := 0.72
const POP_TIME := 0.06

static var _smoke_tex: Texture2D   # SMX1 with its brightness as alpha (the game draws it added)

var pipes: Array[Vector3] = []     # car-local (the body's), set before it enters the tree

var _car: Car
var _smoke: Array[CPUParticles3D] = []
var _flames: Array[MeshInstance3D] = []
var _gear := 0
var _throttle := 0.0
var _pops := 0          # flashes still to come
var _pop_t := 0.0       # s to the next change (on or off)


func _ready() -> void:
	_car = _find_car()
	if _car == null:
		return
	_gear = _car.gear
	var glare := Nfs5Car.fx("GLAR")
	for p in pipes:
		var s := _emitter()
		add_child(s)
		_smoke.append(s)
		var f := Car._lamp_glow(p + Vector3(0, 0, -0.06), Color(1.0, 0.55, 0.2), 0.42, -1.0)
		if glare:
			(f.mesh.material as ShaderMaterial).set_shader_parameter("glow_tex", glare)
		f.visible = false
		add_child(f)
		_flames.append(f)


func _find_car() -> Car:
	var n := get_parent()
	while n != null and not n is Car:
		n = n.get_parent()
	return n as Car


func _process(dt: float) -> void:
	if _car == null:
		return
	var v := absf(_car.speed)
	var on := not _car.far and not _car.freeze and _car.visible and is_visible_in_tree()
	# The smoke: world-space puffs from each pipe, blown back.
	var density := lerpf(IDLE_DENSITY, 1.0, _car.throttle * (1.0 - clampf(v / 12.0, 0.0, 1.0)))
	density *= 1.0 - 0.85 * clampf(v / SPEED_CLEAR, 0.0, 1.0)
	density = clampf(density + Car.precipitation * 0.3, 0.0, 1.0)   # (it hangs in the damp)
	var back := -_car.global_basis.z
	for i in _smoke.size():
		var s := _smoke[i]
		s.emitting = on and density > 0.05
		if s.emitting:
			s.global_position = global_transform * pipes[i]
			# (Up out of a stack high on the body, as the Kenworth's; back and down out of a pipe.)
			s.direction = _car.global_basis.y if pipes[i].y > 0.3 else (back + Vector3(0, -0.15, 0)).normalized()
			s.initial_velocity_min = 1.0
			s.initial_velocity_max = 2.0
			s.color = Color(1, 1, 1, density)
	# Backfires: an upshift at high revs, or lifting off the throttle there.
	var high := _car.rpm > _car.redline * POP_REVS
	if on and _pops == 0 and high and (_car.gear > _gear and _gear > 0 or _throttle > 0.8 and _car.throttle < 0.2):
		_pops = randi_range(1, 3) * 2
		_pop_t = 0.0
	_gear = _car.gear
	_throttle = _car.throttle
	if _pops > 0:
		_pop_t -= dt
		if _pop_t <= 0.0:
			_pops -= 1
			var lit := _pops % 2 == 1
			_pop_t = POP_TIME * randf_range(0.7, 1.4) if lit else randf_range(0.04, 0.12)
			for f in _flames:
				f.visible = lit
				f.scale = Vector3.ONE * randf_range(0.7, 1.3)
	elif _flames.size() > 0 and _flames[0].visible:
		for f in _flames:
			f.visible = false


func _emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "PipeSmoke"
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.amount = 20
	p.lifetime = SMOKE_LIFE
	p.spread = 12.0
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, SMOKE_START / SMOKE_END))
	sc.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = sc
	p.scale_amount_min = SMOKE_END * 0.8
	p.scale_amount_max = SMOKE_END * 1.2
	var shade := 0.85 * (1.0 if not Game.night else 0.3)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(shade, shade, shade, 0.0))
	ramp.set_color(1, Color(shade, shade, shade, 0.0))
	ramp.add_point(0.1, Color(shade, shade, shade, 0.22))
	ramp.add_point(0.5, Color(shade, shade, shade, 0.1))
	p.color_ramp = ramp
	var m := CarEffects._sprite_material(false)
	if _smoke_tex == null:
		_smoke_tex = _alpha_from_luma(Nfs5Car.fx("SMX1"))
	if _smoke_tex:
		m.albedo_texture = _smoke_tex
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = m
	p.mesh = q
	p.gravity = Vector3(0, 0.5, 0)   # warm: it rises a little
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = Car.VISUAL_LAYER
	return p


## The game's additive smoke as a blended one: white, its brightness the coverage.
static func _alpha_from_luma(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, maxf(maxf(c.r, c.g), c.b)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

class_name Car
extends RigidBody3D
## Arcade-sim car: four raycast wheels with spring/damper suspension, a
## friction-circle tyre model and an automatic gearbox driven by the car's own
## torque curve, gear ratios and top speed (from NFS3 carp.txt when available).
## The car faces local +Z; local +X is the driver's left.

signal crashed(impulse: float)

const SUSPENSION_TRAVEL := 0.22
const STATIC_SAG := 0.09
# Past full travel the suspension hits a stiff, well-damped bump stop instead of letting
# the body sink onto the wheels (which pushed the tyres up through the wheel arches).
const BUMP_STOP_STIFFNESS := 12.0   # x spring rate
const BUMP_STOP_DAMPING := 4.0      # x damper rate
# The wheel ray starts this far above full bump so a hard landing that sinks the car
# doesn't put the ray origin under the road (a miss there dropped the wheel out).
const RAY_LEAD := 0.25

# --- control inputs, written by a controller every physics frame
var throttle := 0.0
var brake := 0.0
var steer := 0.0          # -1 left .. +1 right
var handbrake := false
var hold := false         # parked: full brakes, never engages reverse

# --- telemetry
var speed := 0.0          # signed forward speed, m/s
var rpm := 1000.0
var gear := 1             # -1 reverse, 1..n forward
var slip := 0.0           # 0..1 how much the tyres are sliding
var grounded_wheels := 0
var steer_angle := 0.0
var display_name := ""
var is_player := false
var is_cop := false

# --- tuning (filled from car data)
var top_speed := 70.0
var brake_decel := 10.0
var grip := 1.0
var idle_rpm := 1000.0
var redline := 7000.0
var final_drive := 3.8
var v2rpm := PackedFloat32Array()
var ratios := PackedFloat32Array()
var torque_curve := PackedFloat32Array()
var n_gears := 5
var power_scale := 1.0     # AI rubber-banding / difficulty
var max_steer := deg_to_rad(32.0)
var hood_z := 0.8          # front bumper, local z (bumper camera sits here)

var _wheels: Array[Dictionary] = []
var _wheelbase := 2.6
var _shift_timer := 0.0
var _upside_timer := 0.0
var _body_visual: Node3D
var _siren_lights: Array[OmniLight3D] = []
var _siren_glows: Array[MeshInstance3D] = []
var _siren_pos: Array[Vector3] = []
var _siren := false
var _siren_t := 0.0
var _brake_lights: Array[Node3D] = []
var _lamps: Array[Node3D] = []   # head and running tail glows, shown while the headlights are on
var _head_glows: Array[Node3D] = []
var _reverse_lights: Array[Node3D] = []
var _reverse_xf: Transform3D     # where the reversing lamps' light cone starts, local
var _beams: Array[SpotLight3D] = []   # [between the lamps, left lamp, right lamp]
var _split_beams := false
var _beam_allowed := false
var headlights_on := true
var high_beam := false

## Headlight beams: tilt below level (degrees), reach (m), cone half-angle (degrees), energy.
const LOW_BEAM := [6.0, 40.0, 24.0, 10.0]
const HIGH_BEAM := [1.5, 100.0, 16.0, 18.0]
const REVERSE_CONE := Vector3(14.0, 0.75, 0.9)   # track shader: reach, cos(outer angle), strength


func setup(data: Object, tint := Color(0, 0, 0, 0)) -> void:
	display_name = data.display_name
	mass = maxf(data.carp_value(2, 1400.0), 600.0)
	top_speed = data.carp_value(15, 70.0)
	brake_decel = data.carp_value(18, 10.0)
	grip = clampf(data.carp_value(30, 3.2) / 3.2, 0.8, 1.3)
	idle_rpm = maxf(data.carp_value(12, 1000.0), 700.0)   # some traffic cars list 0
	redline = data.carp_value(13, 7000.0)
	final_drive = data.carp_value(11, 3.8)
	v2rpm = data.carp.get(7, PackedFloat32Array([-220, 0, 230, 150, 110, 88, 70, 0]))
	ratios = data.carp.get(8, PackedFloat32Array([2.1, 0, 2.3, 1.5, 1.12, 0.88, 0.7, 0]))
	torque_curve = data.carp.get(10, PackedFloat32Array([300.0]))
	n_gears = 0
	for i in range(2, v2rpm.size()):
		if v2rpm[i] > 0.0:
			n_gears += 1
	n_gears = maxi(n_gears, 1)

	collision_layer = 2
	collision_mask = 1 | 2 | Nfs3TrackBuilder.SCENERY_LAYER
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	continuous_cd = true
	# Replace (not add to) the project's default damping; drag is modelled explicitly.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.6
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.25
	physics_material_override.bounce = 0.05
	body_entered.connect(_on_body_entered)

	_body_visual = Node3D.new()
	_body_visual.name = "Visual"
	add_child(_body_visual)
	var mat: Material = null
	if data.texture:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/car.gdshader")
		sm.set_shader_parameter("albedo_tex", data.texture)
		var paint := tint
		if paint.a == 0.0:
			paint = data.colours[0] if data.colours.size() > 0 else Color.WHITE
		sm.set_shader_parameter("paint", paint)
		mat = sm
	for p in data.body_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if mat:
			mi.material_override = mat
		_body_visual.add_child(mi)

	var hs: Vector3 = data.half_size
	hood_z = hs.z + 0.1
	var wheel_parts: Array = data.wheels
	for slot in 4:
		var w := {"front": slot < 2, "left": slot % 2 == 0, "radius": 0.33, "spin": 0.0, "compression": 0.0,
			"contact": false, "slip": 0.0}
		var center := Vector3((hs.x - 0.2) * (1 if w.left else -1), -hs.y * 0.45, (hs.z * 0.62) * (1 if w.front else -1))
		if slot < wheel_parts.size():
			var wp: Dictionary = wheel_parts[slot]
			var aabb: AABB = wp.mesh.get_aabb()
			# The part's origin isn't always the hub; the middle of the tyre mesh is.
			center = wp.center + aabb.get_center()
			w.radius = clampf(maxf(aabb.size.y, aabb.size.z) * 0.5, 0.2, 0.6)
			var pivot := Node3D.new()
			pivot.position = center
			var wmi := MeshInstance3D.new()
			wmi.mesh = wp.mesh
			wmi.position = -aabb.get_center()
			var spin := Node3D.new()
			spin.add_child(wmi)
			pivot.add_child(spin)
			if mat:
				wmi.material_override = mat
			_body_visual.add_child(pivot)
			w.visual = pivot
			w.spin_node = spin
		w.center = center
		# The ray starts above the wheel centre by the suspension travel plus a lead-in.
		w.mount = center + Vector3.UP * (SUSPENSION_TRAVEL + RAY_LEAD)
		_wheels.append(w)

	_wheelbase = maxf(_wheels[0].center.z - _wheels[2].center.z, 1.5)

	# Many traffic cars list all-zero gear ratios; derive them from the speed-to-rpm table
	# (rpm per m/s = ratio * final drive * 60 / (2 pi r)).
	ratios = ratios.duplicate()
	var r_drive: float = _wheels[2].radius
	for i in mini(ratios.size(), v2rpm.size()):
		if ratios[i] == 0.0 and v2rpm[i] != 0.0 and final_drive > 0.0:
			ratios[i] = absf(v2rpm[i]) * TAU * r_drive / 60.0 / final_drive

	# Body collision: a box that stays clear of the ground (the wheels hold the car up).
	var bottom: float = _wheels[0].center.y + 0.08
	var top := hs.y
	var box := BoxShape3D.new()
	box.size = Vector3(hs.x * 1.9, top - bottom, hs.z * 1.92)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, (top + bottom) * 0.5, 0)
	add_child(cs)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, _wheels[0].center.y + 0.1, 0)
	# Inertia of a solid box, a little exaggerated for stability.
	var sz := box.size
	inertia = Vector3(sz.y * sz.y + sz.z * sz.z, sz.x * sz.x + sz.z * sz.z, sz.x * sz.x + sz.y * sz.y) * mass / 12.0 * 1.4

	# Lamps sit at the model's light dummies; cars without them get a guess from the body size.
	var heads := _lamp_positions(data, "H", Vector3(hs.x * 0.7, 0.0, hs.z))
	var tails := _lamp_positions(data, "T", Vector3(hs.x * 0.7, 0.0, -hs.z))
	for p in heads:
		_head_glows.append(_lamp_glow(p + Vector3(0, 0, 0.08), Color(1.0, 0.95, 0.8), 0.32))
	_lamps.append_array(_head_glows)
	for p in tails:
		_lamps.append(_lamp_glow(p - Vector3(0, 0, 0.06), Color(0.45, 0.03, 0.02), 0.22))
	for l in _lamps:
		add_child(l)
	_siren_pos = _lamp_positions(data, "S", Vector3(0.4, hs.y * 0.9, 0.0))
	for p in tails:
		var glow := _lamp_glow(p - Vector3(0, 0, 0.08), Color(1.0, 0.08, 0.04), 0.3)
		glow.visible = false
		add_child(glow)
		_brake_lights.append(glow)
	# Reversing lamps: white, just inboard of the taillights (the models have no dummies for them).
	for p in tails:
		var glow := _lamp_glow(p - Vector3(signf(p.x) * 0.16, 0.03, 0.07), Color(0.9, 0.9, 0.85), 0.22)
		glow.visible = false
		add_child(glow)
		_reverse_lights.append(glow)
	var rear := Vector3(0.0, tails[0].y, (tails[0].z + tails[-1].z) * 0.5)
	var rl := OmniLight3D.new()
	rl.light_color = Color(0.9, 0.9, 0.85)
	rl.omni_range = 4.0
	rl.light_energy = 1.0
	rl.visible = false
	rl.position = rear - Vector3(0, 0, 0.3)
	add_child(rl)
	_reverse_lights.append(rl)
	# Facing -Z (backwards) is the light's default; tip it 15° down at the road.
	_reverse_xf = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15.0), 0, 0)), rear)
	for p in [tails[0], tails[-1]]:
		var bl := OmniLight3D.new()
		bl.light_color = Color(1, 0.05, 0.02)
		bl.omni_range = 2.0
		bl.light_energy = 1.2
		bl.visible = false
		bl.position = p - Vector3(0, 0, 0.2)
		add_child(bl)
		_brake_lights.append(bl)
	# Real headlight beams, where set_headlight_beam() allows them: one per lamp, or a single
	# one between the lamps to spare the per-object light budget (8 spots on the Mobile renderer).
	# The NFS3 track shader draws its own cones, see light_cones().
	for p: Vector3 in [(heads[0] + heads[-1]) * 0.5, heads[0], heads[-1]]:
		var beam := SpotLight3D.new()
		beam.position = p + Vector3(0, 0.1, 0.2)
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.spot_attenuation = 0.4
		beam.visible = false
		add_child(beam)
		_beams.append(beam)
	set_high_beam(false)


## Whether this car's headlights cast a real light (on cars and the procedural track).
func set_headlight_beam(allowed: bool, per_lamp := false) -> void:
	_beam_allowed = allowed
	_split_beams = per_lamp
	set_headlights(headlights_on)


func set_headlights(on: bool) -> void:
	headlights_on = on
	for i in _beams.size():
		_beams[i].visible = on and _beam_allowed and (i > 0) == _split_beams
	for l in _lamps:
		l.visible = on


func set_high_beam(on: bool) -> void:
	high_beam = on
	var b: Array = HIGH_BEAM if on else LOW_BEAM
	for i in _beams.size():
		_beams[i].rotation_degrees = Vector3(180.0 + b[0], 0, 0)   # face +Z, tipped down at the road
		_beams[i].spot_range = b[1]
		_beams[i].spot_angle = b[2] + 4.0   # the real light's soft edge reaches a little past the cone
		# A pair of lamps overlaps into about the brightness of the single beam.
		_beams[i].light_energy = b[3] * (1.0 if i == 0 else 0.6)
	for g in _head_glows:
		g.scale = Vector3.ONE * (1.4 if on else 1.0)


## Light cones for the NFS3 track shader, which is unshaded and draws its own lighting:
## [world transform (the cone points down -Z), Vector3(reach, cos(outer angle), strength)].
## Drawn from the interpolated transform so the cones move smoothly between physics ticks.
func light_cones() -> Array:
	var out := []
	var xf := get_global_transform_interpolated()
	if headlights_on:
		var b: Array = HIGH_BEAM if high_beam else LOW_BEAM
		var shape := Vector3(b[1], cos(deg_to_rad(b[2])), 1.4 if high_beam else 1.0)
		out.append([xf * _beams[1].transform, shape])
		out.append([xf * _beams[2].transform, shape])
	if gear < 0:
		out.append([xf * _reverse_xf, REVERSE_CONE])
	return out


static func _lamp_positions(data: Object, kind: String, fallback: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for l: Dictionary in data.lights:
		if l.kind == kind:
			out.append(l.pos)
	if out.is_empty():
		out = [fallback, Vector3(-fallback.x, fallback.y, fallback.z)]
	return out


## A small camera-facing additive sprite: reads as a lit lamp in daylight without costing a light.
static func _lamp_glow(pos: Vector3, colour: Color, size: float) -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.9))
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
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = t
	m.albedo_color = colour
	m.disable_fog = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func enable_siren(on: bool) -> void:
	_siren = on
	if on and _siren_lights.is_empty():
		# Red on the left-hand siren dummy, blue on the right-hand one (+X is the driver's left).
		var ends: Array[Vector3] = [_siren_pos[0], _siren_pos[-1]]
		if ends[0].x < ends[1].x:
			ends.reverse()
		for k in 2:
			var c: Color = [Color(1, 0.05, 0.05), Color(0.1, 0.2, 1)][k]
			var l := OmniLight3D.new()
			l.light_color = c
			l.omni_range = 14.0
			l.light_energy = 0.0
			l.position = ends[k] + Vector3.UP * 0.1
			add_child(l)
			_siren_lights.append(l)
			var glow := _lamp_glow(ends[k] + Vector3.UP * 0.05, c, 0.55)
			add_child(glow)
			_siren_glows.append(glow)
	for l in _siren_lights:
		l.visible = on
	for g in _siren_glows:
		g.visible = on


func forward_dir() -> Vector3:
	return global_basis.z


func kmh() -> float:
	return absf(speed) * 3.6


## Puts the car down on the road at `xf` (a point on the road surface), wheels hanging just
## `drop` above it: tall cars and trucks would otherwise spawn with their tyres in the road
## and the suspension would fire them into the air.
func reset_to(xf: Transform3D, drop := 0.1) -> void:
	var tyre_drop := 0.0
	for w in _wheels:
		tyre_drop = maxf(tyre_drop, w.radius - w.center.y)
		w.compression = 0.0
		w.contact = false
	global_transform = xf.translated_local(Vector3.UP * (tyre_drop + drop))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gear = 1
	rpm = idle_rpm


func _torque_at(r: float) -> float:
	if torque_curve.is_empty():
		return 300.0
	var f := clampf(r / 256.0, 0.0, torque_curve.size() - 1.001)
	var i := int(f)
	return lerpf(torque_curve[i], torque_curve[mini(i + 1, torque_curve.size() - 1)], f - i)


func _gear_index(g: int) -> int:
	return 0 if g < 0 else g + 1


func _physics_process(dt: float) -> void:
	var fwd := global_basis.z
	var up := global_basis.y
	var vel := linear_velocity
	speed = vel.dot(fwd)
	var abs_speed := absf(speed)

	# --- gearbox (automatic) and reverse
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	if hold:
		throttle = 0.0
		brake = 1.0
	elif gear > 0 and brake > 0.5 and throttle < 0.1 and abs_speed < 1.0:
		gear = -1
	elif gear < 0 and throttle > 0.1 and speed > -1.0:
		gear = 1
	if gear > 0 and _shift_timer <= 0.0:
		var r := abs_speed * v2rpm[_gear_index(gear)]
		if r > redline * 0.94 and gear < n_gears:
			gear += 1
			_shift_timer = 0.22
		elif gear > 1 and abs_speed * v2rpm[_gear_index(gear - 1)] < redline * 0.7:
			gear -= 1
			_shift_timer = 0.15
	var target_rpm := maxf(idle_rpm, abs_speed * absf(v2rpm[_gear_index(gear)]))
	# In first/reverse the clutch slips at low speed (see torque_rpm below), so the revs rise with the throttle.
	var pedal := throttle if gear > 0 else (0.0 if hold else brake)
	if absi(gear) == 1:
		target_rpm = maxf(target_rpm, lerpf(idle_rpm, redline * 0.45, pedal))
	if grounded_wheels == 0 or (throttle > 0.1 and slip > 0.6):
		target_rpm = lerpf(target_rpm, redline, throttle * 0.8)
	rpm = lerpf(rpm, minf(target_rpm, redline * 1.02), 1.0 - exp(-dt * 12.0))

	var gi := _gear_index(gear)
	var drive := 0.0
	if _shift_timer <= 0.0 and pedal > 0.0:
		var wheel_r: float = _wheels[2].radius
		# Below ~45% of redline in first/reverse the clutch slips, so torque comes from a higher rpm.
		var torque_rpm := maxf(rpm, redline * 0.45) if absi(gear) == 1 else rpm
		drive = _torque_at(torque_rpm) * absf(ratios[gi]) * final_drive * 0.85 / wheel_r * pedal * power_scale
		if rpm >= redline or abs_speed >= top_speed:
			drive = 0.0
		if gear < 0:
			drive = -drive * 0.6
	var braking := 0.0
	if gear > 0 or hold:
		braking = brake
	elif throttle > 0.0:
		braking = throttle

	# --- steering: less lock at speed
	var lock := max_steer * lerpf(1.0, 0.28, clampf(abs_speed / 55.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, -steer * lock, dt * 2.5)

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.exclude = [get_rid()]
	q.collision_mask = 1 | Nfs3TrackBuilder.SCENERY_LAYER
	grounded_wheels = 0
	var total_slip := 0.0
	var k := mass * 9.81 / 4.0 / STATIC_SAG
	var c := 2.0 * sqrt(k * mass / 4.0) * 0.45

	for w in _wheels:
		var origin: Vector3 = global_transform * w.mount
		var ray_len: float = SUSPENSION_TRAVEL + RAY_LEAD + w.radius
		q.from = origin
		q.to = origin - up * ray_len
		var hit := space.intersect_ray(q)
		var prev_comp: float = w.compression
		var prev_contact: bool = w.contact
		if hit.is_empty():
			w.compression = 0.0
			w.contact = false
			w.slip = 0.0
			w.spin += speed / w.radius * dt
			continue
		grounded_wheels += 1
		w.contact = true
		var dist := origin.distance_to(hit.position)
		w.compression = ray_len - dist
		var offset: Vector3 = hit.position - global_position
		# On first contact the finite difference from zero would read as a huge compression
		# speed (and a huge damper kick); the body's own speed into the road is the real one.
		var comp_vel: float = (w.compression - prev_comp) / dt if prev_contact \
				else -(linear_velocity + angular_velocity.cross(offset)).dot(up)
		var spring: float = k * w.compression + c * comp_vel
		var over: float = w.compression - SUSPENSION_TRAVEL
		if over > 0.0:
			spring += k * BUMP_STOP_STIFFNESS * over + c * BUMP_STOP_DAMPING * maxf(comp_vel, 0.0)
		spring = maxf(spring, 0.0)
		var n: Vector3 = hit.normal
		var contact: Vector3 = hit.position
		w.ground = contact
		w.normal = n
		apply_force(up * spring, offset)

		# Tyre frame on the ground plane.
		var wf := fwd
		if w.front:
			wf = fwd.rotated(up, steer_angle)
		wf = (wf - n * wf.dot(n)).normalized()
		var ws := n.cross(wf).normalized()  # points to the car's left
		var pv := linear_velocity + angular_velocity.cross(offset)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(ws)

		var load := maxf(spring, 0.0)
		var mu := 1.25 * grip
		var lat_grip := 1.0
		if handbrake and not w.front:
			mu *= 0.55
			lat_grip = 0.35
		var max_f := mu * load
		# Lateral: cancel sideways sliding (stiff at low speed, capped by grip).
		var f_lat := -v_lat * mass * 0.25 / dt * 0.18 * lat_grip
		# Longitudinal: drive on the rear (and some front), brakes on all.
		var f_long := 0.0
		if not w.front:
			f_long += drive * 0.5
		if braking > 0.0:
			var b := brake_decel * mass * 0.25 * braking * 1.25
			# ABS: braking only gets the grip that cornering leaves over, so the car still
			# turns while braking instead of ploughing on into the outside wall.
			var lat_used := minf(absf(f_lat), max_f * 0.9)
			b = minf(b, sqrt(max_f * max_f - lat_used * lat_used))
			f_long -= clampf(v_long * mass * 0.25 / dt, -b, b)
		if handbrake and not w.front:
			f_long -= clampf(v_long * mass * 0.25 / dt, -max_f * 0.8, max_f * 0.8)
		# Rolling resistance.
		f_long -= v_long * 4.0
		var f := Vector2(f_lat, f_long)
		var ws_slip := 0.0
		if f.length() > max_f:
			ws_slip = clampf((f.length() - max_f) / max_f, 0.0, 1.0)
			f = f.normalized() * max_f
		w.slip = maxf(ws_slip, clampf(absf(v_lat) / 8.0, 0.0, 1.0) if abs_speed > 3.0 else 0.0)
		total_slip += w.slip
		apply_force(ws * f.x + wf * f.y, offset)
		w.spin += v_long / w.radius * dt
	slip = total_slip / 4.0

	# --- aero: drag and downforce
	var drag := 0.42 * speed * absf(speed)
	apply_central_force(-fwd * drag)
	if grounded_wheels > 0:
		apply_central_force(-up * mass * clampf(abs_speed * abs_speed * 0.00035, 0.0, 0.9) * 9.81 * 0.5)
	# Keep yaw from running away when grip is lost (arcade assist). Only rotation beyond what
	# the steering asks for is damped; damping all of it makes the car plough wide in bends.
	var yaw := angular_velocity.dot(up)
	if not handbrake:
		var yaw_ref := speed * tan(steer_angle) / _wheelbase
		var excess := yaw
		if yaw * yaw_ref > 0.0:
			excess = signf(yaw) * maxf(absf(yaw) - absf(yaw_ref), 0.0)
		apply_torque(-up * excess * inertia.y * 1.2)
	# Gentle self-righting in the air so jumps land on the wheels.
	if grounded_wheels == 0:
		var axis := up.cross(Vector3.UP)
		apply_torque(axis * inertia.x * 6.0 - angular_velocity * inertia.x * 1.5)

	if up.y < 0.2:
		_upside_timer += dt
	else:
		_upside_timer = 0.0

	# Hidden rather than zero energy: an active light costs culling and shading even when dark.
	var braking_lit := brake > 0.1 and gear > 0
	for bl in _brake_lights:
		bl.visible = braking_lit
	for rl in _reverse_lights:
		rl.visible = gear < 0


## Per-wheel state for effects: "contact", "ground" and "normal" (world, valid while in
## contact), "slip" 0..1, "front", "left".
func wheel_states() -> Array[Dictionary]:
	return _wheels


func is_stuck_upside_down() -> bool:
	return _upside_timer > 2.5


func _process(dt: float) -> void:
	for w in _wheels:
		if not w.has("visual"):
			continue
		# Wheel centre sits `compression` above its fully-extended position, but never
		# further up than the arch allows.
		var y: float = w.center.y + minf(w.compression, SUSPENSION_TRAVEL)
		w.visual.position.y = lerpf(w.visual.position.y, y, 1.0 - exp(-55.0 * dt))
		w.visual.rotation.y = steer_angle if w.front else 0.0
		w.spin_node.rotation.x = fmod(w.spin, TAU)
	if _siren:
		_siren_t += dt
		var phase := fmod(_siren_t * 3.0, 1.0)
		_siren_lights[0].light_energy = 6.0 if phase < 0.5 else 0.0
		_siren_lights[1].light_energy = 6.0 if phase >= 0.5 else 0.0
		_siren_glows[0].visible = phase < 0.5
		_siren_glows[1].visible = phase >= 0.5


func _on_body_entered(other: Node) -> void:
	var impulse := linear_velocity.length()
	if other is Car:
		impulse = (linear_velocity - (other as Car).linear_velocity).length()
	if impulse > 4.0:
		crashed.emit(impulse)

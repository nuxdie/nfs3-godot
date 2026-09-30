class_name Car
extends RigidBody3D
## Arcade-sim car: four raycast wheels with spring/damper suspension, a
## friction-circle tyre model and an automatic gearbox driven by the car's own
## torque curve, gear ratios and top speed (from NFS3 carp.txt when available).
## The car faces local +Z; local +X is the driver's left.

signal crashed(impulse: float)
signal was_reset

const SUSPENSION_TRAVEL := 0.22
const STATIC_SAG := 0.09
# Past full travel the suspension hits a stiff, well-damped bump stop instead of letting
# the body sink onto the wheels (which pushed the tyres up through the wheel arches).
const BUMP_STOP_STIFFNESS := 12.0   # x spring rate
const BUMP_STOP_DAMPING := 4.0      # x damper rate
# The wheel ray starts this far above full bump so a hard landing that sinks the car
# doesn't put the ray origin under the road (a miss there dropped the wheel out).
const RAY_LEAD := 0.25
# Deceleration from the engine when coasting off the pedals, m/s^2.
const ENGINE_BRAKE := 0.6
# Body sway: the bodywork rides its springs as a damped oscillator, so it lags, leans into a
# bend and overshoots a little on a quick direction change. Radians per m/s^2 at pitch_roll
# [45] 1, natural frequency (Hz), damping ratio, and the most it may lean.
const SWAY_GAIN := 0.0095
const SWAY_HZ := 1.4
const SWAY_DAMPING := 0.5
const SWAY_MAX := 0.12
# Progressive grip: past the limit the tyre gives up its grip gradually with the slip angle,
# from the peak (rad) to the full slide, instead of all at once as soon as it breaks away.
const SLIP_PEAK := 0.12
const SLIP_FULL := 0.6
# Slip-angle tyres (progressive_grip): the grip a fully sliding tyre gives up, x the slide
# multiplier [38]; and how much less grip each extra share of load buys (load sensitivity:
# the more weight moves onto one tyre, the less grip the car has in all).
const SLIDE_DROP := 0.2
const LOAD_SENS := 0.2
# How far past the front tyres' peak slip angle full lock may go at speed.
const STEER_MARGIN := 1.3

## The GTA IV-style additions, for A/B testing against the plain NFS3 handling (F6 toggles).
static var body_sway := true
## Beyond this (m) from the camera nobody sees the wheels turn, the body sway or the tyre
## effects: the car skips them (see `far`).
const DETAIL_RANGE := 140.0
## Porsche Unleashed's Carreras raise their rear spoiler above this speed (m/s, 80 km/h)
## and lower it again below the second (15 km/h), as the real cars do.
const SPOILER_UP := 22.2
const SPOILER_DOWN := 4.2
const REST_AFTER := 1.0   # s an AI car is held motionless before it sleeps
## Whether brake and reversing lamps cast real light (Low quality: just the glowing lamps).
static var lamp_lights := true
static var progressive_grip := true

# --- control inputs, written by a controller every physics frame
var throttle := 0.0
var brake := 0.0
var steer := 0.0          # -1 left .. +1 right
var handbrake := false
var hold := false         # parked: full brakes, never engages reverse
var horn := false

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
var far := false          # out past DETAIL_RANGE from the camera (updated each frame)
var resting := false      # held still and asleep in the physics engine (see REST_AFTER)
var car_data: Object      # what it was built from (Nfs3Car or ProceduralCar): CarAudio finds its engine banks there

# --- tuning (filled from car data; the carp.txt field number is in brackets)
## NFS3 counts pedal, steering and gearbox ramps in physics ticks, with the pedals and the
## steering in 128ths of their travel (the brake-increasing curve sums to exactly 128).
const TICK := 1.0 / 32.0
const PEDAL_STEPS := 128.0
var car_class := 0         # [1] 0 A .. 2 C, 3 special
var top_speed := 70.0      # [15] hard cap, m/s
var max_velocity := 70.0   # [14] what the engine reaches on the flat, m/s: sets the drag
var brake_decel := 10.0    # [18] m/s^2
var grip := 1.0            # [30] lateral grip multiplier over 3.2, x tyre factor [66]
var surface_grip := 1.0    # the road under it: below 1 when wet or snowy (set by Weather)
var off_road := 0.0        # share of the grounded wheels on loose ground (grass, dirt, sand, snow)
var water_depth := 0.0     # m the car is under a stream or lake surface (set by the race): it wades
var idle_rpm := 1000.0     # [12]
var redline := 7000.0      # [13]
var final_drive := 3.8     # [79] (automatic) or [11]
var v2rpm := PackedFloat32Array()        # [76] or [7], per gear slot (R, N, 1..)
var ratios := PackedFloat32Array()       # [77] or [8], x gear ratio factor [63]
var gear_eff := PackedFloat32Array()     # [78] or [9]
var torque_curve := PackedFloat32Array() # [10], Nm every 256 rpm, x engine tuning [60]
var n_gears := 5           # [75] or [3], less reverse and neutral
var shift_delay := 0.2     # [4] s without drive while changing gear
var shift_blip := PackedFloat32Array()   # [5] rpm the engine keeps over the new gear on an upshift
var brake_blip := PackedFloat32Array()   # [6] rpm blipped over the new gear on a braking downshift
var front_drive := 0.0     # [16] share of the drive on the front wheels (0.5 = four-wheel drive)
var has_abs := true        # [17]
var brake_front := 0.55    # [19] + brake balance [61]
var gas_up := PackedFloat32Array()       # [20] per gear, pedal steps per tick
var gas_down := PackedFloat32Array()     # [21]
var brake_up := PackedFloat32Array()     # [22] pedal steps added on the n-th tick of braking
var brake_down := PackedFloat32Array()   # [23]
var wheelbase := 2.6       # [24] m
var weight_front := 0.5    # [25] "front grip bias": the share of the weight (and so of the grip) on the front axle
var front_grip := 1.0      # factor on the front tyres: less for High Stakes' understeer gradient [80]
var power_steering := true # [26]
var steer_rate_fast := 17.0  # [27] minimum steering acceleration: turn-in steps per tick at speed
var steer_in := 16.0       # [28] turn-in ramp, steps per tick at a standstill
var steer_out := 32.0      # [29] turn-out ramp
var downforce_k := 0.00035 # [31] x aero factor [65], g-units of load per (m/s)^2 (half on the tyres)
var drag_k := 0.42         # N per (m/s)^2, from max velocity [14] and aero factor [65]
var gas_off := 0.35        # [32] engine braking off the throttle
var g_transfer := 0.45     # [33] load moved between the wheels per g of acceleration: sets the height of the centre of mass
var slip_peak := [SLIP_PEAK, SLIP_PEAK]   # front, rear tyres' peak slip angle (rad), from their size [35], [36]
var tyre_radius := [0.33, 0.33]   # [35], [36] front, rear (m)
var tyre_width := [0.245, 0.245]  # [35], [36] front, rear (m)
var tyre_wear_rate := 0.0  # [37]
var slide_mult := 1.0      # [38] how much grip a sliding tyre gives up
var spin_cap := 0.35       # [39] rad/s of yaw beyond the steering allowed before the assist acts
var slide_cap := 0.3       # [40] sideways/forward speed allowed before the slide assist acts
var slide_assist := 1.0    # [41] over 128
var push_factor := 1.0     # [42] over 9000: shove given to other cars in a hit
var low_turn := 1.0        # [43] steering lock factor at low speed (lower figure = more lock)
var high_turn := 1.0       # [44] ... and at high speed
var pitch_roll := 0.8      # [45] body pitch and roll on its springs
var bumpiness := 0.8       # [46] how much the body moves over bumps (softer dampers)
var spoiler_type := 0      # [47] 0 none, else active above [48]
var spoiler_speed := 0.0   # [48] m/s
var turn_cutoffs := [55.0, 95.0, 150.0]   # [49..51] AI: bend sharpness (10^4 / radius) classes
var turn_speed_mods := [0.95, 0.93, 0.9]  # [52..54] AI: speed factors for those bends
var camera_arm := 1.0      # [56] over the stock 0.25: chase camera distance
var ai_accel := PackedFloat32Array()      # [67..74] the original AI's acceleration table, m/s^2 per 1 m/s
var power_scale := 1.0     # AI rubber-banding / difficulty
var max_steer := deg_to_rad(32.0)  # from the turning circle [34] and wheelbase
var hood_z := 0.8          # front bumper, local z (bumper camera sits here)
var damage := 0.0          # 0..1, written by CarDamage: costs power and top speed
var steer_pull := 0.0      # bent steering, fraction of the lock (+ pulls left)
var flat_t := 0.0          # seconds left on tyres shredded by a spike strip (a reset refits them)

var _wheels: Array[Dictionary] = []
var _r_drive := 0.33        # driven tyre's radius, m
var _k_scale := 1.0         # suspension stiffness [64], softened by suspension damage [59]
var _steer_speed := 1.0     # steering speed [62]
var _gas := 0.0             # the pedals where they are now, on their way to throttle/brake
var _brake_pedal := 0.0
var _brake_ticks := 0.0     # ticks the brake has been going down, for its curve [22]
var _blip := 0.0            # rpm held over the new gear while a shift goes through [5], [6]
var _wear := 0.0            # grip worn off the tyres [37]
var _prev_vel := Vector3.ZERO
var _acc := Vector2.ZERO    # smoothed acceleration in the car's frame: x to the left, y forward
var _body_tilt: Node3D
var _tilt_pivot := Vector3.ZERO     # roll and pitch centre, car-local (at axle height)
var _tilt := Vector2.ZERO           # body pitch (x) and roll (y), rad
var _tilt_vel := Vector2.ZERO
var _half_size := Vector3(0.9, 0.7, 2.2)
var _shift_timer := 0.0
var _upside_timer := 0.0
var _body_visual: Node3D
var _body_meshes: Array[MeshInstance3D] = []
var _siren_lights: Array = []    # [OmniLight3D, colour letter]: one per colour on the light bar
var _siren_glows: Array = []     # [glow, lamp (see Nfs3Car.decode_light())]
var _siren_lamps: Array[Dictionary] = []
var _wigwags: Array = []         # [head glow, lamp]: headlamps that flash with the siren
var _broken := {}                # lamp position -> true: lamps a crash has put out
var _main_heads: Array[Vector3] = []   # the left and right headlamps the beams come from
var _siren := false
var _siren_t := 0.0
var _braking_lit := false
var _rest_t := 0.0
var _reversing_lit := false
var _ray_q: PhysicsRayQueryParameters3D   # the wheels' suspension ray, reused every tick
var _brake_lights: Array[Node3D] = []
var _lamps: Array[Node3D] = []   # head and running tail glows, shown while the headlights are on
var _head_glows: Array[Node3D] = []
var _popups: Array[Node3D] = []   # pop-up headlamps, raised while the headlights are on
var _popup_covers: Array[Node3D] = []   # Porsche Unleashed: the same lamps down, shown while they're off
var _spoiler_down: Array[Node3D] = []   # Porsche Unleashed: the Carrera's rear spoiler lowered...
var _spoiler_up: Array[Node3D] = []     # ... and raised, above SPOILER_UP until below SPOILER_DOWN
var _spoiler_raised := false
var _plates: Array[Node3D] = []   # the licence plate (High Stakes cars)
var _dash_data := {}              # the car file's in-car view (High Stakes), built on first use
var _dash: Node3D                 # ...its dashboard, seats and doors, shown instead of the body
var _dash_needles: Array[Dictionary] = []   # {node, axis, turns, rpm}
var _dash_wheel: Node3D
var _dash_wheel_axis := Vector3.BACK
var _dash_lit: Array[Node3D] = []
var _dash_mats: Array[Material] = []   # the needles' materials: [by day, lit]
var _dash_lit_on := false
var _paint := Color.WHITE
var _steer_mats: Array[ShaderMaterial] = []   # the materials turning the steering wheel and the driver's hands
var _steer_shapes: Array = []   # [MeshInstance3D, angles]: Porsche Unleashed's arms and hands, posed by blend shapes
var _steer_shown := 0.0
var _reverse_lights: Array[Node3D] = []
var _reverse_xf: Transform3D     # where the reversing lamps' light cone starts, local
var _beams: Array[SpotLight3D] = []   # [between the lamps, left lamp, right lamp]
var _split_beams := false
var _beam_allowed := false
var headlights_on := true
var upgrade_level := 0      # High Stakes' upgrades, 0 stock .. 3 (see UPGRADES)
## The officer who gets out when this car busts someone (High Stakes' police cars), or null.
var officer_mesh: Mesh
var high_beam := false

## Headlight beams: tilt below level (degrees), reach (m), cone half-angle (degrees), energy.
const LOW_BEAM := [6.0, 40.0, 24.0, 10.0]
const HIGH_BEAM := [1.5, 100.0, 16.0, 18.0]
const REVERSE_CONE := Vector3(14.0, 0.75, 0.9)   # track shader: reach, cos(outer angle), strength
## Render layer bit of everything drawn on the car, so the reflection probe riding inside it
## can leave the car out.
const VISUAL_LAYER := 2
## The light dummies' colours: white, red, blue, orange, yellow. (Each lamp's glow keeps what
## the wet road reflects of it as meta "glint": [which way it shines, 1 ahead, -1 behind,
## 0 all round; colour x strength], see lit_lamps().)
const LAMP_COLOURS := {"W": Color(1.0, 0.95, 0.8), "R": Color(1.0, 0.08, 0.04), "B": Color(0.1, 0.2, 1.0),
	"O": Color(1.0, 0.42, 0.05), "Y": Color(1.0, 0.78, 0.25)}
## Flashing lamps go round this cycle (s): each lit for `time` tenths of it, starting `delay`
## tenths in, the "E" ones half a cycle after the "O" ones.
const FLASH_CYCLE := 0.4


## High Stakes' upgrades, bought in turn: 1 suspension, 2 aero, 3 engine. Each multiplies
## acceleration, braking, handling and top speed (its tuning table, as the PlayStation
## version ships it in ZTUNING.BIN; the PC one keeps it in the program).
const UPGRADES := [
	Vector4(0.98, 1.0, 1.05, 1.0),
	Vector4(1.09, 1.0, 1.02, 1.0),
	Vector4(1.10, 1.25, 1.0, 1.09),
]
const UPGRADE_NAMES := ["Stock", "Level 1", "Level 2", "Level 3"]


## Acceleration, braking, handling and top speed multipliers of upgrade `level` (0..3).
static func upgrade_mults(level: int) -> Vector4:
	var m := Vector4.ONE
	for i in clampi(level, 0, UPGRADES.size()):
		m *= UPGRADES[i]
	return m


func setup(data: Object, tint := Color(0, 0, 0, 0), upgrade := 0) -> void:
	upgrade_level = upgrade
	display_name = data.display_name
	car_data = data
	_load_spec(data)

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
	# The bodywork pitches and rolls on its springs [45] about the car's origin, which keeps
	# its parts' positions car-local at rest (CarDamage relies on that); the wheels don't.
	_body_tilt = Node3D.new()
	_body_tilt.name = "Body"
	_body_visual.add_child(_body_tilt)
	var mat: Material = null
	var wheel_mat: Material = null
	if data.texture:
		var sm := ShaderMaterial.new()
		sm.shader = Game.shader("res://shaders/car.gdshader")
		sm.set_shader_parameter("albedo_tex", data.texture)
		if data.damage_texture:
			sm.set_shader_parameter("damage_tex", data.damage_texture)
		var paint := tint
		if paint.a == 0.0:
			paint = data.colours[0] if data.colours.size() > 0 else Color.WHITE
		sm.set_shader_parameter("paint", paint)
		mat = sm
		_paint = paint
		# The wheels share the skin but take a rubber finish on the tyres.
		wheel_mat = sm.duplicate()
		wheel_mat.set_shader_parameter("wheel", true)
	var glass_mat: Material = null
	# The people inside: cloth and skin, not paint (car_driver.gdshader).
	var driver_mat: ShaderMaterial = null
	if data.texture:
		driver_mat = ShaderMaterial.new()
		driver_mat.shader = Game.shader("res://shaders/car_driver.gdshader")
		driver_mat.set_shader_parameter("albedo_tex", data.texture)
		driver_mat.set_shader_parameter("paint", _paint)
	for p in data.body_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if p.get("glass", false) and data.texture:
			# High Stakes' windows: tinted and see-through, the driver behind them.
			if glass_mat == null:
				var gm := ShaderMaterial.new()
				gm.shader = load("res://shaders/car_glass.gdshader")
				gm.set_shader_parameter("albedo_tex", data.texture)
				glass_mat = gm
			mi.material_override = glass_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif p.get("driver", false) and driver_mat:
			mi.material_override = driver_mat
		elif mat:
			mi.material_override = mat
		var part_mat := mi.material_override as ShaderMaterial
		if p.has("steering") and part_mat and not part_mat in _steer_mats:
			part_mat.set_shader_parameter("steer_pivot", p.steering.pivot)
			part_mat.set_shader_parameter("steer_axis", p.steering.axis)
			_steer_mats.append(part_mat)
		if p.has("steer_shapes"):
			_steer_shapes.append([mi, p.steer_shapes])
			_pose_steer_shapes(mi, p.steer_shapes, 0.0)
		# Where each vertex goes in the model's own damaged copy, for CarDamage.
		if p.has("damaged"):
			mi.set_meta("damaged", p.damaged)
		if p.get("popup_closed", false):
			_popup_covers.append(mi)
		match p.get("spoiler", ""):
			"down": _spoiler_down.append(mi)
			"up":
				_spoiler_up.append(mi)
				mi.visible = false
		_body_tilt.add_child(mi)
		_body_meshes.append(mi)
	for p in data.popup_lights:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if mat:
			mi.material_override = mat
		_body_tilt.add_child(mi)
		_popups.append(mi)

	var hs: Vector3 = data.half_size
	_half_size = hs
	hood_z = hs.z + 0.1
	var wheel_parts: Array = data.wheels
	var body_faces := PackedVector3Array()
	for p in data.body_parts:
		for v in p.mesh.get_faces():
			body_faces.append(v + p.center)
	for slot in 4:
		var w := {"front": slot < 2, "left": slot % 2 == 0, "radius": 0.33, "spin": 0.0, "compression": 0.0,
			"contact": false, "slip": 0.0, "lift_max": SUSPENSION_TRAVEL}
		var center := Vector3((hs.x - 0.2) * (1 if w.left else -1), -hs.y * 0.45, (hs.z * 0.62) * (1 if w.front else -1))
		if slot < wheel_parts.size():
			var wp: Dictionary = wheel_parts[slot]
			var aabb: AABB = wp.mesh.get_aabb()
			# The part's origin isn't always the hub; the middle of the tyre mesh is.
			var hub: Vector3 = wp.center + aabb.get_center()
			w.radius = clampf(maxf(aabb.size.y, aabb.size.z) * 0.5, 0.2, 0.6)
			# The model shows the car at rest, so the wheel hangs the static sag below where it
			# is modelled and settles back into place on its springs. From there it may only rise
			# as far as the bodywork above it leaves room, or it shows through the arch.
			center = hub - Vector3(0, STATIC_SAG, 0)
			w.lift_max = STATIC_SAG + clampf(arch_room(body_faces, hub, w.radius, aabb.size.x * 0.5),
				0.0, SUSPENSION_TRAVEL - STATIC_SAG)
			var pivot := Node3D.new()
			pivot.position = hub
			var wmi := MeshInstance3D.new()
			wmi.mesh = wp.mesh
			wmi.position = -aabb.get_center()
			var spin := Node3D.new()
			spin.add_child(wmi)
			pivot.add_child(spin)
			if wheel_mat:
				wmi.material_override = wheel_mat
			_body_visual.add_child(pivot)
			w.visual = pivot
			w.spin_node = spin
		w.center = center
		# The ray starts above the wheel centre by the suspension travel plus a lead-in.
		w.mount = center + Vector3.UP * (SUSPENSION_TRAVEL + RAY_LEAD)
		_wheels.append(w)

	_tilt_pivot = Vector3(0, _wheels[0].center.y, 0)
	if wheelbase <= 0.0:
		wheelbase = maxf(_wheels[0].center.z - _wheels[2].center.z, 1.5)
	# Turning circle [34], kerb to kerb: the outer front wheel turns on half of it. A few cars
	# (the Corvettes) list the radius instead, half a real car's figure: double those.
	var circle: float = data.carp_value(34, 0.0)
	if circle > 0.0:
		if circle < 8.0:
			circle *= 2.0
		max_steer = asin(clampf(wheelbase / (circle * 0.5), 0.0, 1.0))
		max_steer = clampf(max_steer, deg_to_rad(18.0), deg_to_rad(40.0))
	if not data.carp.has(36):
		tyre_radius = [_wheels[0].radius, _wheels[2].radius]
	_r_drive = tyre_radius[1]

	# Many traffic cars list all-zero gear ratios; derive them from the speed-to-rpm table
	# (rpm per m/s = ratio * final drive * 60 / (2 pi r)).
	for i in mini(ratios.size(), v2rpm.size()):
		if ratios[i] == 0.0 and v2rpm[i] != 0.0 and final_drive > 0.0:
			ratios[i] = absf(v2rpm[i]) * TAU * _r_drive / 60.0 / final_drive
	_calibrate_drag(data.carp_value(65, 1.0))

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
	# The centre of mass sits between the axles by the weight split [25], and as high above
	# the road as makes the springs move the g transfer factor's [33] share of the load onto
	# the front tyres under braking (per g, 2 x height / wheelbase of the axle's load).
	var road_y: float = _wheels[0].center.y + STATIC_SAG - _wheels[0].radius
	var cog_h := clampf(g_transfer * wheelbase / 4.0, 0.22, 0.42)
	var zf: float = (_wheels[0].center.z + _wheels[1].center.z) * 0.5
	var zr: float = (_wheels[2].center.z + _wheels[3].center.z) * 0.5
	center_of_mass = Vector3(0, road_y + cog_h, lerpf(zr, zf, weight_front))
	# Inertia of a solid box, a little exaggerated for stability.
	var sz := box.size
	inertia = Vector3(sz.y * sz.y + sz.z * sz.z, sz.x * sz.x + sz.z * sz.z, sz.x * sz.x + sz.y * sz.y) * mass / 12.0 * 1.4

	# Lamps sit at the model's light dummies, their colour, size and flashing as the dummies'
	# names give them (see Nfs3Car.decode_light()); cars without them get a guess from the
	# body size.
	var heads := _lamps_of(data, "H", Vector3(hs.x * 0.7, 0.0, hs.z))
	var tails := _lamps_of(data, "T", Vector3(hs.x * 0.7, 0.0, -hs.z))
	for l in heads:
		var glow := _lamp_glow(l.pos + Vector3(0, 0, 0.08), LAMP_COLOURS[l.colour], 0.32 * _lamp_size(l))
		glow.set_meta("glint", [1.0, _colour_v(l.colour) * 2.5])
		glow.set_meta("lamp", l)
		_head_glows.append(glow)
		# Pursuit cars' headlamps flash in turn (wig-wag) while the siren is going.
		if l.flash != "N":
			_wigwags.append([glow, l])
	_lamps.append_array(_head_glows)
	# Running tail lamps, and the parking and marker lamps (P), dimmer, with the headlights.
	for l in tails + _lamps_of(data, "P"):
		var glow := _lamp_glow(l.pos + Vector3(0, 0, signf(l.pos.z) * 0.06), LAMP_COLOURS[l.colour] * 0.45,
			0.22 * _lamp_size(l))
		glow.set_meta("glint", [signf(l.pos.z), _colour_v(l.colour) * 0.8])
		glow.set_meta("lamp", l)
		_lamps.append(glow)
	# The lamps ride on the bodywork, so they lean with it.
	for l in _lamps:
		_body_tilt.add_child(l)
	_siren_lamps = _lamps_of(data, "S", Vector3(0.4, hs.y * 0.9, 0.0))
	_dash_data = data.get("dash") if "dash" in data else {}
	officer_mesh = data.get("officer") if "officer" in data else null
	# High Stakes' rear plate, with a registration of its own.
	var plate_at: Dictionary = data.get("plate") if "plate" in data else {}
	if not plate_at.is_empty():
		var pm := Plates.make(Plates.random_text(plate_at.euro), plate_at.euro)
		if pm:
			pm.position = plate_at.pos + Vector3(0, 0, -0.012)
			pm.layers = VISUAL_LAYER
			_body_tilt.add_child(pm)
			_plates.append(pm)
	# Brake lamps: High Stakes marks its own, the third one up high included. Where it marks
	# only that one (or none, as NFS3), the tail lamps are the brake lamps too.
	var brakes := _lamps_of(data, "B")
	if brakes.all(func(l: Dictionary) -> bool: return absf(l.pos.x) < 0.25):
		brakes.append_array(tails)
	for l in brakes:
		var glow := _lamp_glow(l.pos - Vector3(0, 0, 0.08), LAMP_COLOURS[l.colour], 0.3 * _lamp_size(l))
		glow.set_meta("glint", [-1.0, _colour_v(l.colour) * 2.2])
		glow.set_meta("lamp", l)
		glow.visible = false
		_body_tilt.add_child(glow)
		_brake_lights.append(glow)
	# Reversing lamps: High Stakes marks them; on NFS3 cars, just inboard of the taillights.
	var reverses := _lamps_of(data, "R")
	if reverses.is_empty():
		for l in tails:
			var r := Nfs3Car.decode_light("RWYN350")
			r.pos = l.pos - Vector3(signf(l.pos.x) * 0.16, 0.03, 0.0)
			reverses.append(r)
	for l in reverses:
		var glow := _lamp_glow(l.pos - Vector3(0, 0, 0.07), LAMP_COLOURS[l.colour], 0.22 * _lamp_size(l))
		glow.set_meta("glint", [-1.0, _colour_v(l.colour) * 1.2])
		glow.set_meta("lamp", l)
		glow.visible = false
		_body_tilt.add_child(glow)
		_reverse_lights.append(glow)
	var rear := Vector3.ZERO
	for l in reverses:
		rear += l.pos
	rear = Vector3(0.0, rear.y, rear.z) / reverses.size()
	var rl := OmniLight3D.new()
	rl.light_color = Color(0.9, 0.9, 0.85)
	rl.omni_range = 4.0
	rl.light_energy = 1.0
	rl.visible = false
	rl.position = rear - Vector3(0, 0, 0.3)
	_body_tilt.add_child(rl)
	_reverse_lights.append(rl)
	# Facing -Z (backwards) is the light's default; tip it 15° down at the road.
	_reverse_xf = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15.0), 0, 0)), rear)
	for l in _outer_pair(brakes):
		var bl := OmniLight3D.new()
		bl.light_color = Color(1, 0.05, 0.02)
		bl.omni_range = 2.0
		bl.light_energy = 1.2
		bl.visible = false
		bl.position = l.pos - Vector3(0, 0, 0.2)
		bl.set_meta("lamp", l)   # it goes out with its lamp (see break_lamps())
		_body_tilt.add_child(bl)
		_brake_lights.append(bl)
	# The beams come from the main pair of headlamps: the brightest, outermost (not the fog lamps).
	var brightest := 0
	for l in heads:
		brightest = maxi(brightest, l.intensity)
	var mains := _outer_pair(heads.filter(func(l: Dictionary) -> bool: return l.intensity == brightest))
	_main_heads = [mains[0].pos, mains[1].pos]
	# Real headlight beams, where set_headlight_beam() allows them: one per lamp, or a single
	# one between the lamps to spare the per-object light budget (8 spots on the Mobile renderer).
	# The NFS3 track shader draws its own cones, see light_cones().
	for p: Vector3 in [(mains[0].pos + mains[1].pos) * 0.5, mains[0].pos, mains[1].pos]:
		var beam := SpotLight3D.new()
		beam.position = p + Vector3(0, 0.1, 0.2)
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.spot_attenuation = 0.4
		beam.visible = false
		_body_tilt.add_child(beam)
		_beams.append(beam)
	set_high_beam(false)
	for g: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		g.layers = VISUAL_LAYER


## Reads the car's carp.txt (see the tuning vars for which field is which). The gearbox is
## automatic, so the automatic set [75..79] wins over the manual one where both are given.
## Serial number [0] and subdivide level [55] (the original renderer's mesh detail) have no
## bearing here.
func _load_spec(data: Object) -> void:
	var carp: Dictionary = data.carp
	car_class = int(data.carp_value(1, 0.0))
	mass = maxf(data.carp_value(2, 1400.0), 600.0)
	top_speed = data.carp_value(15, 70.0)
	max_velocity = data.carp_value(14, top_speed)
	brake_decel = data.carp_value(18, 10.0)
	grip = clampf(data.carp_value(30, 3.2) / 3.2 * data.carp_value(66, 1.0), 0.4, 1.6)
	idle_rpm = maxf(data.carp_value(12, 1000.0), 700.0)   # some traffic cars list 0
	redline = data.carp_value(13, 7000.0)
	final_drive = data.carp_value(79, data.carp_value(11, 3.8))
	var gear_factor: float = data.carp_value(63, 1.0)
	v2rpm = _scaled(_table(carp, [76, 7], [-220, 0, 230, 150, 110, 88, 70, 0]), gear_factor)
	ratios = _scaled(_table(carp, [77, 8], [2.1, 0, 2.3, 1.5, 1.12, 0.88, 0.7, 0]), gear_factor)
	gear_eff = _table(carp, [78, 9], [0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85])
	torque_curve = _scaled(_table(carp, [10], [300.0]), data.carp_value(60, 1.0))
	var forward := 0
	for i in range(2, v2rpm.size()):
		if v2rpm[i] > 0.0:
			forward += 1
	n_gears = clampi(int(data.carp_value(75, data.carp_value(3, forward + 2.0))) - 2, 1, maxi(forward, 1))
	shift_delay = data.carp_value(4, 6.0) * TICK
	shift_blip = _table(carp, [5], [0.0])
	brake_blip = _table(carp, [6], [0.0])
	front_drive = clampf(data.carp_value(16, 0.0), 0.0, 1.0)
	has_abs = data.carp_value(17, 1.0) != 0.0
	brake_front = clampf(data.carp_value(19, 0.55) + data.carp_value(61, 0.0), 0.2, 0.8)
	gas_up = _table(carp, [20], [16.0])
	gas_down = _table(carp, [21], [32.0])
	brake_up = _table(carp, [22], [64.0, 32.0, 16.0, 8.0, 4.0, 2.0, 1.0, 1.0])
	brake_down = _table(carp, [23], [32.0])
	wheelbase = data.carp_value(24, 0.0)
	# The "front grip bias" [25] is where the weight sits: High Stakes' own cars list their
	# showroom weight split there (the F50's 0.42 is its 41/59). The tyres grip by the load
	# on them, so it balances the grip too. High Stakes' understeer gradient [80] (1 neutral;
	# its buses and trucks run to 1.09) takes that much off the front tyres.
	weight_front = clampf(data.carp_value(25, 0.5), 0.3, 0.7)
	front_grip = 1.0 / clampf(data.carp_value(80, 1.0), 0.8, 1.25)
	power_steering = data.carp_value(26, 1.0) != 0.0
	steer_rate_fast = data.carp_value(27, 17.0)
	steer_in = data.carp_value(28, 16.0)
	steer_out = data.carp_value(29, 32.0)
	var aero: float = data.carp_value(65, 1.0)
	# The stock cars span 0.0009..0.0023; 0.0015 is the downforce the handling was tuned on.
	downforce_k = 0.00035 * data.carp_value(31, 0.0015) / 0.0015 * aero
	gas_off = data.carp_value(32, 0.35)
	g_transfer = clampf(data.carp_value(33, 0.45), 0.0, 1.0)
	if carp.has(35) and carp.has(36):
		for axle in 2:
			var t: PackedFloat32Array = carp[35 + axle]
			if t.size() >= 3 and t[0] > 0.0:
				# 245/40 R17: width mm, sidewall % of the width, rim inches.
				tyre_width[axle] = t[0] / 1000.0
				tyre_radius[axle] = t[2] * 0.0254 * 0.5 + t[0] * t[1] / 100000.0
				# A tall sidewall flexes: it takes a bigger slip angle to reach its peak grip
				# (a softer, more forgiving tyre); a wide, low-profile one bites sooner.
				var aspect := clampf(t[1], 25.0, 80.0) / 40.0
				slip_peak[axle] = SLIP_PEAK * clampf(sqrt(aspect) * pow(0.245 / clampf(tyre_width[axle], 0.15, 0.4), 0.3), 0.8, 1.35)
	tyre_wear_rate = data.carp_value(37, 0.0)
	slide_mult = data.carp_value(38, 1.0)
	spin_cap = data.carp_value(39, 0.35)
	slide_cap = data.carp_value(40, 0.3)
	slide_assist = data.carp_value(41, 128.0) / 128.0
	push_factor = data.carp_value(42, 9000.0) / 9000.0
	low_turn = clampf(0.021 / maxf(data.carp_value(43, 0.021), 0.001), 0.75, 1.35)
	high_turn = clampf(0.027 / maxf(data.carp_value(44, 0.027), 0.001), 0.75, 1.35)
	pitch_roll = data.carp_value(45, 0.8)
	bumpiness = data.carp_value(46, 0.8)
	spoiler_type = int(data.carp_value(47, 0.0))
	spoiler_speed = data.carp_value(48, 0.0)
	for i in 3:
		turn_cutoffs[i] = data.carp_value(49 + i, turn_cutoffs[i])
		turn_speed_mods[i] = data.carp_value(52 + i, turn_speed_mods[i])
	camera_arm = clampf(data.carp_value(56, 0.25) / 0.25, 0.6, 1.6)
	ai_accel = PackedFloat32Array()
	for k in range(67, 75):
		ai_accel.append_array(carp.get(k, PackedFloat32Array()))
	# Damage the file starts the car with [57..59] (none on the stock cars).
	damage = clampf(maxf(data.carp_value(57, 0.0), data.carp_value(58, 0.0)), 0.0, 1.0)
	_k_scale = data.carp_value(64, 1.0) * (1.0 - 0.3 * clampf(data.carp_value(59, 0.0), 0.0, 1.0))
	_steer_speed = data.carp_value(62, 1.0)
	var up := upgrade_mults(upgrade_level)
	if up != Vector4.ONE:
		torque_curve = _scaled(torque_curve, up.x)
		ai_accel = _scaled(ai_accel, up.x)
		brake_decel *= up.y
		grip = clampf(grip * up.z, 0.4, 1.7)
		top_speed *= up.w
		max_velocity *= up.w


## The first of `keys` the file has, else `fallback` (always a copy: the result gets scaled).
static func _table(carp: Dictionary, keys: Array, fallback: Array) -> PackedFloat32Array:
	for k in keys:
		if carp.has(k) and not (carp[k] as PackedFloat32Array).is_empty():
			return (carp[k] as PackedFloat32Array).duplicate()
	return PackedFloat32Array(fallback)


static func _scaled(t: PackedFloat32Array, k: float) -> PackedFloat32Array:
	for i in t.size():
		t[i] *= k
	return t


## Entry `i` of a per-gear (or per-tick) table, the last entry past its end.
static func _at(t: PackedFloat32Array, i: int, fallback: float) -> float:
	if t.is_empty():
		return fallback
	return t[clampi(i, 0, t.size() - 1)]


## Push at the tyres, N, from the engine at `r` rpm in gear slot `gi` at full throttle.
func _wheel_force(r: float, gi: int) -> float:
	var eff := _at(gear_eff, gi, 0.85)
	if eff <= 0.0:
		eff = 0.85
	return _torque_at(r) * absf(ratios[gi]) * final_drive * eff / _r_drive


## Drag, scaled by aero [65]. Where the file has the original game's acceleration table
## [67..74], the drag that best matches it above 20 m/s (least squares, taking the gear the
## automatic box would be in); otherwise, the drag that lets the engine in its best gear just
## reach max velocity [14] on the flat (a touch past it, so the top speed cap [15] is met).
func _calibrate_drag(aero: float) -> void:
	var num := 0.0
	var den := 0.0
	for v in range(20, mini(int(max_velocity) - 2, ai_accel.size())):
		if ai_accel[v] <= 0.0:
			continue
		var g := 1
		while g < n_gears and v * v2rpm[_gear_index(g)] > redline * 0.94:
			g += 1
		var rest := _wheel_force(v * v2rpm[_gear_index(g)], _gear_index(g)) - 16.0 * v - mass * ai_accel[v]
		num += rest * v * v
		den += float(v) * v * v * v
	if den > 0.0 and num > 0.0:
		drag_k = clampf(num / den, 0.1, 4.0) * aero
		return
	var v := maxf(max_velocity, 10.0) * 1.03
	var f := 0.0
	for g in range(1, n_gears + 1):
		var gi := _gear_index(g)
		if v * v2rpm[gi] <= redline:
			f = maxf(f, _wheel_force(v * v2rpm[gi], gi))
	if f == 0.0:
		# Out of revs before max velocity: flat out in top gear sets it.
		f = _wheel_force(redline, _gear_index(n_gears))
	f -= 16.0 * v   # rolling resistance, 4 N per m/s at each wheel
	drag_k = clampf(f / (v * v), 0.15, 4.0) * aero


## Share of the lateral grip the car corners on: grip [30], less any understeer [80]. Round a
## bend a car holds a little less than its tyres' peak: weight transfer and the steered
## wheels' drag take the rest (measured with tools/car_handling.gd).
func corner_grip() -> float:
	return grip * minf(front_grip, 1.0) * 0.87


## The original AI's speed factor for a bend of radius r [49..54]: bends are sorted by how
## sharp they are (10^4 / radius) into gradual (no change), medium, sharp and extreme.
func bend_speed_factor(r: float) -> float:
	var s := 10000.0 / maxf(r, 1.0)
	if s < turn_cutoffs[0]:
		return 1.0
	for i in 2:
		if s < turn_cutoffs[i + 1]:
			return turn_speed_mods[i]
	return turn_speed_mods[2]


## Whether this car's headlights cast a real light (on cars and the procedural track).
func set_headlight_beam(allowed: bool, per_lamp := false) -> void:
	_beam_allowed = allowed
	_split_beams = per_lamp
	set_headlights(headlights_on)


func _set_spoiler(up: bool) -> void:
	_spoiler_raised = up
	var inside := _dash != null and _dash.visible
	for mi in _spoiler_up:
		mi.visible = up and not inside
	for mi in _spoiler_down:
		mi.visible = not up and not inside


## Poses blend-shaped arms and hands for the wheel turned `angle` (their shapes' angles
## ascending): the two shapes either side of it, weighted to sum to 1.
static func _pose_steer_shapes(mi: MeshInstance3D, angles: PackedFloat32Array, angle: float) -> void:
	var a := clampf(angle, angles[0], angles[angles.size() - 1])
	var k := 0
	while k < angles.size() - 2 and a > angles[k + 1]:
		k += 1
	var t := inverse_lerp(angles[k], angles[k + 1], a)
	for i in angles.size():
		mi.set_blend_shape_value(i, 1.0 - t if i == k else t if i == k + 1 else 0.0)


## Repaints the car where it stands (the menu's paint choice): every part in the skin's
## material takes `tint` (alpha 0: the car's first colour), as setup() gave it.
func set_paint(tint: Color) -> void:
	var c := tint
	if c.a == 0.0:
		c = car_data.colours[0] if car_data and car_data.colours.size() > 0 else Color.WHITE
	_paint = c
	var done := {}
	for n in find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m and not done.has(m) and m.get_shader_parameter("paint") != null:
			m.set_shader_parameter("paint", c)
			done[m] = true


func set_headlights(on: bool) -> void:
	headlights_on = on
	for i in _beams.size():
		_beams[i].visible = on and _beam_allowed and (i > 0) == _split_beams and not _beam_broken(i)
	for l in _lamps:
		l.visible = on
	for l in _popups:
		l.visible = on and not (_dash and _dash.visible)
	for l in _popup_covers:
		l.visible = not on and not (_dash and _dash.visible)


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
		for i in [1, 2]:
			if not _beam_broken(i):
				out.append([xf * _beams[i].transform, shape])
	if gear < 0:
		out.append([xf * _reverse_xf, REVERSE_CONE])
	return out


## Where the NFS3 track shader darkens the ground under the car, as NFS3's own drop shadow
## did: [the footprint's centre at tyre-contact height, the car's right axis over the
## shadow's half width, its forward axis over the half length] (world, interpolated).
func shadow_footprint() -> Array:
	var xf := get_global_transform_interpolated()
	var w: Dictionary = _wheels[0]
	var centre := xf * Vector3(0, w.center.y - w.radius, 0)
	var b := xf.basis.orthonormalized()
	return [centre, b.x / (_half_size.x * 1.08), b.z / (_half_size.z * 1.04)]


## The lamps that are lit, for the wet road to reflect: [world position, the way it shines
## (zero: all round), colour x strength].
func lit_lamps() -> Array:
	var out := []
	var xf := get_global_transform_interpolated()
	var fwd := xf.basis.z.normalized()
	var glows: Array = _lamps + _brake_lights + _reverse_lights
	for sg in _siren_glows:
		glows.append(sg[0])
	for g: Node3D in glows:
		if g.visible and g.has_meta("glint"):
			var glint: Array = g.get_meta("glint")
			out.append([xf * g.position, fwd * glint[0], glint[1]])
	return out


## The car's lamps of one kind (H, T, B, R, P or S), from its light dummies, leaving out
## broken ones (intensity 0). Without any, a left and right pair at +-fallback.x, unless
## fallback is left out.
static func _lamps_of(data: Object, kind: String, fallback := Vector3.INF) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in data.lights:
		if l.kind == kind and l.intensity > 0:
			out.append(l)
	if out.is_empty() and fallback != Vector3.INF:
		# Named as NFS3 would: left then right (+X is the driver's left).
		for side in ["L", "R"]:
			var l := Nfs3Car.decode_light(kind + "M" + side + "N")
			l.pos = fallback if side == "L" else Vector3(-fallback.x, fallback.y, fallback.z)
			out.append(l)
	return out


## The leftmost and rightmost of some lamps, in that order.
static func _outer_pair(lamps: Array) -> Array:
	var left: Dictionary = lamps[0]
	var right: Dictionary = lamps[0]
	for l: Dictionary in lamps:
		if l.pos.x > left.pos.x:
			left = l
		if l.pos.x < right.pos.x:
			right = l
	return [left, right]


## How big a lamp's glow is for its intensity (5 the usual).
static func _lamp_size(l: Dictionary) -> float:
	return clampf(l.intensity / 5.0, 0.4, 1.4)


static func _colour_v(letter: String) -> Vector3:
	var c: Color = LAMP_COLOURS[letter]
	return Vector3(c.r, c.g, c.b)


## Whether a flashing lamp is lit `t` seconds into its flashing.
static func _flash_lit(l: Dictionary, t: float) -> bool:
	if l.time == 0:
		return true
	var phase := fmod(t / FLASH_CYCLE + l.delay * 0.1 + (0.5 if l.flash == "E" else 0.0), 1.0)
	return phase < l.time * 0.1


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
	mi.layers = VISUAL_LAYER
	return mi


func siren_on() -> bool:
	return _siren


func enable_siren(on: bool) -> void:
	_siren = on
	if on and _siren_glows.is_empty():
		# A light bar of many lamps gets smaller glows than a pair.
		var size := 0.55 if _siren_lamps.size() <= 2 else 0.32
		var by_colour := {}
		for l in _siren_lamps:
			if _broken.has(l.pos):
				continue
			var glow := _lamp_glow(l.pos + Vector3.UP * 0.05, LAMP_COLOURS[l.colour], size * _lamp_size(l))
			glow.set_meta("glint", [0.0, _colour_v(l.colour) * (4.5 if l.colour == "B" else 3.5)])
			glow.visible = false
			_body_tilt.add_child(glow)
			glow.set_meta("lamp", l)
			_siren_glows.append([glow, l])
			by_colour[l.colour] = by_colour.get(l.colour, []) + [l.pos]
		# The light they throw round about, one per colour, only where the quality allows (see
		# lamp_lights).
		if lamp_lights:
			for c: String in by_colour:
				var at := Vector3.ZERO
				for p: Vector3 in by_colour[c]:
					at += p
				var l := OmniLight3D.new()
				l.light_color = LAMP_COLOURS[c]
				l.omni_range = 14.0
				l.light_energy = 6.0
				l.visible = false
				l.position = at / by_colour[c].size() + Vector3.UP * 0.1
				_body_tilt.add_child(l)
				_siren_lights.append([l, c])
	if not on:
		for sl in _siren_lights:
			sl[0].visible = false
		for sg in _siren_glows:
			sg[0].visible = false
		for w in _wigwags:
			w[0].visible = headlights_on


## A crash at car-local `p`: puts out the breakable lamps (see Nfs3Car.decode_light())
## within `radius` of it, and the beam of a main headlamp among them.
func break_lamps(p: Vector3, radius: float) -> void:
	var glows: Array = _lamps + _brake_lights + _reverse_lights
	for sg in _siren_glows:
		glows.append(sg[0])
	var broke := false
	# The glows decide what the crash reaches; the brake lamps' lights go out with theirs.
	for g: Node3D in glows:
		if g is MeshInstance3D and g.has_meta("lamp"):
			var l: Dictionary = g.get_meta("lamp")
			if l.breakable and not _broken.has(l.pos) and g.position.distance_to(p) < radius:
				_broken[l.pos] = true
				broke = true
	if not broke:
		return
	var out := func(g: Node3D) -> bool: return g.has_meta("lamp") and _broken.has(g.get_meta("lamp").pos)
	var keep := func(g: Node3D) -> bool: return not out.call(g)
	for g: Node3D in glows:
		if out.call(g):
			g.queue_free()
	_lamps.assign(_lamps.filter(keep))
	_head_glows.assign(_head_glows.filter(keep))
	_brake_lights.assign(_brake_lights.filter(keep))
	_reverse_lights.assign(_reverse_lights.filter(keep))
	_wigwags = _wigwags.filter(func(w: Array) -> bool: return keep.call(w[0]))
	_siren_glows = _siren_glows.filter(func(sg: Array) -> bool: return keep.call(sg[0]))
	set_headlights(headlights_on)


## Whether headlight beam i ([between the lamps, left, right]) has lost its lamp: the
## middle one only once both have gone.
func _beam_broken(i: int) -> bool:
	if _main_heads.is_empty():
		return false
	if i == 0:
		return _broken.has(_main_heads[0]) and _broken.has(_main_heads[1])
	return _broken.has(_main_heads[i - 1])


func forward_dir() -> Vector3:
	return global_basis.z


func kmh() -> float:
	return absf(speed) * 3.6


## Driven over a spike strip: the tyres go flat for a while, costing grip and top speed.
func puncture(secs := 14.0) -> void:
	flat_t = maxf(flat_t, secs)


func tyres_flat() -> bool:
	return flat_t > 0.0


## Puts the car down on the road at `xf` (a point on the road surface), wheels hanging just
## `drop` above it: tall cars and trucks would otherwise spawn with their tyres in the road
## and the suspension would fire them into the air.
func reset_to(xf: Transform3D, drop := 0.1) -> void:
	if resting:
		_wake()
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
	flat_t = 0.0
	water_depth = 0.0
	_wear = 0.0
	_gas = 0.0
	_brake_pedal = 0.0
	_prev_vel = Vector3.ZERO
	_acc = Vector2.ZERO
	_tilt = Vector2.ZERO
	_tilt_vel = Vector2.ZERO
	was_reset.emit()


func _torque_at(r: float) -> float:
	if torque_curve.is_empty():
		return 300.0
	var f := clampf(r / 256.0, 0.0, torque_curve.size() - 1.001)
	var i := int(f)
	return lerpf(torque_curve[i], torque_curve[mini(i + 1, torque_curve.size() - 1)], f - i)


func _gear_index(g: int) -> int:
	return 0 if g < 0 else g + 1


func _physics_process(dt: float) -> void:
	if resting:
		# Asleep in the physics engine until something runs into it (which wakes it) or it's
		# asked to drive off.
		if hold and sleeping:
			return
		_wake()
	var fwd := global_basis.z
	var up := global_basis.y
	var vel := linear_velocity
	speed = vel.dot(fwd)
	var abs_speed := absf(speed)
	# Acceleration in the car's frame, smoothed: moves load between the tyres [33] and
	# pitches and rolls the body [45]. Clamped so a crash's jolt doesn't throw it about.
	var acc := (vel - _prev_vel) / dt
	_prev_vel = vel
	var acc_now := Vector2(clampf(acc.dot(global_basis.x), -20.0, 20.0), clampf(acc.dot(fwd), -20.0, 20.0))
	_acc = _acc.lerp(acc_now, 1.0 - exp(-dt * 8.0))

	# --- gearbox (automatic) and reverse
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	flat_t = maxf(flat_t - dt, 0.0)
	var flat := flat_t > 0.0
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
			_shift_timer = shift_delay
			_blip = _at(shift_blip, _gear_index(gear), 0.0)
		elif gear > 1 and abs_speed * v2rpm[_gear_index(gear - 1)] < redline * 0.7:
			gear -= 1
			_shift_timer = shift_delay
			# Heel-and-toe: braking into the lower gear blips the throttle to match the revs.
			_blip = _at(brake_blip if _brake_pedal > 0.1 else shift_blip, _gear_index(gear), 0.0)
	var gi := _gear_index(gear)

	# --- pedals: they travel at the car's own rates, in 128ths per tick: the gas by gear
	# [20], [21]; the brake goes down along its curve [22] and comes up at [23].
	var steps := dt / TICK / PEDAL_STEPS
	_gas = move_toward(_gas, throttle, steps * (_at(gas_up, gi, 16.0) if throttle > _gas else _at(gas_down, gi, 32.0)))
	if hold:
		_brake_pedal = 1.0
	elif brake > _brake_pedal:
		_brake_pedal = move_toward(_brake_pedal, brake, steps * _at(brake_up, int(_brake_ticks), 64.0))
		_brake_ticks += dt / TICK
	else:
		_brake_pedal = move_toward(_brake_pedal, brake, steps * _at(brake_down, 0, 32.0))
		_brake_ticks = 0.0

	var target_rpm := maxf(idle_rpm, abs_speed * absf(v2rpm[gi]))
	# In first/reverse the clutch slips at low speed (see torque_rpm below), so the revs rise with the throttle.
	var pedal := _gas if gear > 0 else (0.0 if hold else _brake_pedal)
	if absi(gear) == 1:
		target_rpm = maxf(target_rpm, lerpf(idle_rpm, redline * 0.45, pedal))
	if grounded_wheels == 0 or (throttle > 0.1 and slip > 0.6):
		target_rpm = lerpf(target_rpm, redline, throttle * 0.8)
	if _shift_timer > 0.0:
		target_rpm += _blip
	rpm = lerpf(rpm, minf(target_rpm, redline * 1.02), 1.0 - exp(-dt * 12.0))

	var drive := 0.0
	if _shift_timer <= 0.0 and pedal > 0.0:
		# Below ~45% of redline in first/reverse the clutch slips, so torque comes from a higher rpm.
		var torque_rpm := maxf(rpm, redline * 0.45) if absi(gear) == 1 else rpm
		drive = _wheel_force(torque_rpm, gi) * pedal * power_scale
		drive *= 1.0 - 0.3 * damage
		if rpm >= redline or abs_speed >= top_speed * (1.0 - 0.12 * damage) * (0.45 if flat else 1.0):
			drive = 0.0
		if gear < 0:
			drive = -drive * 0.6
	var braking := 0.0
	if gear > 0 or hold:
		braking = _brake_pedal
	elif throttle > 0.0:
		braking = _gas
	var idle := pedal < 0.05 and braking < 0.05 and not hold

	# --- steering: less lock at speed, by the low and high turn factors [43], [44]. The wheel
	# turns in at the turn-in ramp [28] (easing to the minimum steering acceleration [27] at
	# speed) and back at the turn-out ramp [29], in 128ths of the lock per tick.
	var speed_f := clampf(abs_speed / 55.0, 0.0, 1.0)
	var lock := max_steer * lerpf(low_turn, 0.28 * high_turn, speed_f)
	if progressive_grip:
		# At speed, only as much lock as takes the front tyres a little past their peak slip
		# angle on the tightest line the car's grip (and downforce) holds: any more would only
		# scrub them wide. In a slide the wheels may turn as far again as the car is sideways,
		# so it can be caught.
		var a_max := 9.81 * 1.25 * corner_grip() * surface_grip \
				* (1.0 + clampf(abs_speed * abs_speed * downforce_k, 0.0, 0.9) * 0.5)
		var line := atan(wheelbase * a_max / maxf(abs_speed * abs_speed, 1.0))
		var beta := atan2(absf(vel.dot(global_basis.x)), abs_speed) if abs_speed > 3.0 else 0.0
		lock = minf((line + slip_peak[0] * STEER_MARGIN) * high_turn + beta, max_steer * low_turn)
	var steer_to := (steer_pull - steer) * lock
	var turning_in := absf(steer_to) > absf(steer_angle) and steer_to * steer_angle >= 0.0
	var steer_steps := lerpf(steer_in, steer_rate_fast, speed_f) if turning_in else steer_out
	if not power_steering:
		steer_steps *= lerpf(0.6, 1.0, speed_f)
	steer_angle = move_toward(steer_angle, steer_to, steer_steps * steps * lock * _steer_speed)

	var space := get_world_3d().direct_space_state
	if _ray_q == null:
		_ray_q = PhysicsRayQueryParameters3D.new()
		_ray_q.exclude = [get_rid()]
		_ray_q.collision_mask = 1 | Nfs3TrackBuilder.SCENERY_LAYER
	var q := _ray_q
	grounded_wheels = 0
	var total_slip := 0.0
	var loose_wheels := 0
	# Suspension stiffness [64]; a bumpier car [46] rides on softer dampers. Each axle's springs
	# carry its share of the weight [25] (see `axle`), so the car sits level.
	var k := mass * 9.81 / 4.0 / STATIC_SAG * _k_scale
	var c := 2.0 * sqrt(k * mass / 4.0) * 0.45 * lerpf(1.25, 0.85, clampf(bumpiness, 0.0, 1.0))

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
		# What's underfoot (TrackSurface): off the road the tyres grip less, the ground drags
		# at them and it's bumpy, where the road is smooth.
		var surface := TrackSurface.code(hit.collider, hit.shape, hit.get("face_index", -1))
		var feel := TrackSurface.feel(surface)
		var ground_grip: float = feel[0]
		var ground_drag: float = feel[1]
		var rough: float = feel[2]
		if surface in TrackSurface.LOOSE:
			loose_wheels += 1
		var dist := origin.distance_to(hit.position)
		w.compression = ray_len - dist
		if rough > 0.0:
			# Bumps fixed to the ground (so they come faster the faster the car goes), a
			# different pattern under each wheel.
			var gp: Vector3 = hit.position
			w.compression += rough * (sin(gp.x * 1.9 + gp.z * 0.7) * sin(gp.z * 2.3 - gp.x * 0.4) \
					+ 0.5 * sin((gp.x + gp.z) * 5.1))
		var offset: Vector3 = hit.position - global_position
		# On first contact the finite difference from zero would read as a huge compression
		# speed (and a huge damper kick); the body's own speed into the road is the real one.
		var comp_vel: float = (w.compression - prev_comp) / dt if prev_contact \
				else -(linear_velocity + angular_velocity.cross(offset)).dot(up)
		var share := weight_front if w.front else 1.0 - weight_front
		var spring: float = k * w.compression + c * comp_vel
		var over: float = w.compression - SUSPENSION_TRAVEL
		if over > 0.0:
			spring += k * BUMP_STOP_STIFFNESS * over + c * BUMP_STOP_DAMPING * maxf(comp_vel, 0.0)
		spring = maxf(spring * share * 2.0, 0.0)
		var n: Vector3 = hit.normal
		var contact: Vector3 = hit.position
		w.ground = contact
		w.normal = n
		w.hit = hit   # collider, shape and face_index: what's underfoot (TrackSurface)
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
		# Grip: the car's own [30], less tyre wear [37], by the load on the tyre.
		var mu := 1.25 * grip * (front_grip if w.front else 1.0) * (1.0 - _wear) * surface_grip * ground_grip \
				* (0.5 if flat else 1.0)
		var lat_grip := 1.0
		if handbrake and not w.front:
			mu *= 0.55
			# The slip-angle tyre slides by the friction circle instead, the brake taking most of it.
			if not progressive_grip:
				lat_grip = 0.35
		var max_f := mu * load
		if progressive_grip:
			# The load the springs put on it: the weight split [25], moved about by braking, power
			# and cornering [33], and downforce. Each extra share of it buys a little less grip,
			# so the more load moves onto one tyre, the less the car has in all.
			max_f *= 1.0 - LOAD_SENS * clampf(load / (mass * 9.81 * share * 0.5) - 1.0, -1.0, 2.0)
		else:
			# Classic: the load its acceleration moves onto this tyre [33], on top (onto the rear
			# under power, the front under braking, the outside wheels in a bend).
			var transfer := g_transfer / 9.81 * (_acc.y * (-0.5 if w.front else 0.5) + _acc.x * (-0.5 if w.left else 0.5))
			max_f *= clampf(1.0 + transfer, 0.3, 1.7)
		# Brakes, split front to rear by the brake bias [19]. Without ABS [17] a wheel asked
		# for more than its grip locks, and a locked tyre barely steers.
		var b := 0.0
		if braking > 0.0:
			b = brake_decel * mass * braking * 1.25 * (brake_front if w.front else 1.0 - brake_front) * 0.5
			if not has_abs and b > max_f and absf(v_long) > 1.0:
				lat_grip = minf(lat_grip, 0.3)
		# Lateral: cancel sideways sliding (capped by grip). Nearly stopped it cancels all of it,
		# as static friction does, or the car creeps down any camber it is parked on.
		var f_lat := -v_lat * mass * 0.25 / dt * lerpf(1.0, 0.18, clampf(abs_speed / 2.0, 0.0, 1.0)) * lat_grip
		var slide := 0.0
		var over_peak := 0.0   # how far past its peak slip angle the tyre is, as a share of it
		if progressive_grip:
			# Slip-angle tyre: the grip builds with the angle between where the tyre points and
			# where it's going, peaks at its peak slip angle (by its size [35], [36]) and past it
			# falls away gradually, by the slide multiplier [38]: a slide builds and can be caught.
			var peak: float = slip_peak[0 if w.front else 1]
			var x := atan2(absf(v_lat), maxf(absf(v_long), 0.5)) / peak
			slide = smoothstep(1.0, SLIP_FULL / peak, x)
			over_peak = x - 1.0
			var shape := x * (2.0 - x) if x < 1.0 else 1.0 - SLIDE_DROP * slide_mult * slide
			# Crawling it just holds, as before; and it never pushes back more than stops the
			# slide in one tick, or it would flick from side to side.
			var cancel := -v_lat * mass * share * 0.5 / dt
			f_lat = lerpf(cancel, -signf(v_lat) * max_f * shape, clampf((abs_speed - 1.5) / 3.0, 0.0, 1.0))
			if absf(f_lat) > absf(cancel):
				f_lat = cancel
			f_lat *= lat_grip
		# Longitudinal: the drive split between the axles by the front drive ratio [16].
		var driven := front_drive if w.front else 1.0 - front_drive
		var f_long := drive * 0.5 * driven
		if b > 0.0:
			if has_abs:
				# ABS: braking only gets the grip that cornering leaves over, so the car still
				# turns while braking instead of ploughing on into the outside wall.
				var lat_used := minf(absf(f_lat), max_f * 0.9)
				b = minf(b, sqrt(max_f * max_f - lat_used * lat_used))
			f_long -= clampf(v_long * mass * 0.25 / dt, -b, b)
		if handbrake and not w.front:
			f_long -= clampf(v_long * mass * 0.25 / dt, -max_f * 0.8, max_f * 0.8)
		elif idle:
			# Off the pedals: engine braking on the driven wheels, by the gas off factor [32],
			# and nearly stopped the car stays put (as if in Park) rather than rolling down the slope.
			var hold_f := max_f if abs_speed < 1.0 else mass * 0.5 * ENGINE_BRAKE * gas_off / 0.35 * driven
			f_long -= clampf(v_long * mass * 0.25 / dt, -hold_f, hold_f)
		# Rolling resistance, and loose ground dragging at the tyres (a quarter each).
		f_long -= v_long * 4.0 + v_long * mass * ground_drag * 0.25
		var f := Vector2(f_lat, f_long)
		var ws_slip := 0.0
		if progressive_grip and max_f > 0.0 and abs_speed > 3.0:
			ws_slip = slide
			# The friction circle: asked to corner and drive or brake at once for more than its
			# grip, the tyre breaks away (wheelspin, a locked wheel) and slides, by [38]. Too
			# much power out of a bend takes the grip the rear needs to hold its line.
			var demand := f.length() / max_f
			# Wheelspin: drive past what the cornering leaves over spins the tyre up, which
			# takes only three quarters of its worth of side grip: a power slide builds rather than snaps.
			var spare := sqrt(maxf(max_f * max_f - f.x * f.x, 0.0))
			if f.y > spare and drive * driven > 0.0:
				f.y = spare + (f.y - spare) * 0.75
				demand = f.length() / max_f
			if demand > 1.0:
				var excess := minf(demand - 1.0, 1.0)
				ws_slip = maxf(ws_slip, excess)
				f = f / demand * (1.0 - SLIDE_DROP * slide_mult * excess)
		elif f.length() > max_f:
			ws_slip = clampf((f.length() - max_f) / max_f, 0.0, 1.0)
			# A sliding tyre grips less than one on the limit, by the slide multiplier [38].
			f = f.normalized() * max_f * (1.0 - 0.15 * slide_mult * ws_slip)
		# How much it's sliding, for the skid sound, marks and smoke. The slip-angle tyre runs
		# some way sideways in any bend at speed: it squeals at its peak and marks the road
		# only well past it.
		var sideways := clampf(absf(v_lat) / 8.0, 0.0, 1.0)
		if progressive_grip:
			sideways = clampf((over_peak + 0.25) / 1.3, 0.0, 1.0)
		w.slip = maxf(ws_slip, sideways if abs_speed > 3.0 else 0.0)
		total_slip += w.slip
		apply_force(ws * f.x + wf * f.y, offset)
		w.spin += v_long / w.radius * dt
	slip = total_slip / 4.0
	off_road = float(loose_wheels) / grounded_wheels if grounded_wheels > 0 else 0.0
	_wear = minf(_wear + tyre_wear_rate * slip * dt * 0.01, 0.3)

	# --- aero: drag (see _calibrate_drag) and downforce [31], more with an active spoiler
	# [47] raised above its speed [48]
	apply_central_force(-fwd * drag_k * speed * absf(speed))
	if grounded_wheels > 0:
		var df := mass * clampf(abs_speed * abs_speed * downforce_k, 0.0, 0.9) * 9.81 * 0.5
		apply_central_force(-up * df)
		# The spoiler presses on the rear axle: more grip at the back, steadier at speed.
		if spoiler_type != 0 and abs_speed > spoiler_speed:
			apply_force(-up * df * 0.2, global_basis * Vector3(0, 0, _wheels[2].center.z))
	# Keep yaw from running away when grip is lost (arcade assist). Only rotation beyond what
	# the steering asks for is damped, less the car's spin velocity cap [39] share of it;
	# damping all of it makes the car plough wide in bends. Its strength is the slide
	# assistance factor [41].
	var yaw := angular_velocity.dot(up)
	if not handbrake:
		var yaw_ref := speed * tan(steer_angle) / wheelbase
		var excess := yaw
		if yaw * yaw_ref > 0.0:
			excess = signf(yaw) * maxf(absf(yaw) - absf(yaw_ref) * (1.0 + spin_cap), 0.0)
		apply_torque(-up * excess * inertia.y * 1.2 * slide_assist)
		# Sliding sideways faster than the slide velocity cap [40] allows (as a share of the
		# speed): the assist eases the slide back.
		var v_side := vel.dot(global_basis.x)
		var over := absf(v_side) - slide_cap * abs_speed
		if over > 0.0 and abs_speed > 5.0 and grounded_wheels > 0:
			apply_central_force(-global_basis.x * signf(v_side) * over * mass * 0.5 * slide_assist)
	# In a stream or a lake: the water holds the car back, more the deeper it sits, and
	# stops it sinking like a stone until the race fishes it out.
	if water_depth > 0.0:
		var wade := minf(water_depth / 0.8, 1.0)
		apply_central_force(-vel * mass * 2.5 * wade)
		apply_torque(-angular_velocity * inertia.x * 3.0 * wade)
	# Gentle self-righting in the air so jumps land on the wheels.
	if grounded_wheels == 0:
		var axis := up.cross(Vector3.UP)
		apply_torque(axis * inertia.x * 6.0 - angular_velocity * inertia.x * 1.5)

	if up.y < 0.2:
		_upside_timer += dt
	else:
		_upside_timer = 0.0
	# An AI car held still (a cruiser parked by the road, the grid before the start) that has
	# settled on its springs: nothing to work out until it's hit or let go.
	if hold and not is_player and grounded_wheels == 4 and vel.length_squared() < 0.0025 \
			and angular_velocity.length_squared() < 0.0025:
		_rest_t += dt
		if _rest_t > REST_AFTER:
			resting = true
			can_sleep = true
			sleeping = true
			slip = 0.0
	else:
		_rest_t = 0.0

	# Hidden rather than zero energy: an active light costs culling and shading even when dark.
	var braking_lit := brake > 0.1 and gear > 0
	if braking_lit != _braking_lit or (gear < 0) != _reversing_lit:
		_braking_lit = braking_lit
		_reversing_lit = gear < 0
		# The glows always; the real lights they cast on the road only where the quality allows.
		for bl in _brake_lights:
			bl.visible = braking_lit and (lamp_lights or not bl is Light3D)
		for rl in _reverse_lights:
			rl.visible = _reversing_lit and (lamp_lights or not rl is Light3D)


func has_cockpit() -> bool:
	return not _dash_data.is_empty()


## The driver's eye, car-local, for the in-car view.
func cockpit_eye() -> Vector3:
	return _dash_data.get("eye", Vector3(0.4, 0.45, -0.3))


## The in-car view: the dashboard, seats and doors instead of the body and wheels (the
## camera sits inside them). False when the car file has none.
func set_cockpit(on: bool) -> bool:
	if _dash_data.is_empty():
		return false
	if on and _dash == null:
		_build_dash()
	if _dash:
		_dash.visible = on
	for mi in _body_meshes + _popups:
		mi.visible = not on and (headlights_on or not (mi in _popups)) and not (headlights_on and mi in _popup_covers) \
			and not (mi in _spoiler_up and not _spoiler_raised) and not (mi in _spoiler_down and _spoiler_raised)
	for p in _plates:
		p.visible = not on
	for w in _wheels:
		if w.has("visual"):
			w.visual.visible = not on
	return true


func _build_dash() -> void:
	_dash = Node3D.new()
	_dash.name = "Dash"
	add_child(_dash)
	var mat := ShaderMaterial.new()
	mat.shader = Game.shader("res://shaders/car.gdshader")
	mat.set_shader_parameter("albedo_tex", _dash_data.texture)
	mat.set_shader_parameter("paint", _paint)
	mat.set_shader_parameter("interior", true)
	# The dials' night faces: their markings lit, whatever the light.
	var lit_mat := StandardMaterial3D.new()
	lit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit_mat.albedo_texture = _dash_data.texture
	lit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lit_mat.alpha_scissor_threshold = 0.08
	lit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The needles glow with them: unshaded, whole.
	var needle_lit := lit_mat.duplicate() as StandardMaterial3D
	needle_lit.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_dash_mats = [mat, needle_lit]
	var re := RegEx.create_from_string("\\(\\s*([\\d.]+)\\s*to\\s*([\\d.]+)\\s*\\)")
	for p: Dictionary in _dash_data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = mat
		mi.layers = VISUAL_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.position = p.center
		holder.add_child(mi)
		_dash.add_child(holder)
		var pname: String = p.name
		# Parts are named by the views they show in (:F front, :L, :R, :B) and what they are:
		# ":F_MPH (0.0 to 0.63)" is the speedo needle, sweeping 0.63 of a turn.
		if pname.contains("_mph") or pname.contains("_rpm"):
			var m := re.search(pname)
			# Each needle turns about the car's length through its part's centre, clockwise as
			# the driver sees it: the needles are modelled with their hub on that line, often a
			# long way in front of or behind the centre, and tilted from the dial, so turning
			# about the needle's own normal swings it off its hub and through the dial's face.
			_dash_needles.append({"node": holder, "axis": Vector3.BACK, "rpm": pname.contains("_rpm"),
				"turns": (m.get_string(2).to_float() - m.get_string(1).to_float()) if m else 0.7})
		elif pname.contains("_w ") or pname.ends_with("_w"):
			_dash_wheel = holder
			var size: Vector3 = (p.mesh as Mesh).get_aabb().size
			# Its column: the wheel's thinnest direction.
			_dash_wheel_axis = Vector3.BACK if size.z <= minf(size.x, size.y) else (Vector3.RIGHT if size.x < size.y else Vector3.UP)
		elif pname.contains("_ldash"):
			# Over the day face (which stays, dark, behind its cut-outs): a hair nearer the
			# driver so the two don't fight, well behind the needles.
			mi.material_override = lit_mat
			holder.position.z -= 0.0015
			holder.visible = false
			_dash_lit.append(holder)


## How far the steering wheel is turned (radians, + clockwise as the driver sees it): it
## follows the road wheels, so it winds on gradually and turns less at speed, where they do;
## full lock at a standstill is a little over a third of a turn.
func wheel_turn() -> float:
	return -steer_angle / (max_steer * low_turn) * 2.4


## Needles and steering wheel of the in-car view.
func _update_dash() -> void:
	if _dash_wheel:
		_dash_wheel.basis = Basis(_dash_wheel_axis, wheel_turn())
	for n in _dash_needles:
		# The dials' scales aren't in the files: the speedo reads to a little past the car's top
		# speed, the rev counter to a quarter past its redline.
		var f := clampf(rpm / (redline * 1.25), 0.0, 1.0) if n.rpm else clampf(absf(speed) / (top_speed * 1.1), 0.0, 1.0)
		(n.node as Node3D).basis = Basis(n.axis, f * float(n.turns) * TAU)
	# The dials light up with the headlights after dark.
	var lit := headlights_on and Game.night
	if lit == _dash_lit_on:
		return
	_dash_lit_on = lit
	for l in _dash_lit:
		l.visible = lit
	for n in _dash_needles:
		((n.node as Node3D).get_child(0) as MeshInstance3D).material_override = _dash_mats[int(lit)]


## The body's mesh instances (not wheels or pop-up lamps), for CarDamage to dent.
func body_meshes() -> Array[MeshInstance3D]:
	return _body_meshes


## Lamp glows, lights and beams that sit on the bodywork, for CarDamage to move with a dent.
func fittings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	out.append_array(_lamps + _brake_lights + _reverse_lights + _beams + _plates)
	return out


## Per-wheel state for effects: "contact", "ground" and "normal" (world, valid while in
## contact), "hit" (the ray result, ditto), "slip" 0..1, "front", "left".
func wheel_states() -> Array[Dictionary]:
	return _wheels


func is_stuck_upside_down() -> bool:
	return _upside_timer > 2.5


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	far = cam != null and cam.global_position.distance_squared_to(global_position) > DETAIL_RANGE * DETAIL_RANGE
	if _siren:
		_siren_t += dt
		# Each lamp in its own time (see _flash_lit()); a colour's light shines while any of its
		# lamps does. Hidden, not dimmed: a light at zero energy still costs its culling and shading.
		var lit := {}
		for sg in _siren_glows:
			var on: bool = _flash_lit(sg[1], _siren_t)
			sg[0].visible = on
			if on:
				lit[sg[1].colour] = true
		for sl in _siren_lights:
			sl[0].visible = lit.has(sl[1])
		for w in _wigwags:
			w[0].visible = _flash_lit(w[1], _siren_t)
	if _dash and _dash.visible:
		_update_dash()
	if not _spoiler_up.is_empty():
		var v := absf(speed)
		if v > SPOILER_UP and not _spoiler_raised or v < SPOILER_DOWN and _spoiler_raised:
			_set_spoiler(not _spoiler_raised)
	# The driver turns his wheel as far as the in-car view's.
	if not (_steer_mats.is_empty() and _steer_shapes.is_empty()) and wheel_turn() != _steer_shown:
		_steer_shown = wheel_turn()
		for m in _steer_mats:
			m.set_shader_parameter("steer_angle", _steer_shown)
		for s in _steer_shapes:
			_pose_steer_shapes(s[0], s[1], _steer_shown)
	# Far off (or parked asleep) the wheels and body keep the pose they had.
	if far or freeze or resting:
		return
	# The body leans back under power, dips under braking and rolls out of a bend [45].
	var lean := Vector2(-_acc.y, _acc.x) * pitch_roll
	if body_sway:
		# On its springs: a softer-damped car [46] wallows more before it settles.
		var target := (lean * SWAY_GAIN).limit_length(SWAY_MAX)
		var omega := TAU * SWAY_HZ
		var zeta := SWAY_DAMPING * lerpf(1.2, 0.8, clampf(bumpiness, 0.0, 1.0))
		var h := minf(dt, 1.0 / 30.0)
		_tilt_vel += ((target - _tilt) * omega * omega - _tilt_vel * 2.0 * zeta * omega) * h
		_tilt += _tilt_vel * h
		_tilt = _tilt.limit_length(SWAY_MAX * 1.2)
	else:
		_tilt = lean * 0.005
		_tilt_vel = Vector2.ZERO
	# Leaning about the roll centre at axle height, so the roof swings out rather than the
	# sills digging in; it's the identity at rest, which keeps the parts car-local (CarDamage).
	var tilt_basis := Basis.from_euler(Vector3(_tilt.x, 0.0, _tilt.y))
	_body_tilt.transform = Transform3D(tilt_basis, _tilt_pivot - tilt_basis * _tilt_pivot)
	for w in _wheels:
		if not w.has("visual"):
			continue
		# Wheel centre sits `compression` above its fully-extended position, but never
		# further up than the arch allows: past that (a hard landing) the tyre dips into the
		# road rather than showing through the bodywork.
		var y: float = w.center.y + minf(w.compression, w.lift_max)
		w.visual.position.y = lerpf(w.visual.position.y, y, 1.0 - exp(-55.0 * dt))
		w.visual.rotation.y = steer_angle if w.front else 0.0
		w.spin_node.rotation.x = fmod(w.spin, TAU)


func _on_body_entered(other: Node) -> void:
	var impulse := linear_velocity.length()
	if other is Car:
		impulse = (linear_velocity - (other as Car).linear_velocity).length()
		# A heavier-hitting car shoves the other one aside [42].
		var car := other as Car
		var away := car.global_position - global_position
		away.y = 0.0
		if away.length() > 0.1:
			car.apply_central_impulse(away.normalized() * minf(impulse, 20.0) * car.mass * 0.02 * push_factor)
	if impulse > 4.0:
		crashed.emit(impulse)


## Stops simulating the car: it becomes a kinematic body whoever holds it moves by hand
## (AIController's far-off traffic).
func suspend() -> void:
	if resting:
		_wake()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	set_physics_process(false)
	slip = 0.0


## Back to driving after suspend(), moving at `velocity`.
func resume(velocity: Vector3) -> void:
	freeze = false
	set_physics_process(true)
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	_prev_vel = velocity
	speed = velocity.dot(global_basis.z)


func _wake() -> void:
	resting = false
	_rest_t = 0.0
	can_sleep = false
	sleeping = false


## Room above a tyre (hub `c`, radius `r`, half-width `hw`) before it meets the bodywork
## `faces`: the smallest vertical gap from the tread up to the body, over the tyre's footprint.
## Surfaces already cutting into the tyre (the arch's side lips) don't count.
static func arch_room(faces: PackedVector3Array, c: Vector3, r: float, hw: float) -> float:
	var room := INF
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var d := faces[i + 2]
		if maxf(a.y, maxf(b.y, d.y)) < c.y or minf(a.x, minf(b.x, d.x)) > c.x + hw \
				or maxf(a.x, maxf(b.x, d.x)) < c.x - hw or minf(a.z, minf(b.z, d.z)) > c.z + r \
				or maxf(a.z, maxf(b.z, d.z)) < c.z - r:
			continue
		# Barycentric coordinates in the triangle's ground-plane projection.
		var det := (b.z - d.z) * (a.x - d.x) + (d.x - b.x) * (a.z - d.z)
		if absf(det) < 1e-9:
			continue
		for sx in [-0.7, 0.0, 0.7]:
			for sz in [-0.7, -0.35, 0.0, 0.35, 0.7]:
				var px: float = c.x + hw * sx
				var pz: float = c.z + r * sz
				var u := ((b.z - d.z) * (px - d.x) + (d.x - b.x) * (pz - d.z)) / det
				var v := ((d.z - a.z) * (px - d.x) + (a.x - d.x) * (pz - d.z)) / det
				if u < 0.0 or v < 0.0 or u + v > 1.0:
					continue
				var top: float = c.y + r * sqrt(1.0 - sz * sz)
				var y := a.y * u + b.y * v + d.y * (1.0 - u - v)
				if y > top - 0.02:
					room = minf(room, y - top)
	return room

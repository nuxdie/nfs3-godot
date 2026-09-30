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
# Body sway: the springs already pitch and roll the car itself about as far as a real one
# (some 2.5 degrees a g); the bodywork only makes up the difference to its own [45], eased in
# at this rate (1/s) and never by more than this (rad).
const SWAY_SMOOTH := 12.0
const SWAY_MAX := 0.05
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
## s a Porsche Unleashed cabriolet takes to fold its top away or raise it.
const TOP_FOLD_TIME := 2.5
const SPOILER_DOWN := 4.2
## s the pop-up headlamps take to rise or go down; the lamps light once they're up.
const POPUP_TIME := 0.6
## s the Carreras' spoiler takes to rise or go down (through its frames, where it has them).
const SPOILER_TIME := 0.8
## Porsche Unleashed's wipers: s for a sweep up and back at full rain, and at the lightest
## (and the longest pause between sweeps there: intermittent).
const WIPE_FAST := 1.1
const WIPE_SLOW := 1.7
const WIPE_PAUSE := 2.5
## The indicators' cycle (s, lit for the first half), and when a car signals by itself: turning
## this hard (steer) below this speed (m/s), held this long (s) after.
const INDICATOR_CYCLE := 0.7
const INDICATE_STEER := 0.45
const INDICATE_SPEED := 12.0
const INDICATE_HOLD := 1.2
## Porsche Unleashed's doors, bonnet and boot (Nfs5Car.LID_GROUPS: 6 left door, 7 right, 8
## bonnet, 9 boot) and windows: s to open or close, and to wind a window down or up.
const LID_TIME := 0.9
const WINDOW_TIME := 2.0
## A hit this hard (share of a full one) within LATCH_REACH m of a door or lid springs its
## latch: it then hangs ajar (LATCH_AJAR radians) and swings on the car's motion, the bonnet
## blown up by the air as the car goes faster (full open by BONNET_BLOW_SPEED m/s), the
## others pressed shut by it.
const LATCH_BREAK := 0.55
const LATCH_REACH := 1.2
const LATCH_AJAR := 0.12
## What tears off (Porsche Unleashed's doors, lids, skirts, spoiler: _loose): a full hit square
## on a part takes this much of the way to losing it (a door or lid only goes once its latch
## has sprung), the sills less; and a sprung lid slamming against its stop faster than
## TEAR_SLAM (rad/s) wrenches its hinges by TEAR_SLAM_HURT per rad/s over.
const TEAR_HIT := 0.7
const TEAR_SILL := 0.45
const TEAR_REACH := 0.3
const TEAR_SLAM := 5.0
const TEAR_SLAM_HURT := 0.04
const BONNET_BLOW_SPEED := 45.0
## How hard it's raining or snowing where the camera is, 0..1 (Weather sets it): the wipers
## go and the fog lamps light with it.
static var precipitation := 0.0
const REST_AFTER := 1.0   # s an AI car is held motionless before it sleeps
## Whether brake and reversing lamps cast real light (Low quality: just the glowing lamps).
static var lamp_lights := true
static var _glow_tex: GradientTexture2D   # the lamp glows' soft disc, shared
static var _glint_mat: ShaderMaterial      # Porsche Unleashed's chrome glints (car_glint.gdshader), shared
static var _glint_frame := -1              # ... its sun last set this frame
static var _sun_ref: WeakRef               # the scene's sun (DirectionalLight3D), found once
## Porsche Unleashed's lamp glows use the game's own glare (Nfs5Car.fx("GLAR")), its star
## rays smaller than the plain disc's soft edge: drawn this much bigger.
const PU_GLARE_SCALE := 1.5
static var progressive_grip := true

# --- control inputs, written by a controller every physics frame
var throttle := 0.0
var brake := 0.0
var steer := 0.0          # -1 left .. +1 right
var handbrake := false
var hold := false         # parked: full brakes, never engages reverse
var horn := false
var shift_request := 0    # manual gearbox: +1 up, -1 down; cleared once the box can act on it

# --- telemetry
var speed := 0.0          # signed forward speed, m/s
var rpm := 1000.0
var gear := 1             # -1 reverse, 1..n forward
var manual := false       # shifted by shift_request, on the manual gearing (set_manual)
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
var final_drive := 3.8     # [79] (automatic) or [11] (manual)
var v2rpm := PackedFloat32Array()        # [76] or [7], per gear slot (R, N, 1..)
var ratios := PackedFloat32Array()       # [77] or [8], x gear ratio factor [63]
var gear_eff := PackedFloat32Array()     # [78] or [9]
var torque_curve := PackedFloat32Array() # [10], Nm every 256 rpm, x engine tuning [60]
var n_gears := 5           # [75] or [3], less reverse and neutral
## The file's two gearboxes, [automatic, manual]: {n_gears, final_drive, v2rpm, ratios, gear_eff}.
var _gearboxes: Array[Dictionary] = []
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
var _heave_acc := 0.0       # ... and up it, smoothed (a sprung lid bounces with it)
var _body_tilt: Node3D
var _tilt_pivot := Vector3.ZERO     # roll and pitch centre, car-local (at axle height)
var _tilt := Vector2.ZERO           # body pitch (x) and roll (y), rad
var _ride := Vector3.ZERO           # the body riding up on wheels past their arches: pitch, roll (rad), heave (m)
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
var _popup_moves: Array[Dictionary] = []   # each one's way down: {center, hinge, fold, sink} (see Nfs3Car.popup_lights)
var _popup_t := 1.0               # the pop-ups' pose: 0 down .. 1 up (the headlights start on)
var _popup_covers: Array[Node3D] = []   # Porsche Unleashed: the same lamps down, shown while they're off
var _spoiler_down: Array[Node3D] = []   # Porsche Unleashed: the Carrera's rear spoiler lowered...
var _spoiler_up: Array[Node3D] = []     # ... and raised, above SPOILER_UP until below SPOILER_DOWN
var _spoiler_raised := false
var _spoiler_moving: Array[MeshInstance3D] = []   # ... and on its way, by its blend shapes (frames)
var _spoiler_frames := 0
var _spoiler_t := 0.0                  # its pose: 0 down .. 1 up
var _wipers: Array = []                # [MeshInstance3D, frames]: Porsche Unleashed's wipers, parked (0) .. up (frames - 1)
var _wipe_t := 0.0                     # s into the current sweep (and pause), 0 parked
var _signals: Array = []               # [glow, side]: the indicators, side -1 left, 1 right (as `indicate`)
var _fog_glows: Array[Node3D] = []     # fog lamps, lit with the headlights in rain and snow
## The indicators, set by a controller: -1 left, 1 right, 2 all four (hazards), 0 none
## (the car signals by itself for a slow, tight turn).
var indicate := 0
## What opens (Porsche Unleashed): group -> {parts: [[MeshInstance3D, rest position]], hinge,
## axis, open (radians), t (0 shut .. 1 open), goal, centre, broken, angle, spin}; the windows
## by door: {parts, drop, t, goal}; the bays by the lid over them: [MeshInstance3D].
var _lids := {}
var _windows := {}
var _bays := {}
## What can be torn off: group (a lid's, or Nfs5Car.BUMPER_FRONT...) -> {nodes (every mesh that
## goes with it), box (theirs, car-local, shut), hurt (0 .. 1, off)}.
var _loose := {}
var _skin_mat: ShaderMaterial   # the skin's material, lit where the lamps' lenses are
var _lens_state := {}           # uniform -> value, as last set on it
var _indicate_auto := 0
var _indicate_hold := 0.0
var _indicator_t := 0.0
var _indicator_shown := 0
var _hood_up: Array[Node3D] = []       # Porsche Unleashed's cabriolets: the hood's frame and rear window, up...
var _hood_folded: Array[Node3D] = []   # ... the hood folded away, down...
var _hood_top: Array[MeshInstance3D] = []   # ... and the soft top, folding by its blend shapes (frames)
var _hood_frames := 0
var _top_t := 0.0                      # the top's pose: 0 raised .. _hood_frames - 1 folded
var fold_speed := 1.0                  # how fast the top folds (tools set 0 to hold a pose)
var top_down := false
var spoiler_raise := false               # the menu's showroom: the spoiler up whatever the speed
var _plates: Array[Node3D] = []   # the licence plate (High Stakes cars)
var _dash_data := {}              # the car file's in-car view (High Stakes' dash, built on first use; Porsche Unleashed's eye)
var _driver_mat: ShaderMaterial   # the people inside (car_driver.gdshader), or null
var _dash: Node3D                 # ...its dashboard, seats and doors, shown instead of the body
var _dash_needles: Array[Dictionary] = []   # {node, axis, turns, rpm}
var _cabin_on := false   # a Porsche Unleashed car's own cabin is the in-car view
var _cabin_mirror_glass: Array[Dictionary] = []   # its side mirrors' glass: {node, point, normal}
var _cabin_mirrors: Node3D   # ...their CarMirrors, made on first use, shown with the in-car view
var _dash_wheel: Node3D
var _dash_wheel_axis := Vector3.BACK
var _dash_lit: Array[Node3D] = []
var _dash_mats: Array[Material] = []   # the needles' materials: [by day, lit]
var _dash_lit_on := false
var _mirrors: CarMirrors           # the in-car view's side mirrors, or null
var _rear_mirror: Node3D           # the in-car view's rear-view mirror, made on first use, or null
## Whether the in-car view shows its rear-view mirror (the HUD's M; while it does, the HUD's
## own mirror stands down), and the car whose in-car view is showing, or null.
static var rear_mirror_wanted := true
static var in_car_view: Car
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
## The car's own outside, seen from inside it: drawn only by its side mirrors (CarMirrors).
const OWN_VIEW_LAYER := 32
## The in-car view's dashboard, seats and doors: everything but the side mirrors sees them.
const DASH_LAYER := 64
## The in-car mirrors' own glass and housings (the rear-view mirror's, the Porsche Unleashed
## side mirrors' bezels), which no mirror's view shows.
const REAR_MIRROR_LAYER := 128
## How wide the dark rim round a Porsche Unleashed mirror's glass is in the in-car view (m).
const MIRROR_BEZEL := 0.007
## Neither game models a rear-view mirror inside: one is hung at the top of the windscreen,
## on the car's centreline: its glass (m, rounded ends), housing rim and depth, and how far
## the glass sits below the windscreen's top and behind the glass there.
const REAR_MIRROR_SIZE := Vector2(0.25, 0.07)
const REAR_MIRROR_RIM := 0.008
const REAR_MIRROR_DEPTH := 0.03
const REAR_MIRROR_DROP := 0.065
const REAR_MIRROR_BACK := 0.075
## How far Porsche Unleashed's speedo and rev needles sweep, full scale (turns): the files
## don't say; their dials run about three quarters of the way round.
const CABIN_NEEDLE_TURNS := 0.75
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
		sm.set_shader_parameter("interior_paint", _interior_of(paint))
		mat = sm
		_skin_mat = sm
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
		_driver_mat = driver_mat
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
		match p.get("hood", ""):
			"up": _hood_up.append(mi)
			"down": _hood_folded.append(mi)
			"top":
				_hood_top.append(mi)
				_hood_frames = maxi(_hood_frames, int(p.get("hood_frames", 0)))
		match p.get("spoiler", ""):
			"down": _spoiler_down.append(mi)
			"up":
				_spoiler_up.append(mi)
				mi.visible = false
			"moving":
				_spoiler_moving.append(mi)
				_spoiler_frames = int(p.get("spoiler_frames", 0))
				mi.visible = false
		if p.has("wiper_frames"):
			_wipers.append([mi, int(p.wiper_frames)])
			_pose_frames(mi, 0.0)
		_body_tilt.add_child(mi)
		_add_opening(p, mi)
		_add_loose(p, mi)
		if p.has("bay"):
			continue   # (it doesn't dent: nobody sees it but through an open lid)
		if p.has("mirror_glass"):
			# Porsche Unleashed's side mirrors' glass: in the in-car view, CarMirrors shows the
			# view back on it (and the mirrors' own views leave it out, as the dash's: below).
			_cabin_mirror_glass.append({"node": mi, "point": p.mirror_glass.point, "normal": p.mirror_glass.normal})
			continue
		if p.has("needle"):
			# Porsche Unleashed's speedo and rev needles, turning about their hubs in the
			# in-car view (they don't dent).
			_dash_needles.append({"node": mi, "axis": p.axis, "rpm": p.needle == "rpm", "turns": CABIN_NEEDLE_TURNS,
				"zero": p.zero, "round_scale": true})
			continue
		_body_meshes.append(mi)
	if has_soft_top():
		set_top_down(Game.tops_down, true)
	for p in data.popup_lights:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if mat:
			mi.material_override = mat
		_body_tilt.add_child(mi)
		_popups.append(mi)
		# Without the game's word on how they move, they tip forward about their back edge
		# as they sink their own height, under the lids the body has.
		var bb: AABB = p.mesh.get_aabb()
		var move := {"center": p.center, "hinge": Vector3.ZERO, "fold": 0.0, "sink": 0.0}
		if p.has("sink") or p.has("fold"):
			for k in ["hinge", "fold", "sink"]:
				move[k] = p.get(k, move[k])
		else:
			move.hinge = p.center + Vector3(0.0, bb.position.y, bb.position.z)
			move.fold = 0.5
			move.sink = bb.size.y + 0.02
		_popup_moves.append(move)

	var hs: Vector3 = data.half_size
	_half_size = hs
	hood_z = hs.z + 0.1
	var wheel_parts: Array = data.wheels
	var body_faces := PackedVector3Array()
	for p in data.body_parts:
		if p.has("bay"):
			continue
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
	for box in _gearboxes:
		var r: PackedFloat32Array = box.ratios
		var v: PackedFloat32Array = box.v2rpm
		for i in mini(r.size(), v.size()):
			if r[i] == 0.0 and v[i] != 0.0 and box.final_drive > 0.0:
				r[i] = absf(v[i]) * TAU * _r_drive / 60.0 / box.final_drive
		box.ratios = r
	_use_gearbox(0)
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
	# ... set onto the bodywork (the pop-ups raised: their lamps shine only then).
	var lamp_faces := body_faces.duplicate()
	for p in data.popup_lights:
		for v in p.mesh.get_faces():
			lamp_faces.append(v + p.center)
	_seat_lamps(data.lights + heads + tails, lamp_faces)
	for l in heads:
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour], 0.32 * _lamp_size(l), 1.0)
		glow.set_meta("glint", [1.0, _colour_v(l.colour) * 2.5])
		glow.set_meta("lamp", l)
		_head_glows.append(glow)
		# Pursuit cars' headlamps flash in turn (wig-wag) while the siren is going.
		if l.flash != "N":
			_wigwags.append([glow, l])
	_lamps.append_array(_head_glows)
	# Running tail lamps, and the parking and marker lamps (P), dimmer, with the headlights.
	for l in tails + _lamps_of(data, "P"):
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour] * 0.45, 0.22 * _lamp_size(l), signf(l.pos.z))
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
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour], 0.3 * _lamp_size(l), -1.0)
		glow.set_meta("glint", [-1.0, _colour_v(l.colour) * 2.2])
		glow.set_meta("lamp", l)
		glow.visible = false
		_body_tilt.add_child(glow)
		_brake_lights.append(glow)
	# Indicators, each flashing with its side (+X is the driver's left), and fog lamps.
	for l in _indicator_lamps(data, heads, tails):
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour], 0.24 * _lamp_size(l), signf(l.pos.z))
		glow.set_meta("glint", [signf(l.pos.z), _colour_v(l.colour) * 1.2])
		glow.set_meta("lamp", l)
		glow.visible = false
		_body_tilt.add_child(glow)
		_signals.append([glow, -1 if l.pos.x >= 0.0 else 1])
	for l in _lamps_of(data, "F"):
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour], 0.28 * _lamp_size(l), signf(l.pos.z))
		glow.set_meta("glint", [signf(l.pos.z), _colour_v(l.colour) * 1.5])
		glow.set_meta("lamp", l)
		glow.visible = false
		_body_tilt.add_child(glow)
		_fog_glows.append(glow)
	# Reversing lamps: High Stakes marks them; on NFS3 cars, just inboard of the taillights.
	var reverses := _lamps_of(data, "R")
	if reverses.is_empty():
		for l in tails:
			var r := Nfs3Car.decode_light("RWYN350")
			r.pos = l.pos - Vector3(signf(l.pos.x) * 0.16, 0.03, 0.0)
			reverses.append(r)
		_seat_lamps(reverses, lamp_faces)
	for l in reverses:
		var glow := _lamp_glow(l.pos, LAMP_COLOURS[l.colour], 0.22 * _lamp_size(l), -1.0)
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
	if data is Nfs3Car:
		_car_effects(data)
	for g: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		g.layers = VISUAL_LAYER
	for m in _cabin_mirror_glass:
		(m.node as GeometryInstance3D).layers = DASH_LAYER


## Reads the car's carp.txt (see the tuning vars for which field is which). It lists an
## automatic gearbox [75..79] and a manual one [3], [7..9], [11]; each takes what it lacks
## from the other, and the car starts on the automatic (set_manual switches).
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
	var gear_factor: float = data.carp_value(63, 1.0)
	_gearboxes.clear()
	# Field numbers: gear count, speed-to-rpm, ratios, efficiency, final drive.
	var fields := [[75, 76, 77, 78, 79], [3, 7, 8, 9, 11]]
	for m in 2:
		var own: Array = fields[m]
		var other: Array = fields[1 - m]
		var box := {
			"final_drive": data.carp_value(own[4], data.carp_value(other[4], 3.8)),
			"v2rpm": _scaled(_table(carp, [own[1], other[1]], [-220, 0, 230, 150, 110, 88, 70, 0]), gear_factor),
			"ratios": _scaled(_table(carp, [own[2], other[2]], [2.1, 0, 2.3, 1.5, 1.12, 0.88, 0.7, 0]), gear_factor),
			"gear_eff": _table(carp, [own[3], other[3]], [0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85]),
		}
		var forward := 0
		for i in range(2, box.v2rpm.size()):
			if box.v2rpm[i] > 0.0:
				forward += 1
		box.n_gears = clampi(int(data.carp_value(own[0], data.carp_value(other[0], forward + 2.0))) - 2, 1, maxi(forward, 1))
		_gearboxes.append(box)
	_use_gearbox(0)
	torque_curve = _scaled(_table(carp, [10], [300.0]), data.carp_value(60, 1.0))
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


func _use_gearbox(i: int) -> void:
	var box := _gearboxes[i]
	final_drive = box.final_drive
	v2rpm = box.v2rpm
	ratios = box.ratios
	gear_eff = box.gear_eff
	n_gears = box.n_gears


## A driver who shifts by hand (the player, with the manual gearbox chosen): the car then
## changes gear only on shift_request, on the file's manual gearing.
func set_manual(on: bool) -> void:
	manual = on
	shift_request = 0
	if not _gearboxes.is_empty():
		_use_gearbox(int(on))
		gear = mini(gear, n_gears)


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


## Whether this car has a soft top to raise and lower (a Porsche Unleashed cabriolet).
func has_soft_top() -> bool:
	return not _hood_top.is_empty() and not _hood_folded.is_empty()


## Lowers or raises the soft top: it folds through its frames over TOP_FOLD_TIME (`now`:
## straight there).
func set_top_down(down: bool, now := false) -> void:
	if not has_soft_top():
		return
	top_down = down
	# (The side windows go down with the top, as they're driven.)
	for side: int in _windows:
		set_window_down(side, down, now)
	if now or _hood_frames < 2:
		_top_t = float(_hood_frames - 1) if down else 0.0
	_pose_top()


## Moves the top a step toward where top_down wants it.
func _fold_top(dt: float) -> void:
	var goal := float(_hood_frames - 1) if top_down else 0.0
	if _top_t == goal:
		return
	_top_t = move_toward(_top_t, goal, dt * fold_speed * (_hood_frames - 1) / TOP_FOLD_TIME)
	_pose_top()


## The top at _top_t, between two of its frames; the hood's frame and rear window only while
## it's fully up, the folded hood only once it's all the way down.
func _pose_top() -> void:
	var last := float(maxi(_hood_frames - 1, 0))
	var k := mini(int(_top_t), maxi(_hood_frames - 2, 0))
	var f := _top_t - k
	for mi in _hood_top:
		mi.visible = _top_t < last
		for i in mi.get_blend_shape_count():
			mi.set_blend_shape_value(i, 1.0 - f if i == k else f if i == k + 1 else 0.0)
	for mi in _hood_up:
		mi.visible = _top_t == 0.0
	for mi in _hood_folded:
		mi.visible = _top_t >= last


## Porsche Unleashed's effects: the game's glare on the lamps, the sun's glints off the
## chrome (a mesh per door or lid they ride on, posed with it), the exhaust (CarExhaust).
func _car_effects(data: Nfs3Car) -> void:
	var pu := data is Nfs5Car
	if not pu:
		_mark_lenses(data)
	var glare := Nfs5Car.fx("GLAR") if pu else null
	if glare:
		var glows: Array = _lamps + _brake_lights + _reverse_lights + _fog_glows
		for sg in _signals:
			glows.append(sg[0])
		for g in glows:
			if g is MeshInstance3D and (g as MeshInstance3D).mesh is QuadMesh:
				var q := (g as MeshInstance3D).mesh as QuadMesh
				(q.material as ShaderMaterial).set_shader_parameter("glow_tex", glare)
				q.size *= PU_GLARE_SCALE
	var glint := Nfs5Car.fx("GLNT")
	if glint == null:
		glint = _star_texture()
	# The other cars mark no chrome: the sun glints off their wheels' hubs.
	var glints: Array[Dictionary] = data.glints
	if not pu:
		glints = []
		for w in _wheels:
			var side := 1.0 if w.left else -1.0
			glints.append({"pos": w.center + Vector3(side * 0.1, STATIC_SAG, 0.0), "facing": Vector3(side, 0.15, 0.0).normalized(), "lid": 0})
	if not glints.is_empty():
		if _glint_mat == null:
			_glint_mat = ShaderMaterial.new()
			_glint_mat.shader = preload("res://shaders/car_glint.gdshader")
			_glint_mat.set_shader_parameter("glint_tex", glint)
		var by_lid := {}
		for gl: Dictionary in glints:
			if not by_lid.has(gl.lid):
				by_lid[gl.lid] = []
			by_lid[gl.lid].append(gl)
		for lid: int in by_lid:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 0
			for gl: Dictionary in by_lid[lid]:
				var phase := Color(randf(), 0.0, 0.0)
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
					st.set_color(phase)
					st.set_normal(gl.facing)
					st.set_uv(corner)
					st.add_vertex(gl.pos)
				n += 1
			var mi := MeshInstance3D.new()
			mi.name = "Glints"
			mi.mesh = st.commit()
			mi.material_override = _glint_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 0.5
			_body_tilt.add_child(mi)
			if _lids.has(lid):
				_lids[lid].parts.append([mi, Vector3.ZERO])
			if _loose.has(lid):
				_loose[lid].nodes.append(mi)
	# Without their pipes marked (NFS3's, most of High Stakes'), a pair under the back bumper.
	var pipes: Array[Vector3] = data.exhausts
	if pipes.is_empty() and not _wheels.is_empty():
		var y: float = _wheels[2].center.y - 0.02
		var z := -_half_size.z + 0.06
		pipes = [Vector3(_half_size.x * 0.45, y, z), Vector3(-_half_size.x * 0.45, y, z)]
	if not pipes.is_empty():
		var ex: Node3D = preload("res://scripts/vehicle/car_exhaust.gd").new()
		ex.name = "Exhaust"
		ex.pipes = pipes
		_body_tilt.add_child(ex)


## The car's indicators: Porsche Unleashed's own (I); High Stakes' amber and yellow parking
## and marker lamps (P), which sit at the corners where they go; else, as on NFS3's cars, a
## lamp just outboard of each outer headlamp and tail lamp.
static func _indicator_lamps(data: Object, heads: Array, tails: Array) -> Array[Dictionary]:
	var out := _lamps_of(data, "I")
	if not out.is_empty() or data is Nfs5Car:
		return out
	for l in _lamps_of(data, "P"):
		if l.colour in ["O", "Y"]:
			var i := Nfs3Car.decode_light("IOYN")
			i.pos = l.pos
			i.intensity = l.intensity
			out.append(i)
	if not out.is_empty() or not "lights" in data:
		return out
	for set: Array in [heads, tails]:
		if set.size() < 2:
			continue
		for l: Dictionary in _outer_pair(set):
			var i := Nfs3Car.decode_light("IOYN")
			i.pos = l.pos + Vector3(signf(l.pos.x) * 0.1, 0.0, 0.0)
			i.intensity = 3
			out.append(i)
	return out


## The lamps' lenses on an NFS3 or High Stakes model, which marks none: the vertices near each
## lamp dummy take COLOR (0, 1, 1) (car.gdshader lights them with it; the rest white, as
## meshes without colours read), once per model.
const LENS_REACH := 0.14


static func _mark_lenses(data: Nfs3Car) -> void:
	if data.has_meta("lenses") or data.lights.is_empty():
		return
	data.set_meta("lenses", true)
	var lamps: Array[Vector4] = []
	for l: Dictionary in data.lights:
		if l.kind in ["H", "T", "B", "R", "P"] and l.intensity > 0:
			lamps.append(Vector4(l.pos.x, l.pos.y, l.pos.z, LENS_REACH * clampf(l.intensity / 5.0, 0.7, 1.5)))
	for p: Dictionary in data.body_parts:
		if p.get("glass", false) or p.get("driver", false) or not p.mesh is ArrayMesh:
			continue
		var mesh: ArrayMesh = p.mesh
		if mesh.get_blend_shape_count() > 0:
			continue
		var surfaces := []
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var cols := PackedColorArray()
			cols.resize(verts.size())
			cols.fill(Color.WHITE)
			var any := false
			for i in verts.size():
				var v: Vector3 = verts[i] + p.center
				for lp in lamps:
					if v.distance_squared_to(Vector3(lp.x, lp.y, lp.z)) < lp.w * lp.w:
						cols[i] = Color(0.0, 1.0, 1.0)
						any = true
						break
			if any:
				arrays[Mesh.ARRAY_COLOR] = cols
			surfaces.append([mesh.surface_get_primitive_type(si), arrays, mesh.surface_get_material(si)])
		mesh.clear_surfaces()
		for sf in surfaces:
			mesh.add_surface_from_arrays(sf[0], sf[1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, sf[2])


## A four-pointed star for the glints where Porsche Unleashed's (GLNT) isn't to be had.
static func _star_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5) / 15.5
			var a := clampf(1.0 - d.length(), 0.0, 1.0)
			var rays := maxf(clampf(1.0 - absf(d.x) * 8.0, 0.0, 1.0), clampf(1.0 - absf(d.y) * 8.0, 0.0, 1.0))
			var v := clampf(a * a * 1.5 + rays * a, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	return ImageTexture.create_from_image(img)


## Points the glints' sun where the scene's is (once a frame, for every car): none at night.
static func _aim_glints(tree: SceneTree) -> void:
	if _glint_mat == null or _glint_frame == Engine.get_process_frames():
		return
	_glint_frame = Engine.get_process_frames()
	var sun: DirectionalLight3D = _sun_ref.get_ref() if _sun_ref else null
	if (sun == null or not sun.is_inside_tree()) and _glint_frame % 30 == 0:
		sun = null
		for l in tree.root.find_children("*", "DirectionalLight3D", true, false):
			if (l as DirectionalLight3D).visible:
				sun = l
				break
		_sun_ref = weakref(sun) if sun else null
	if sun == null or not sun.visible or Game.night:
		_glint_mat.set_shader_parameter("sun_energy", 0.0)
		return
	_glint_mat.set_shader_parameter("sun_dir", sun.global_basis.z.normalized())
	_glint_mat.set_shader_parameter("sun_energy", clampf(sun.light_energy, 0.0, 1.5))


## Files a Porsche Unleashed part that opens (Nfs5Car's "lid", "window" and "bay" keys).
func _add_opening(p: Dictionary, mi: MeshInstance3D) -> void:
	if p.has("lid"):
		var g: int = p.lid
		if not _lids.has(g):
			_lids[g] = {"parts": [], "hinge": p.hinge, "axis": p.axis, "open": p.open, "t": 0.0, "goal": 0.0,
				"centre": Vector3.ZERO, "broken": false, "angle": 0.0, "spin": 0.0, "n": 0}
		if not p.has("window"):
			_lids[g].parts.append([mi, p.center])
			if not p.has("spoiler") and not p.has("mirror_glass"):
				var c: Vector3 = p.center + p.mesh.get_aabb().get_center()
				_lids[g].centre = (_lids[g].centre * _lids[g].n + c) / (_lids[g].n + 1)
				_lids[g].n += 1
	if p.has("window"):
		var w: int = p.window
		if not _windows.has(w):
			_windows[w] = {"parts": [], "drop": p.drop, "t": 0.0, "goal": 0.0}
		_windows[w].parts.append([mi, p.center])
	if p.has("bay"):
		if not _bays.has(p.bay):
			_bays[p.bay] = []
		_bays[p.bay].append(mi)
		mi.visible = false


## Whether this car has `what` to open (Nfs5Car.DOOR_LEFT, DOOR_RIGHT, BONNET or BOOT).
func can_open(what: int) -> bool:
	return _lids.has(what)


func is_open(what: int) -> bool:
	return _lids.has(what) and _lids[what].goal > 0.0


## Opens or shuts a door, the bonnet or the boot over LID_TIME (`now`: straight there). One
## whose latch a crash sprang shuts again (repaired) when told to.
func set_open(what: int, open: bool, now := false) -> void:
	if not _lids.has(what):
		return
	var l: Dictionary = _lids[what]
	l.goal = 1.0 if open else 0.0
	if not open:
		l.broken = false
	if now:
		l.t = l.goal
		l.angle = l.open * l.t
		l.spin = 0.0
	_pose_lid(what)


## Winds a door's window (the door's group) down or up over WINDOW_TIME.
func set_window_down(side: int, down: bool, now := false) -> void:
	if not _windows.has(side):
		return
	_windows[side].goal = 1.0 if down else 0.0
	if now:
		_windows[side].t = _windows[side].goal
	_pose_lid(side)


func has_windows() -> bool:
	return not _windows.is_empty()


## A crash at car-local `p`, `s` of a full hit (CarDamage): springs the latch of a door or lid
## near enough to it.
func latch_hit(p: Vector3, s: float) -> void:
	if s < LATCH_BREAK:
		return
	for g: int in _lids:
		var l: Dictionary = _lids[g]
		if not l.broken and l.goal == 0.0 and (l.centre as Vector3).distance_to(p) < LATCH_REACH:
			l.broken = true
			l.spin = randf_range(1.0, 3.0) * signf(l.open)


## Files a Porsche Unleashed part that a crash can tear off, with its door or lid ("lid") and
## as a part of its own ("loose": the skirts, the spoiler).
func _add_loose(p: Dictionary, mi: MeshInstance3D) -> void:
	if p.has("spoiler"):
		mi.set_meta("spoiler", true)
	for key in ["lid", "loose"]:
		if not p.has(key):
			continue
		var g: int = p[key]
		var box: AABB = p.mesh.get_aabb()
		box.position += p.center
		if not _loose.has(g):
			_loose[g] = {"nodes": [], "box": box, "hurt": 0.0}
		_loose[g].nodes.append(mi)
		_loose[g].box = (_loose[g].box as AABB).merge(box)


## A crash at car-local `p` reaching `radius`, `s` of a full hit (CarDamage): the parts near
## it closer to coming off, and off if that was enough.
func loose_hit(p: Vector3, radius: float, s: float) -> void:
	for g: int in _loose.keys():
		if not _loose.has(g):
			continue   # (gone with another: the spoiler with the boot)
		var l: Dictionary = _loose[g]
		var box: AABB = l.box
		var reach := radius + TEAR_REACH
		var d := (p.clamp(box.position, box.end) - p).length()
		if d >= reach:
			continue
		var f := 1.0 - d / reach
		l.hurt += s * s * f * (TEAR_SILL if g in [Nfs5Car.SILL_LEFT, Nfs5Car.SILL_RIGHT] else TEAR_HIT)
		if l.hurt >= 1.0 and not far and (not _lids.has(g) or _lids[g].broken):
			tear_off(g)


## Group `g`'s parts come off the car and go their own way (CarDebris): a door takes its
## window and mirror, the boot its spoiler; the bay under a lost lid is left open.
func tear_off(g: int) -> void:
	if not _loose.has(g):
		return
	var nodes: Array = _loose[g].nodes
	_loose.erase(g)
	for o: int in _loose.keys():
		var left: Array = _loose[o].nodes.filter(func(n: Node) -> bool: return not n in nodes)
		if left.is_empty():
			_loose.erase(o)
		else:
			_loose[o].nodes = left
	_lids.erase(g)
	_windows.erase(g)
	for mi: Node3D in _bays.get(g, []):
		mi.visible = true   # (the bay on the car, the lid's underside on the piece)
	_bays.erase(g)
	var keep := func(n: Node) -> bool: return not n in nodes
	_body_meshes.assign(_body_meshes.filter(keep))
	_spoiler_up.assign(_spoiler_up.filter(keep))
	_spoiler_down.assign(_spoiler_down.filter(keep))
	_spoiler_moving.assign(_spoiler_moving.filter(keep))
	_cabin_mirror_glass.assign(_cabin_mirror_glass.filter(func(m: Dictionary) -> bool: return not m.node in nodes))
	# (Without its spoiler the back loses the downforce it gave.)
	if nodes.any(func(n: Node) -> bool: return n.has_meta("spoiler")):
		spoiler_type = 0
	CarDebris.launch(self, nodes)


## The doors, lids and windows a step on: toward where they're told, or, with the latch
## sprung, swinging on their hinges: pulled back toward ajar, flung by the body's motion.
func _move_openings(dt: float) -> void:
	for g: int in _lids:
		var l: Dictionary = _lids[g]
		var before: float = l.angle
		if l.broken and l.goal == 0.0:
			var full: float = absf(l.open)
			var rest := LATCH_AJAR
			var v := absf(speed)
			if g == Nfs5Car.BONNET:
				rest = lerpf(LATCH_AJAR, full, clampf(v / BONNET_BLOW_SPEED, 0.0, 1.0) ** 2)
			else:
				rest = LATCH_AJAR * clampf(1.0 - v / 15.0, 0.0, 1.0)
			# The body's lurches: a door swings out as the car turns away from its side, a lid
			# bounces with the heave.
			var shove := 0.0
			if g in [Nfs5Car.DOOR_LEFT, Nfs5Car.DOOR_RIGHT]:
				shove = _acc.x * (-1.0 if g == Nfs5Car.DOOR_LEFT else 1.0) * 0.6
			else:
				shove = -_heave_acc * 0.25
			var a := absf(l.angle)
			var w: float = l.spin * signf(l.open)
			w += ((rest - a) * 40.0 - w * 3.0 + shove) * dt
			a += w * dt
			if a < 0.0:
				a = 0.0
				w = -w * 0.35
			elif a > full:
				a = full
				if absf(w) > TEAR_SLAM and _loose.has(g):
					_loose[g].hurt += (absf(w) - TEAR_SLAM) * TEAR_SLAM_HURT
					if _loose[g].hurt >= 1.0 and not far:
						tear_off.call_deferred(g)
				w = -w * 0.3
			l.angle = a * signf(l.open)
			l.spin = w * signf(l.open)
			l.t = a / full
		elif l.t != l.goal:
			l.t = move_toward(l.t, l.goal, dt / LID_TIME)
			l.angle = l.open * smoothstep(0.0, 1.0, l.t)
		if l.angle != before:
			_pose_lid(g)
	for side: int in _windows:
		var w: Dictionary = _windows[side]
		if w.t != w.goal:
			w.t = move_toward(w.t, w.goal, dt / WINDOW_TIME)
			_pose_lid(side)


## A door or lid (and its window) where its angle has it, and the bay under a lid shown
## while it's open.
func _pose_lid(g: int) -> void:
	var b := Basis.IDENTITY
	var hinge := Vector3.ZERO
	if _lids.has(g):
		var l: Dictionary = _lids[g]
		b = Basis(l.axis, l.angle)
		hinge = l.hinge
		for pm in l.parts:
			(pm[0] as Node3D).transform = Transform3D(b, hinge + b * (pm[1] - hinge))
		for mi in _bays.get(g, []):
			mi.visible = absf(l.angle) > 0.01
	if _windows.has(g):
		var w: Dictionary = _windows[g]
		var drop: Vector3 = w.drop * smoothstep(0.0, 1.0, w.t)
		for pm in w.parts:
			(pm[0] as Node3D).transform = Transform3D(b, hinge + b * (pm[1] + drop - hinge))


## Sets one of the skin's lamp-lens uniforms (car.gdshader), when it changes.
func _set_lens(uniform: String, value: float) -> void:
	if _skin_mat == null or _lens_state.get(uniform, -1.0) == value:
		return
	_lens_state[uniform] = value
	_skin_mat.set_shader_parameter(uniform, value)


## The spoiler at _spoiler_t: lowered, raised, or between them through its frames (without
## them it just goes from one to the other halfway). With frames it stays on the last one
## when up: the raised model maps its underside anew (the grille's louvres, a painted fan)
## where the frames have the dark gap they rose through.
func _pose_spoiler() -> void:
	var moving := _spoiler_t > 0.0 and not _spoiler_moving.is_empty()
	var up := _spoiler_t >= 0.5 and _spoiler_moving.is_empty()
	for mi in _spoiler_up:
		mi.visible = up and not moving
	for mi in _spoiler_down:
		mi.visible = not up and not moving
	for mi in _spoiler_moving:
		mi.visible = moving
		if moving:
			_pose_frames(mi, smoothstep(0.0, 1.0, _spoiler_t) * (_spoiler_frames - 1))


## Poses a part by its blend shapes, a frame each: at `f`, between two of them.
static func _pose_frames(mi: MeshInstance3D, f: float) -> void:
	var n := mi.get_blend_shape_count()
	if n == 0:
		return
	var k := clampi(int(f), 0, maxi(n - 2, 0))
	var t := clampf(f - k, 0.0, 1.0)
	for i in n:
		mi.set_blend_shape_value(i, 1.0 - t if i == k else t if i == k + 1 else 0.0)


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
			if m.get_shader_parameter("interior_paint") != null:
				m.set_shader_parameter("interior_paint", _interior_of(c))
			done[m] = true


## The cabin colour that goes with `paint`, one of the car's colours (Porsche Unleashed's
## pair each paint with an interior), or transparent: the cabin as the skin has it.
func _interior_of(paint: Color) -> Color:
	if car_data == null or not "interior_colours" in car_data or car_data.interior_colours.is_empty():
		return Color(0, 0, 0, 0)
	var i := maxi(car_data.colours.find(paint), 0)
	return car_data.interior_colours[mini(i, car_data.interior_colours.size() - 1)]


## Switches the headlights (and the tail lamps with them). Pop-up headlamps rise first and
## go down after, over POPUP_TIME (`now`: straight there).
func set_headlights(on: bool, now := false) -> void:
	headlights_on = on
	if now or _popups.is_empty():
		_popup_t = 1.0 if on else 0.0
		_pose_popups()
	_show_lamps()


func _show_lamps() -> void:
	var heads := headlights_on and _popup_t == 1.0
	_set_lens("head_lit", 1.0 if heads else 0.0)
	_set_lens("tail_lit", 1.0 if headlights_on else 0.0)
	for i in _beams.size():
		_beams[i].visible = heads and _beam_allowed and (i > 0) == _split_beams and not _beam_broken(i)
	for l in _lamps:
		l.visible = heads if _head_glows.has(l) else headlights_on


## The pop-ups at _popup_t: each turned about its hinge and let down by its share of the way;
## Porsche Unleashed's own lamps-down parts (the covers) shown once they're all the way down.
func _pose_popups() -> void:
	var down := 1.0 - smoothstep(0.0, 1.0, _popup_t)
	for i in _popups.size():
		var m := _popup_moves[i]
		var b := Basis(Vector3.RIGHT, m.fold * down)
		_popups[i].transform = Transform3D(b, m.center + m.hinge - b * m.hinge + Vector3(0.0, -m.sink * down, 0.0))
		_popups[i].visible = _popup_t > 0.0
	for l in _popup_covers:
		l.visible = _popup_t == 0.0


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
	var glows: Array = _lamps + _brake_lights + _reverse_lights + _fog_glows
	for sg in _siren_glows + _signals:
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


## Lamps sit this far (m) at most in front of the bodywork behind them, as seen along the car.
const LAMP_SEAT_REACH := 0.3


## Sets each lamp onto the outside of the bodywork straight behind it along the car: the light
## dummies float up to 15 cm clear of their lenses (High Stakes' 550 Maranello's the most),
## and the reversing lamps made up for NFS3's cars sink in where the tail wraps round. A lamp
## LAMP_SEAT_REACH or more in front of anything, or set in behind a lip or spoiler further
## out than OUT, stays put; one seated already (the car data's lamps are shared by its
## cars) isn't looked at again.
static func _seat_lamps(lamps: Array, faces: PackedVector3Array) -> void:
	var todo: Array[Dictionary] = []
	for l: Dictionary in lamps:
		if not l.get("seated", false) and l.kind != "S":
			l["seated"] = true
			todo.append(l)
	if todo.is_empty():
		return
	const OUT := 0.1   # the rays start this far out, so a lamp just under the skin finds it
	var depth := PackedFloat32Array()
	depth.resize(todo.size())
	depth.fill(INF)
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		for k in todo.size():
			var p: Vector3 = todo[k].pos
			if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
				continue
			var inward := Vector3(0, 0, -signf(p.z))
			var hit: Variant = Geometry3D.ray_intersects_triangle(p - inward * OUT, inward, a, b, c)
			if hit != null:
				depth[k] = minf(depth[k], (hit as Vector3).distance_to(p - inward * OUT))
	for k in todo.size():
		if depth[k] < LAMP_SEAT_REACH + OUT:
			var l := todo[k]
			l.pos -= Vector3(0, 0, signf(l.pos.z) * (depth[k] - OUT))


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


## A small camera-facing additive sprite: reads as a lit lamp in daylight without costing a
## light. Centred on the lamp; car_lamp.gdshader keeps the bodywork round it from cutting it.
static func _lamp_glow(pos: Vector3, colour: Color, size: float, facing := 0.0) -> MeshInstance3D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.9))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(0.5, 0.0)
		_glow_tex.width = 32
		_glow_tex.height = 32
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/car_lamp.gdshader")
	m.set_shader_parameter("glow_tex", _glow_tex)
	m.set_shader_parameter("colour", colour)
	m.set_shader_parameter("facing", facing)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size
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
	var glows: Array = _lamps + _brake_lights + _reverse_lights + _fog_glows
	for sg in _siren_glows + _signals:
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
	_signals = _signals.filter(func(sg: Array) -> bool: return keep.call(sg[0]))
	_fog_glows.assign(_fog_glows.filter(keep))
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
	_ride = Vector3.ZERO
	was_reset.emit()


func _torque_at(r: float) -> float:
	if torque_curve.is_empty():
		return 300.0
	var f := clampf(r / 256.0, 0.0, torque_curve.size() - 1.001)
	var i := int(f)
	return lerpf(torque_curve[i], torque_curve[mini(i + 1, torque_curve.size() - 1)], f - i)


func _gear_index(g: int) -> int:
	return 0 if g < 0 else g + 1


func _shift(to: int) -> void:
	var up := to > gear
	gear = to
	_shift_timer = shift_delay
	# Heel-and-toe: braking into the lower gear blips the throttle to match the revs.
	_blip = _at(brake_blip if not up and _brake_pedal > 0.1 else shift_blip, _gear_index(gear), 0.0)


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
	_heave_acc = lerpf(_heave_acc, clampf(acc.dot(global_basis.y), -30.0, 30.0), 1.0 - exp(-dt * 12.0))

	# --- gearbox (automatic, or by hand) and reverse
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
	if manual and _shift_timer <= 0.0 and shift_request != 0:
		# By hand: up to top gear, down only where the lower gear won't over-rev, and down
		# from 1st (or up from reverse) near a standstill.
		if gear < 0:
			if shift_request > 0 and speed > -1.0:
				gear = 1
		elif shift_request > 0:
			if gear < n_gears:
				_shift(gear + 1)
		elif gear > 1:
			if abs_speed * v2rpm[_gear_index(gear - 1)] < redline:
				_shift(gear - 1)
		elif abs_speed < 1.0:
			gear = -1
		shift_request = 0
	elif not manual and gear > 0 and _shift_timer <= 0.0:
		var r := abs_speed * v2rpm[_gear_index(gear)]
		if r > redline * 0.94 and gear < n_gears:
			_shift(gear + 1)
		elif gear > 1 and abs_speed * v2rpm[_gear_index(gear - 1)] < redline * 0.7:
			_shift(gear - 1)
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
		_set_lens("brake_lit", 1.0 if braking_lit else 0.0)
		_set_lens("reverse_lit", 1.0 if _reversing_lit else 0.0)


func has_cockpit() -> bool:
	return not _dash_data.is_empty()


## The driver's eye, car-local, for the in-car view. In a cabin of the car's own model it
## sways with the body, so the dash doesn't swing into the view.
func cockpit_eye() -> Vector3:
	var eye: Vector3 = _dash_data.get("eye", Vector3(0.4, 0.45, -0.3))
	if _dash_data.get("own_cabin", false):
		return global_transform.affine_inverse() * _body_tilt.global_transform * eye
	return eye


## The in-car view: the dashboard, seats and doors instead of the body and wheels (the
## camera sits inside them), which only the side mirrors still draw. A Porsche Unleashed
## car has its cabin in its own model: that stays, and only the driver's head goes. False
## when the car file has none.
func set_cockpit(on: bool) -> bool:
	if _dash_data.is_empty():
		return false
	if on:
		in_car_view = self
	elif in_car_view == self:
		in_car_view = null
	if _dash_data.get("own_cabin", false):
		_cabin_on = on
		if _driver_mat:
			_driver_mat.set_shader_parameter("hide_head", on)
		if on and _cabin_mirrors == null:
			_cabin_mirrors = Node3D.new()
			_cabin_mirrors.name = "Mirrors"
			_body_tilt.add_child(_cabin_mirrors)
			if not _cabin_mirror_glass.is_empty():
				var glass: Array[Dictionary] = []
				for g in _cabin_mirror_glass:
					glass.append(_bezel_glass(g, _cabin_mirrors))
				var mirrors := CarMirrors.new()
				_cabin_mirrors.add_child(mirrors)
				mirrors.setup(self, glass, _dash_data.eye, _half_size)
			_build_rear_mirror(_cabin_mirrors, _body_tilt, _dash_data.eye)
		if _cabin_mirrors:
			_cabin_mirrors.visible = on
		return true
	if on and _dash == null:
		_build_dash()
		_build_rear_mirror(_dash, self, cockpit_eye())
	if _dash:
		_dash.visible = on
	var outside: Array = _body_meshes + _popups + _plates
	for w in _wheels:
		if w.has("visual"):
			outside.append_array((w.visual as Node).find_children("*", "GeometryInstance3D", true, false))
	for g: GeometryInstance3D in outside.filter(func(n: Node) -> bool: return n is GeometryInstance3D):
		if not g.has_meta("shadow"):
			g.set_meta("shadow", g.cast_shadow)
		g.layers = OWN_VIEW_LAYER if on else VISUAL_LAYER
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else g.get_meta("shadow")
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
	var glass: Array[Dictionary] = []
	for p: Dictionary in _dash_data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = mat
		mi.layers = DASH_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.position = p.center
		holder.add_child(mi)
		_dash.add_child(holder)
		if p.has("glass"):
			var g := MeshInstance3D.new()
			g.mesh = p.glass.mesh
			g.material_override = mat
			g.layers = DASH_LAYER
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(g)
			glass.append({"node": g, "point": p.center + p.glass.point, "normal": p.glass.normal})
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
	if not glass.is_empty():
		_mirrors = CarMirrors.new()
		_mirrors.name = "Mirrors"
		_dash.add_child(_mirrors)
		_mirrors.setup(self, glass, cockpit_eye(), _half_size)


## The rear-view mirror, under `parent` (at the origin of `space`, the car or its body; the
## eye `eye` in `space`). A Porsche Unleashed cabin mostly has one modelled on the
## centreline, under the roof (or on the dash top, the 356's): its glass, a small flat patch
## facing the eye, is taken for the mirror's. Anywhere else one is hung from the windscreen's top on the centreline, found by
## casting rays ahead from the eye at rising heights: their hits come nearer smoothly up the
## leaning glass, until they pass over the car or meet the roof's lining, a jump nearer.
## Either glass is taken as turned to show the eye what lies straight behind.
func _build_rear_mirror(parent: Node3D, space: Node3D, eye: Vector3) -> void:
	var inv := space.global_transform.affine_inverse()
	var tris := PackedVector3Array()   # near the centreline, ahead of and above the eye
	var meshes: Array = _body_meshes.duplicate()
	if _dash:
		meshes.append_array(_dash.find_children("*", "MeshInstance3D", true, false))
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null or not mi.is_inside_tree():
			continue
		var xf := inv * mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size() - 2, 3):
			var a := xf * f[i]
			var b := xf * f[i + 1]
			var c := xf * f[i + 2]
			if minf(a.x, minf(b.x, c.x)) > 0.15 or maxf(a.x, maxf(b.x, c.x)) < -0.15 \
					or maxf(a.z, maxf(b.z, c.z)) < eye.z + 0.15 or maxf(a.y, maxf(b.y, c.y)) < eye.y - 0.1:
				continue
			tris.append_array([a, b, c])
	_rear_mirror = Node3D.new()
	_rear_mirror.name = "RearMirror"
	parent.add_child(_rear_mirror)
	var glass := MeshInstance3D.new()
	var glass_at: Vector3
	var model_glass := _model_rear_glass(tris, eye)
	if not model_glass.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lift := (eye - (model_glass.point as Vector3)).normalized() * 0.002
		for v: Vector3 in model_glass.faces:
			st.add_vertex(v + lift)
		glass.mesh = st.commit()
		glass_at = model_glass.point
	else:
		glass_at = _hang_rear_mirror(tris, eye)
	var back := Vector3(0.0, -sin(CarMirrors.AIM_DOWN), -cos(CarMirrors.AIM_DOWN))
	var n := ((eye - glass_at).normalized() + back).normalized()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.15)
	dark.metallic = 0.8
	dark.roughness = 0.15
	glass.material_override = dark
	_rear_mirror.add_child(glass)
	if not model_glass.is_empty():
		# The model's glass is its housing's whole face: framed as the side mirrors are.
		var framed := _bezel_glass({"node": glass, "point": glass_at, "normal": n}, _rear_mirror)
		glass.free()
		glass = framed.node
	else:
		var x_axis := Vector3.UP.cross(n).normalized()
		var basis := Basis(x_axis, n.cross(x_axis), n)
		glass.mesh = _rounded_slab(REAR_MIRROR_SIZE, 0.0)
		glass.transform = Transform3D(basis, glass_at)
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.045, 0.045, 0.05)
		shell.roughness = 0.55
		var housing := MeshInstance3D.new()
		housing.mesh = _rounded_slab(REAR_MIRROR_SIZE + Vector2.ONE * REAR_MIRROR_RIM * 2.0, REAR_MIRROR_DEPTH)
		housing.material_override = shell
		housing.transform = Transform3D(basis, glass_at - n * 0.001)
		_rear_mirror.add_child(housing)
		# Its stalk, from the housing's back up to where the windscreen meets the roof.
		var stem_from := glass_at - n * REAR_MIRROR_DEPTH + basis.y * (REAR_MIRROR_SIZE.y * 0.25)
		var stem_to: Vector3 = _rear_mirror.get_meta("mount")
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.007
		cyl.bottom_radius = 0.009
		cyl.height = maxf(stem_from.distance_to(stem_to), 0.01)
		cyl.radial_segments = 8
		cyl.rings = 1
		var stem := MeshInstance3D.new()
		stem.mesh = cyl
		stem.material_override = shell
		var along := (stem_to - stem_from).normalized()
		var side := along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.BACK).normalized()
		stem.transform = Transform3D(Basis(side, along, side.cross(along)), (stem_from + stem_to) * 0.5)
		_rear_mirror.add_child(stem)
	for g: GeometryInstance3D in _rear_mirror.get_children():
		g.layers = REAR_MIRROR_LAYER
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mirrors := CarMirrors.new()
	_rear_mirror.add_child(mirrors)
	var gl: Array[Dictionary] = [{"node": glass, "point": glass_at, "normal": n, "rear": true}]
	mirrors.setup(self, gl, eye, _half_size)
	_rear_mirror.visible = rear_mirror_wanted


## A Porsche Unleashed mirror's glass ({node, point, normal}: a side mirror's, see
## _cabin_mirror_glass, or the modelled rear-view mirror's) framed for the in-car view, under
## `parent` (at the body's origin): its edge a dark rim MIRROR_BEZEL wide, over which a copy
## of it drawn that much smaller shows the view. The copy's {node, point, normal}.
func _bezel_glass(g: Dictionary, parent: Node3D) -> Dictionary:
	var src: MeshInstance3D = g.node
	var n: Vector3 = g.normal
	var u := Vector3.UP.cross(n).normalized() if absf(n.y) < 0.9 else Vector3.RIGHT
	var w := n.cross(u)
	var faces := PackedVector3Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in src.mesh.get_faces():
		var p := src.transform * v
		faces.append(p)
		lo = lo.min(Vector2(p.dot(u), p.dot(w)))
		hi = hi.max(Vector2(p.dot(u), p.dot(w)))
	var mid := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	var shrink := Vector2(maxf(1.0 - MIRROR_BEZEL / maxf(half.x, 0.001), 0.5),
		maxf(1.0 - MIRROR_BEZEL / maxf(half.y, 0.001), 0.5))
	var rim := SurfaceTool.new()
	var inset := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	inset.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in faces:
		var c := Vector2(p.dot(u), p.dot(w))
		var q := mid + (c - mid) * shrink
		rim.set_normal(n)
		rim.add_vertex(p + n * 0.001)
		inset.add_vertex(p + u * (q.x - c.x) + w * (q.y - c.y) + n * 0.002)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.045, 0.045, 0.05)
	shell.roughness = 0.55
	var bezel := MeshInstance3D.new()
	bezel.mesh = rim.commit()
	bezel.material_override = shell
	var glass := MeshInstance3D.new()
	glass.mesh = inset.commit()
	glass.material_override = src.material_override
	for m: MeshInstance3D in [bezel, glass]:
		m.layers = REAR_MIRROR_LAYER
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
	return {"node": glass, "point": g.point, "normal": n}


## A modelled rear-view mirror's glass among `tris` (see _build_rear_mirror): the nearest
## flat patch, mirror-sized, across the car's length a little way ahead, about the eye's
## height or above, near the centreline. {faces, point (its middle)}, or {} if there's none.
static func _model_rear_glass(tris: PackedVector3Array, eye: Vector3) -> Dictionary:
	var planes := {}   # its plane (normal to a tenth, facing back; depth to the cm) -> [faces, area, weighted middle]
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var cross := (b - a).cross(c - a)
		var mid := (a + b + c) / 3.0
		if cross.length() < 1e-7 or absf(mid.x) > 0.15 or mid.y < eye.y - 0.1 or mid.z - eye.z > 0.9:
			continue
		var n := cross.normalized() * (-1.0 if cross.z > 0.0 else 1.0)
		# (Turned to the driver, as some are, a little.)
		if n.z > -0.75:
			continue
		var key := Vector3i(roundi(n.x * 10.0), roundi(n.y * 10.0), roundi(n.dot(mid) * 100.0))
		if not planes.has(key):
			planes[key] = [PackedVector3Array(), 0.0, Vector3.ZERO]
		var pl: Array = planes[key]
		var faces: PackedVector3Array = pl[0]
		faces.append_array([a, b, c])
		pl[0] = faces
		pl[1] += cross.length() * 0.5
		pl[2] += mid * cross.length() * 0.5
	var best := {}
	for key: Vector3i in planes:
		var pl: Array = planes[key]
		var area: float = pl[1]
		if area < 0.003 or area > 0.03:
			continue
		var box := AABB((pl[0] as PackedVector3Array)[0], Vector3.ZERO)
		for v: Vector3 in pl[0]:
			box = box.expand(v)
		# Wider than tall, and not much bigger than a mirror.
		if box.size.x < box.size.y * 1.5 or box.size.x > 0.35 or box.size.y > 0.12:
			continue
		var mid: Vector3 = pl[2] / area
		if best.is_empty() or eye.distance_to(mid) < eye.distance_to(best.point):
			best = {"faces": pl[0], "point": mid, "box": box, "normal": Vector3(key.x, key.y, 0.0) * 0.1}
	if best.is_empty():
		return best
	# A curved glass (the 993's) turns its sides toward the driver: they're its glass too,
	# the faces across it facing back that aren't behind it (the housing's back is; the
	# stalk above it faces down).
	var bn: Vector3 = best.normal
	bn = Vector3(bn.x, bn.y, -sqrt(maxf(1.0 - bn.length_squared(), 0.0))).normalized()
	var box: AABB = best.box
	var reach := AABB(box.position - Vector3(0.015, 0.004, 0.015), box.size + Vector3(0.03, 0.008, 0.03))
	var faces := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var mid := (tris[i] + tris[i + 1] + tris[i + 2]) / 3.0
		var cross := (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i])
		if cross.length() < 1e-7 or absf(cross.normalized().z) < 0.9 or not reach.has_point(mid) \
				or (mid - (best.point as Vector3)).dot(bn) < -0.004:
			continue
		faces.append_array([tris[i], tris[i + 1], tris[i + 2]])
	best.faces = faces
	return best


## Where a rear-view mirror's glass hangs when the cabin has none (see _build_rear_mirror),
## in `tris`' space; its stalk's top as _rear_mirror's meta "mount".
func _hang_rear_mirror(tris: PackedVector3Array, eye: Vector3) -> Vector3:
	var ahead := func(y: float) -> float:   # how far ahead of the eye the ray at `y` hits, or INF
		var best := INF
		var from := Vector3(0.0, y, eye.z)
		for i in range(0, tris.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.BACK, tris[i], tris[i + 1], tris[i + 2])
			if hit != null and (hit as Vector3).z - eye.z > 0.15:
				best = minf(best, (hit as Vector3).z - eye.z)
		return best
	var top := eye.y + 0.2
	var reach := 0.75
	var h := eye.y
	var last: float = ahead.call(h)
	while last < 1.4 and h < eye.y + 0.6:
		var d: float = ahead.call(h + 0.01)
		if d >= 1.4 or last - d > 0.04:
			break
		h += 0.01
		last = d
	if h > eye.y and last < 1.4:
		top = h
		reach = last
	var y := top - REAR_MIRROR_DROP
	var d_at: float = ahead.call(y)
	_rear_mirror.set_meta("mount", Vector3(0.0, top, eye.z + reach - 0.01))
	return Vector3(0.0, y, eye.z + clampf((d_at if d_at < 1.4 else reach) - REAR_MIRROR_BACK, 0.3, 0.8))


## A flat plate `size` across its X and Y, its ends rounded, facing +Z; `depth` > 0 makes it a
## slab that deep behind (-Z), sides and back closed.
static func _rounded_slab(size: Vector2, depth: float) -> ArrayMesh:
	var r := size.y * 0.5
	var outline := PackedVector2Array()
	for k in 9:
		var a := -PI * 0.5 + PI * k / 8.0
		outline.append(Vector2(size.x * 0.5 - r + r * cos(a), r * sin(a)))
	for k in 9:
		var a := PI * 0.5 + PI * k / 8.0
		outline.append(Vector2(-size.x * 0.5 + r + r * cos(a), r * sin(a)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [[0.0, 1.0]] if depth <= 0.0 else [[0.0, 1.0], [-depth, -1.0]]
	for face in faces:
		for i in range(1, outline.size() - 1):
			var tri := [outline[0], outline[i], outline[i + 1]] if face[1] > 0.0 else [outline[0], outline[i + 1], outline[i]]
			for p: Vector2 in tri:
				st.set_normal(Vector3(0, 0, face[1]))
				st.set_uv(Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y))
				st.add_vertex(Vector3(p.x, p.y, face[0]))
	if depth > 0.0:
		for i in outline.size():
			var p := outline[i]
			var q := outline[(i + 1) % outline.size()]
			var nrm := Vector3(q.y - p.y, p.x - q.x, 0.0).normalized()
			for v: Vector3 in [Vector3(p.x, p.y, 0), Vector3(q.x, q.y, -depth), Vector3(q.x, q.y, 0),
					Vector3(p.x, p.y, 0), Vector3(p.x, p.y, -depth), Vector3(q.x, q.y, -depth)]:
				st.set_normal(nrm)
				st.add_vertex(v)
	return st.commit()


## A Porsche Unleashed dial's full scale: the rev counter's the thousand past a tenth over
## the redline, the speedo's the 20 km/h (m/s here) past a twentieth over the top speed.
func _dial_full_scale(revs: bool) -> float:
	if revs:
		return ceilf(redline * 1.1 / 1000.0) * 1000.0
	return ceilf(top_speed * 1.05 * 3.6 / 20.0) * 20.0 / 3.6


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
		# speed, the rev counter to a quarter past its redline (Porsche Unleashed's, round figures).
		var full := _dial_full_scale(n.rpm) if n.get("round_scale", false) \
			else redline * 1.25 if n.rpm else top_speed * 1.1
		var f := clampf((rpm if n.rpm else absf(speed)) / full, 0.0, 1.0)
		(n.node as Node3D).basis = Basis(n.axis, float(n.get("zero", 0.0)) + f * float(n.turns) * TAU)
	# The dials light up with the headlights after dark (High Stakes' dash: its lit faces).
	var lit := headlights_on and Game.night
	if lit == _dash_lit_on or _dash_mats.is_empty():
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
	out.append_array(_lamps + _brake_lights + _reverse_lights + _fog_glows + _beams + _plates)
	for sg in _signals:
		out.append(sg[0])
	return out


## Per-wheel state for effects: "contact", "ground" and "normal" (world, valid while in
## contact), "hit" (the ray result, ditto), "slip" 0..1, "front", "left".
func wheel_states() -> Array[Dictionary]:
	return _wheels


## The wipers a step on: while it rains or snows they sweep up and back, faster the harder
## it comes down, with a pause between sweeps when it's light; once it stops they finish
## the sweep they're on and park.
func _wipe(dt: float) -> void:
	var amount := clampf(precipitation, 0.0, 1.0)
	if _wipe_t == 0.0 and amount < 0.05:
		return
	var sweep := lerpf(WIPE_SLOW, WIPE_FAST, amount)
	var pause := WIPE_PAUSE * clampf(1.0 - amount * 2.0, 0.0, 1.0) if amount >= 0.05 else 0.0
	_wipe_t += dt
	if _wipe_t >= sweep + pause:
		_wipe_t = 0.0 if amount < 0.05 else fmod(_wipe_t - sweep - pause, sweep)
	if far:
		return
	# Up and back, easing at each end as the motor's crank does.
	var up := 0.5 - 0.5 * cos(TAU * minf(_wipe_t / sweep, 1.0))
	for w in _wipers:
		_pose_frames(w[0], up * (w[1] - 1))


## The indicators' flashing: the side the controller asks for, else the one the car turns
## to at a crawl (held a moment after), all four once it's stuck on its roof.
func _flash_indicators(dt: float) -> void:
	if absf(speed) < INDICATE_SPEED and absf(speed) > 0.5 and absf(steer) > INDICATE_STEER:
		_indicate_auto = 1 if steer > 0.0 else -1
		_indicate_hold = INDICATE_HOLD
	else:
		_indicate_hold -= dt
		if _indicate_hold <= 0.0:
			_indicate_auto = 0
	var side := indicate if indicate != 0 else 2 if is_stuck_upside_down() else _indicate_auto
	if side != _indicator_shown:
		_indicator_shown = side
		_indicator_t = 0.0
	_indicator_t += dt
	var lit := side != 0 and fmod(_indicator_t, INDICATOR_CYCLE) < INDICATOR_CYCLE * 0.5
	for sg in _signals:
		sg[0].visible = lit and (side == 2 or side == sg[1])
	_set_lens("indicator_left", 1.0 if lit and side in [2, -1] else 0.0)
	_set_lens("indicator_right", 1.0 if lit and side in [2, 1] else 0.0)


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
	if _dash and _dash.visible or _cabin_on:
		_update_dash()
		if _rear_mirror:
			_rear_mirror.visible = rear_mirror_wanted
	if not _hood_top.is_empty():
		_fold_top(dt)
	var popup_goal := 1.0 if headlights_on else 0.0
	if _popup_t != popup_goal and not _popups.is_empty():
		_popup_t = move_toward(_popup_t, popup_goal, dt / POPUP_TIME)
		_pose_popups()
		if _popup_t == popup_goal or not headlights_on:
			_show_lamps()
	if not _spoiler_up.is_empty():
		var v := 99.0 if spoiler_raise else absf(speed)
		if v > SPOILER_UP and not _spoiler_raised or v < SPOILER_DOWN and _spoiler_raised:
			_spoiler_raised = not _spoiler_raised
		var goal := 1.0 if _spoiler_raised else 0.0
		if _spoiler_t != goal:
			_spoiler_t = move_toward(_spoiler_t, goal, dt / SPOILER_TIME)
			_pose_spoiler()
	if not _wipers.is_empty():
		_wipe(dt)
	if not (_lids.is_empty() and _windows.is_empty()):
		_move_openings(dt)
	_aim_glints(get_tree())
	if not _signals.is_empty():
		_flash_indicators(dt)
	var fogs := headlights_on and precipitation > 0.05
	if not _fog_glows.is_empty() and _fog_glows[0].visible != fogs:
		for g in _fog_glows:
			g.visible = fogs
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
	if body_sway:
		# The springs do that already (the car's own lag and wallow with them); [45] scales
		# how far this body goes on them. Read off the wheels, so it's the body against its
		# wheels whatever the camber, and nothing while a wheel is off the ground.
		var goal := Vector2.ZERO
		if grounded_wheels == 4:
			var c: Array[float] = [_wheels[0].compression, _wheels[1].compression, _wheels[2].compression, _wheels[3].compression]
			var track := maxf(absf(_wheels[0].center.x - _wheels[1].center.x), 1.0)
			var base := maxf(_wheels[0].center.z - _wheels[2].center.z, 1.0)
			var springs := Vector2((c[0] + c[1] - c[2] - c[3]) * 0.5 / base, (c[1] + c[3] - c[0] - c[2]) * 0.5 / track)
			goal = (springs * (clampf(pitch_roll, 0.3, 1.5) - 1.0)).limit_length(SWAY_MAX)
		_tilt = _tilt.lerp(goal, 1.0 - exp(-SWAY_SMOOTH * dt))
	else:
		_tilt = Vector2(-_acc.y, _acc.x) * pitch_roll * 0.005
	# The models leave the tyres only a little room in their arches, less than the springs
	# travel with a hard corner's load or the downforce on them: where a wheel would rise past
	# its arch, the body rides up on it instead (a plane through the corners: heave, pitch and
	# roll), as on a bump stop; what's left the tyre takes by dipping into the road.
	var over: Array[float] = []
	for w in _wheels:
		var dy: float = _tilt.y * w.center.x - _tilt.x * w.center.z
		over.append(maxf(w.compression - w.lift_max - dy, 0.0))
	var ride := Vector3.ZERO
	if over.max() > 0.0:
		var track := maxf(absf(_wheels[0].center.x - _wheels[1].center.x), 1.0)
		var base := maxf(_wheels[0].center.z - _wheels[2].center.z, 1.0)
		ride = Vector3(-(over[0] + over[1] - over[2] - over[3]) * 0.5 / base,
				(over[0] + over[2] - over[1] - over[3]) * 0.5 / track,
				minf((over[0] + over[1] + over[2] + over[3]) * 0.25, 0.08))
	_ride = _ride.lerp(ride, 1.0 - exp(-30.0 * dt))
	# Leaning about the roll centre at axle height, so the roof swings out rather than the
	# sills digging in; it's the identity at rest, which keeps the parts car-local (CarDamage).
	var tilt_basis := Basis.from_euler(Vector3(_tilt.x + _ride.x, 0.0, _tilt.y + _ride.y))
	_body_tilt.transform = Transform3D(tilt_basis, _tilt_pivot - tilt_basis * _tilt_pivot + Vector3(0, _ride.z, 0))
	for w in _wheels:
		if not w.has("visual"):
			continue
		# Wheel centre sits `compression` above its fully-extended position, but never
		# further up than the arch allows, where the body's lean has put it: past that (a hard
		# landing) the tyre dips into the road rather than showing through the bodywork.
		var arch: Vector3 = w.center + Vector3(0, w.radius, 0) - _tilt_pivot
		var lift: float = w.lift_max + (tilt_basis * arch).y - arch.y + _ride.z
		var y: float = w.center.y + minf(w.compression, lift)
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

class_name ProceduralCar
extends Nfs3Car
## Stand-in car data, built here rather than read from a game's files: used when no game is
## installed, and for generic cop and traffic cars. Each preset is modelled from a handful
## of body lines and comes in parts the way Porsche Unleashed's cars do (Nfs5Car), so it
## does everything they do: a lofted shell cut into the panels that open and come off (the
## doors on their hinges with their windows winding down into them, the bonnet and boot lid
## over their bays, the bumpers, sills, spoiler and mirrors), see-through glass over a cabin
## (seats, a dash whose needles move, a steering wheel that turns, a driver whose hands go
## with it), wipers and an active spoiler moving by blend shapes, pop-up headlamps, lamps
## whose lenses light, tail pipes and a plate.
##
## The shell is lofted through cross-sections of a dozen landmarks (sill, flank, shoulder,
## window line, roof rail...) joined by curves, the ends closing round in plan, each landmark
## stopping its own way short of the end so the nose and tail come out sculpted (the bumper
## furthest out, the bonnet's leading edge and the chin set back), flared over the wheels.
## Lamps, grilles, intakes and badges are pictures cast onto it. The skin is painted here, shut
## lines, door handles and the shading round the arches and sills and all, for the same paint/
## glass/rubber shader (car.gdshader) as the games' cars, which reads the vertices' finish as
## Porsche Unleashed's (COLOR: r how much it mirrors, g a lamp's lens, b 0).

const GROUND := -0.6   # the road below the car's origin at rest
## Who they're made by, as the dealership lists them (Game.cars has them as PATH_PREFIX + preset).
const MAKER := "Generated"
const PATH_PREFIX := "proc:"

# Body lines in metres, heights above the road. Positions along the car are fractions
# of its half length `len` (front +1): ws0/ws1 windshield base/top, rw1/rw0 rear window
# top/base, bpil the B pillar (none outside -1..1), cpil where the side glass ends,
# wf/wr the axles. In plan the ends close over rcf/rcr (m) as a superellipse of power
# plan_n (2 round .. 5 square); re rounds them in side view. flare: how far the flanks swell
# out over the front and rear wheels; nose_k scales how far the nose's upper parts set back;
# creases: landmarks the body has a crisp edge at (the boxier cars' shoulders).
# Besides: "engine" front or rear (which bay it fills; the other carries luggage), "doors"
# 2 or 4 (the rear ones don't open), "hatch" (the boot lid takes the rear window with it),
# "heads" corner (swept back into the wings), face (upright in the nose) or popup, "tails"
# round, strip or bar (one across the tail), "grille" none, mesh or bars, "spoiler" 0 none,
# 1 a lip, 2 a wing on posts, 3 one that rises at speed, "pipes" how many tail pipes, "fog"
# lamps in the front bumper, "vents" in the flanks behind the doors, "diffuser", "euro" the
# plate, "interior" the cabin's colour, "paints" the other colours it comes in (the menu's,
# "paint_names" theirs, the first the car's own); for the showroom its "class" (0 A .. 2 C)
# and "motor".
const PRESETS := [
	{"name": "Stinger GT", "color": Color(0.6, 0.04, 0.035), "mass": 1400.0, "top": 80.0, "torque": 520.0,
		"len": 2.2, "wid": 0.9, "roof": 1.28, "nose": 0.6, "hood": 0.84, "deck": 0.92, "tail": 0.84, "crown": 0.06,
		"ws0": 0.24, "ws1": -0.06, "rw1": -0.36, "rw0": -0.7, "bpil": 2.0, "cpil": -0.4, "tumble": 0.78,
		"clear": 0.13, "r": 0.33, "wf": 0.6, "wr": -0.58, "rcf": 0.5, "rcr": 0.45, "plan_n": 3.0, "re": 0.2,
		"flare": [0.03, 0.075], "nose_k": 1.0,
		"heads": "corner", "tails": "round", "grille": "none", "rim": "spoke", "spokes": 5, "spoiler": 3,
		"engine": "rear", "doors": 2, "pipes": 2, "diffuser": true, "euro": true, "interior": Color(0.42, 0.28, 0.17),
		"class": 0, "motor": "3.6 litre flat six, twin turbo", "paint_names": ["Guards Red", "Black", "Arctic Silver", "Speed Yellow", "Midnight Blue"],
		"paints": [Color(0.04, 0.04, 0.05), Color(0.62, 0.63, 0.64), Color(0.86, 0.66, 0.06), Color(0.06, 0.13, 0.32)]},
	{"name": "Vortex V12", "color": Color(0.88, 0.66, 0.05), "mass": 1550.0, "top": 90.0, "torque": 600.0,
		"len": 2.25, "wid": 1.0, "roof": 1.12, "nose": 0.48, "hood": 0.7, "deck": 0.95, "tail": 0.9, "crown": 0.03,
		"ws0": 0.42, "ws1": 0.02, "rw1": -0.22, "rw0": -0.66, "bpil": 2.0, "cpil": -0.25, "tumble": 0.72,
		"clear": 0.12, "r": 0.34, "wf": 0.6, "wr": -0.58, "rcf": 0.55, "rcr": 0.36, "plan_n": 3.4, "re": 0.18,
		"flare": [0.03, 0.09], "nose_k": 0.6, "head_dir": Vector3(-0.2, -1.0, -0.3), "head_size": Vector2(0.36, 0.22), "head_back": 0.3,
		"heads": "corner", "tails": "bar", "grille": "mesh", "rim": "spoke", "spokes": 10, "spoiler": 2,
		"engine": "rear", "doors": 2, "pipes": 4, "vents": true, "diffuser": true, "euro": true,
		"class": 0, "motor": "6.0 litre V12", "paint_names": ["Giallo", "Rosso", "Nero", "Bianco", "Verde"],
		"interior": Color(0.1, 0.1, 0.11),
		"paints": [Color(0.6, 0.04, 0.035), Color(0.04, 0.04, 0.05), Color(0.86, 0.86, 0.85), Color(0.18, 0.4, 0.12)]},
	{"name": "Aero RS", "color": Color(0.07, 0.2, 0.55), "mass": 1250.0, "top": 76.0, "torque": 430.0,
		"len": 2.12, "wid": 0.88, "roof": 1.27, "nose": 0.56, "hood": 0.74, "deck": 0.8, "tail": 0.78, "crown": 0.05,
		"ws0": 0.3, "ws1": 0.0, "rw1": -0.25, "rw0": -0.86, "bpil": 2.0, "cpil": -0.5, "tumble": 0.76,
		"clear": 0.14, "r": 0.31, "wf": 0.64, "wr": -0.6, "rcf": 0.45, "rcr": 0.4, "plan_n": 3.3, "re": 0.22,
		"flare": [0.03, 0.04], "nose_k": 0.7,
		"heads": "popup", "tails": "strip", "grille": "none", "rim": "spoke", "spokes": 6, "spoiler": 1, "hatch": true,
		"engine": "front", "doors": 2, "pipes": 1, "euro": false, "interior": Color(0.2, 0.2, 0.23),
		"class": 1, "motor": "2.5 litre straight four, turbo", "paint_names": ["Racing Blue", "White", "Red", "Black", "Gunmetal"],
		"paints": [Color(0.86, 0.86, 0.85), Color(0.55, 0.03, 0.03), Color(0.04, 0.04, 0.05), Color(0.4, 0.41, 0.43)]},
	{"name": "Interceptor", "color": Color(0.03, 0.03, 0.035), "mass": 1700.0, "top": 82.0, "torque": 560.0,
		"len": 2.55, "wid": 0.98, "roof": 1.44, "nose": 0.86, "hood": 0.93, "deck": 1.0, "tail": 0.96, "crown": 0.04,
		"ws0": 0.3, "ws1": 0.07, "rw1": -0.3, "rw0": -0.48, "bpil": -0.12, "cpil": -0.42, "tumble": 0.82,
		"clear": 0.16, "r": 0.33, "wf": 0.62, "wr": -0.58, "rcf": 0.34, "rcr": 0.3, "plan_n": 4.5, "re": 0.12,
		"flare": [0.01, 0.012], "nose_k": 0.35, "creases": [5, 6],
		"heads": "face", "tails": "strip", "grille": "bars", "rim": "steel", "spokes": 8, "spoiler": 0,
		"engine": "front", "doors": 4, "pipes": 2, "fog": true, "euro": false, "interior": Color(0.16, 0.16, 0.17),
		"class": 1, "motor": "5.7 litre V8", "paint_names": ["Black and White"],
		"lightbar": true, "twotone": true, "paints": []},
	{"name": "Sedan", "color": Color(0.5, 0.52, 0.46), "mass": 1500.0, "top": 50.0, "torque": 300.0,
		"len": 2.32, "wid": 0.9, "roof": 1.42, "nose": 0.82, "hood": 0.89, "deck": 0.98, "tail": 0.94, "crown": 0.04,
		"ws0": 0.32, "ws1": 0.06, "rw1": -0.32, "rw0": -0.52, "bpil": -0.12, "cpil": -0.44, "tumble": 0.8,
		"clear": 0.15, "r": 0.31, "wf": 0.64, "wr": -0.6, "rcf": 0.4, "rcr": 0.34, "plan_n": 3.8, "re": 0.14,
		"flare": [0.015, 0.02], "nose_k": 0.4, "creases": [5, 6],
		"heads": "face", "tails": "strip", "grille": "bars", "rim": "hubcap", "spokes": 12, "spoiler": 0,
		"engine": "front", "doors": 4, "pipes": 1, "euro": true, "interior": Color(0.32, 0.27, 0.22),
		"class": 2, "motor": "2.0 litre straight six", "paint_names": ["Sage", "Navy", "Burgundy", "Ivory", "Forest Green"],
		"paints": [Color(0.08, 0.12, 0.24), Color(0.36, 0.05, 0.06), Color(0.8, 0.8, 0.76), Color(0.2, 0.24, 0.18)]},
]

# The skin: flat swatches along the top row (the paint at Porsche Unleashed's paint alpha,
# the cabin's at its interior alpha), patterned patches below them, and the body's own
# chart (BODY_RECT: along the car across, round the ring down), where the shut lines are.
enum Sw { PAINT, GLASS, TRIM, CHROME, RED, WHITE, TYRE, AMBER, BLUE, CREAM, CABIN, DARK, CARPET, SUIT, MIRROR,
	VISOR, GBLACK, ALLOY }
## How much each swatch mirrors the surroundings (COLOR.r, car.gdshader): 0 matte, 0.5
## gloss, 1 chrome; the alloy between (polished, on the wheels).
const ENV := [0.5, 0.5, 0.05, 1.0, 0.5, 0.5, 0.0, 0.5, 0.5, 0.5, 0.0, 0.1, 0.0, 0.0, 1.0, 0.5, 0.5, 0.8]
const SKIN := 1024
const SWATCH := 32
const PAINT_A := 117   # Nfs5Car's paint alpha
const CABIN_A := 224   # ... and its cabin's (Nfs5Car.CABIN_ALPHA)
const HEAD_RECT := Rect2i(0, 32, 256, 128)
const TAIL_RECT := Rect2i(256, 32, 256, 128)
const GRILLE_RECT := Rect2i(512, 32, 256, 128)
const DIAL_RECT := Rect2i(768, 32, 256, 128)
const SEAT_RECT := Rect2i(0, 160, 128, 128)
const PLATE_RECT := Rect2i(128, 160, 256, 128)
const CAM_RECT := Rect2i(384, 160, 128, 128)
const INTAKE_RECT := Rect2i(512, 160, 256, 128)
const BADGE_RECT := Rect2i(768, 160, 128, 128)
const MARKER_RECT := Rect2i(896, 160, 128, 64)
const DIFF_RECT := Rect2i(896, 224, 128, 64)
const RIM_RECT := Rect2i(0, 288, 256, 256)
const TREAD_RECT := Rect2i(256, 288, 256, 64)
const WALL_RECT := Rect2i(256, 352, 256, 64)
const BODY_RECT := Rect2i(0, 640, 1024, 384)
const RING_POINTS := 12
## Landmarks the ring turns a corner at (the curve through the others is smooth), and how
## many steps each landmark's segment is cut into.
const SHARP := [1, 2, 3, 7, 8]
const SUBS := [1, 1, 1, 3, 3, 3, 4, 2, 3, 3, 4]
## How far short of the end each landmark stops (m), at the nose and the tail: the bumper
## (landmark 5) furthest out, the chin under it and the bonnet's leading edge set back.
const NOSE_SET := [0.36, 0.33, 0.26, 0.12, 0.04, 0.0, 0.05, 0.12, 0.14, 0.15, 0.16, 0.16]
const TAIL_SET := [0.3, 0.28, 0.22, 0.09, 0.025, 0.0, 0.02, 0.04, 0.05, 0.06, 0.06, 0.06]
const SET_SOFT := 0.06
const TYRE_W := 0.235
## The rows of the ring each piece takes (strip j runs from landmark j to j + 1): the
## sills the lower flank between the arches, the doors the flank up to the shoulder, the
## lids the top from the shoulder in, the bumpers the flank up to their own height.
const SILL_ROW := 3
const DOOR_ROWS := [4, 5, 6]
const LID_ROWS := [7, 8, 9, 10]
const BUMPER_ROWS_F := 4
const BUMPER_ROWS_R := 3
## Frames of the moving parts' blend shapes.
const WIPER_FRAMES := 8
const SPOILER_FRAMES := 6
const SPOILER_LIFT := 0.13
const SPOILER_SPEED := 22.0   # m/s it rises at (carp [48])
## The driver's eye below the roof, and the steering wheel's size.
const EYE_BELOW_ROOF := 0.19
const WHEEL_RADIUS := 0.185

var body_color := Color.WHITE
var interior_colours: Array[Color] = []   # each paint's cabin colour (Car._interior_of), at double strength

# Built meshes and skin per preset; only the paint colour differs between cars of one preset.
static var _models := {}


## The preset's car; with `spec_only` just its name, colours and figures (for menus that list
## every car), without building the model.
static func make(preset: int, tint := Color(0, 0, 0, 0), spec_only := false) -> ProceduralCar:
	preset = clampi(preset, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[preset]
	var c := ProceduralCar.new()
	c.id = "proc%d" % preset
	c.display_name = p.name
	c.body_color = p.color if tint.a == 0 else tint
	# The skin's paint is mid-grey, so the colours go on at double strength (as NFS3's do);
	# each with the cabin colour it comes with.
	var paints: Array = [c.body_color] + p.paints
	for col: Color in paints:
		c.colours.append(Color(col.r * 2.0, col.g * 2.0, col.b * 2.0))
		var inside: Color = p.interior
		c.interior_colours.append(Color(inside.r * 2.0, inside.g * 2.0, inside.b * 2.0))
	c.carp = {
		1: PackedFloat32Array([p.class]),
		2: PackedFloat32Array([p.mass]),
		7: PackedFloat32Array([-220, 0, 230, 150, 110, 88, 70, 0]),
		8: PackedFloat32Array([2.1, 0, 2.3, 1.5, 1.12, 0.88, 0.7, 0]),
		10: _torque_curve(p.torque),
		11: PackedFloat32Array([3.8]),
		12: PackedFloat32Array([1000]),
		13: PackedFloat32Array([7000]),
		15: PackedFloat32Array([p.top]),
		18: PackedFloat32Array([10.0]),
		30: PackedFloat32Array([3.2]),
	}
	# What the showroom says of it (Nfs3Car.read_info's keys).
	var peak: float = p.torque
	c.info = {"make": MAKER, "model": p.name, "name": p.name, "engine": p.motor,
		"power": "%d bhp" % roundi(peak * 5500.0 / 7121.0),
		"torque": "%d Nm" % roundi(peak), "weight": "%d kg" % roundi(p.mass),
		"top_speed": "%d km/h" % roundi(p.top * 3.6), "transmission": "5-speed manual",
		"colours": p.paint_names}
	if p.spoiler == 3:
		c.carp[47] = PackedFloat32Array([1.0])
		c.carp[48] = PackedFloat32Array([SPOILER_SPEED])
	if spec_only:
		return c
	if not _models.has(preset):
		_models[preset] = _build(p)
	var m: Dictionary = _models[preset]
	c.texture = m.texture
	c.half_size = m.half_size
	c.lights.assign(m.lights)
	c.body_parts.assign(m.parts)
	c.wheels.assign(m.wheels)
	c.popup_lights.assign(m.popups)
	c.exhausts.assign(m.exhausts)
	c.plate = m.plate
	c.dash = m.dash
	# The lenses are marked in the meshes already (Car._mark_lenses would guess at them).
	c.set_meta("lenses", true)
	return c


## A lamp as the games' light dummies name it (see Nfs3Car.decode_light()).
static func _light(dname: String, pos: Vector3) -> Dictionary:
	var l := decode_light(dname)
	l.pos = pos
	return l


static func _torque_curve(peak: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 41:
		var rpm := i * 256.0
		out.append(peak * clampf(0.55 + 0.45 * sin(clampf(rpm / 5500.0, 0.0, 1.4) * PI * 0.5), 0.0, 1.0) * (1.0 - clampf((rpm - 6500.0) / 4000.0, 0.0, 0.6)))
	return out


# ------------------------------------------------------------------ body lines

## Share of the full cabin height at `u` (0 over the hood and deck, 1 under the roof),
## eased so the windshield and rear window bow out a little.
static func _cabin(p: Dictionary, u: float) -> float:
	var t := 0.0
	if u < p.ws0 and u > p.rw0:
		t = minf(clampf((p.ws0 - u) / (p.ws0 - p.ws1), 0.0, 1.0), clampf((u - p.rw0) / (p.rw1 - p.rw0), 0.0, 1.0))
	return 1.0 - pow(1.0 - t, 1.3)


## Height of the waist line: the hood falling to the nose, the flank rising to the deck,
## the deck dropping to the tail.
static func _belt(p: Dictionary, u: float) -> float:
	if u >= p.ws0:
		return lerpf(p.hood, p.nose, pow((u - p.ws0) / (1.0 - p.ws0), 1.6))
	if u <= p.rw0:
		var t: float = (p.rw0 - u) / (p.rw0 + 1.0)
		return lerpf(p.deck, p.tail, t * t)
	return lerpf(p.deck, p.hood, (u - p.rw0) / (p.ws0 - p.rw0))


## The roof's height at `u`: highest a little behind the windshield's top, curving down
## both ways.
static func _roof(p: Dictionary, u: float) -> float:
	var peak: float = lerpf(p.ws1, p.rw1, 0.35)
	var span: float = maxf(p.ws1 - p.rw1, 0.1)
	var t := (u - peak) / span
	return p.roof - 0.09 * t * t


## Underside: level between the axles, lifting under the overhangs.
static func _bottom(p: Dictionary, u: float) -> float:
	var b: float = p.clear
	if u > p.wf:
		b += (u - p.wf) / (1.0 - p.wf) * 0.1
	elif u < p.wr:
		b += (p.wr - u) / (1.0 + p.wr) * 0.1
	return b


## Top of the wheel arch at `z`, or -INF clear of both wheels.
static func _arch(p: Dictionary, z: float) -> float:
	var ra: float = p.r + 0.05
	for zw: float in [p.wf * p.len, p.wr * p.len]:
		var d := absf(z - zw)
		if d <= ra:
			return p.r + sqrt(ra * ra - d * d)
	return -INF


## How far the flanks swell out at `z` over the wheels (m).
static func _flare(p: Dictionary, z: float) -> float:
	var out := 0.0
	var reach: float = p.r + 0.45
	for k in 2:
		var zw: float = (p.wf if k == 0 else p.wr) * p.len
		var d := absf(z - zw) / reach
		if d < 1.0:
			out += (p.flare[k] as float) * (0.5 + 0.5 * cos(PI * d))
	return out


## The share of the body's width left at `z`: all of it amidships, closing round to nothing
## at the ends (a superellipse in plan).
static func _plan(p: Dictionary, z: float) -> float:
	var rc: float = p.rcf if z > 0.0 else p.rcr
	var dz: float = absf(z) - (p.len - rc)
	if dz <= 0.0:
		return 1.0
	var n: float = p.plan_n
	return pow(maxf(1.0 - pow(minf(dz / rc, 1.0), n), 0.0), 1.0 / n)


## `a` held below `b`, rounded off over SET_SOFT.
static func _smin(a: float, b: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / SET_SOFT, 0.0, 1.0)
	return lerpf(b, a, h) - SET_SOFT * h * (1.0 - h)


## The body's cross-section through station `z`, the +X half from the middle of the floor
## round to the middle of the roof (or hood): its landmarks, 0 floor, 1-2 wheel-well liner,
## 3 sill, 4-5 flank, 6 shoulder, 7 window sill, 8 window top, 9 roof rail, 10-11 roof (or
## hood, or glass). Near the ends each landmark stops short of the station on its own line
## (NOSE_SET, TAIL_SET), so the section's points needn't lie at `z`.
static func _ring(p: Dictionary, z: float) -> PackedVector3Array:
	var L: float = p.len
	var u := z / L
	var c := _cabin(p, u)
	var hw: float = p.wid * (1.0 - 0.03 * u * u)
	var bot := _bottom(p, u)
	var belt := _belt(p, u)
	var roof := _roof(p, u)
	var crown: float = p.crown
	var rail: float = hw * p.tumble - 0.08
	var fl := _flare(p, z)
	var pts: Array[Vector2] = [
		Vector2(0.0, bot), Vector2(hw - 0.34, bot), Vector2(hw - 0.3, bot + 0.02), Vector2(hw - 0.05 + fl * 0.5, bot + 0.05),
		Vector2(hw + fl, bot + 0.25 * (belt - bot)), Vector2(hw - 0.005 + fl, belt - 0.15), Vector2(hw - 0.06 + fl * 0.7, belt),
		Vector2(hw * 0.9, belt + 0.012).lerp(Vector2(hw - 0.13, belt + 0.03), c),
		Vector2(hw * 0.84, belt + crown * 0.3).lerp(Vector2(hw * p.tumble, roof - 0.09), c),
		Vector2(hw * 0.76, belt + crown * 0.5).lerp(Vector2(rail, roof - 0.02), c),
		Vector2(hw * 0.4, belt + crown * 0.88).lerp(Vector2(rail * 0.5, roof - 0.004), c),
		Vector2(0.0, belt + crown).lerp(Vector2(0.0, roof), c),
	]
	# Wheel arches: the well is cut up into the flank, and the wings swell over the tyres.
	var a := _arch(p, z)
	if a > -INF:
		for k in [2, 3, 4]:
			pts[k].y = maxf(pts[k].y, a)
		pts[5].y = maxf(pts[5].y, a + 0.05)
		pts[6].y = maxf(pts[6].y, a + 0.065)
		# The hood's edges hump over the wells too, or the wells would show through a low hood.
		for k in [7, 8, 9]:
			pts[k].y = maxf(pts[k].y, a + 0.06 - 0.02 * (k - 7))
		pts[7].y = maxf(pts[7].y, lerpf(pts[7].y, pts[6].y + 0.02, c))
	# Round the ends off in side view.
	var re: float = p.re
	var ez := absf(z) - (L - re)
	if ez > 0.0:
		var k := 0.8 + 0.2 * sqrt(maxf(1.0 - (ez / re) * (ez / re), 0.0))
		var mid := (bot + belt) * 0.5
		for i in pts.size():
			pts[i].y = mid + (pts[i].y - mid) * k
	# In plan the ends close round; each landmark stops short of the end by its own amount.
	var w := _plan(p, z)
	var sets: Array = NOSE_SET if z > 0.0 else TAIL_SET
	var nk: float = p.nose_k if z > 0.0 else 1.0
	var out := PackedVector3Array()
	for i in pts.size():
		var stop: float = L - (sets[i] as float) * (nk if i >= 6 else 1.0)
		var zz := _smin(absf(z), stop) * signf(z) if z != 0.0 else 0.0
		out.append(Vector3(pts[i].x * w, GROUND + pts[i].y, zz))
	return out


## The ring with its landmarks joined by curves (Hermite, Catmull-Rom tangents; straight into
## a SHARP landmark, level across the middle): [points, their landmark positions (j + t)].
static func _fine(r: PackedVector3Array, sharp: Array = SHARP) -> Array:
	var pts := PackedVector3Array()
	var ks := PackedFloat32Array()
	var n := r.size()
	for j in n - 1:
		var p1 := r[j]
		var p2 := r[j + 1]
		var p0 := r[j - 1] if j > 0 else Vector3(-r[1].x, r[1].y, r[1].z)
		var p3 := r[j + 2] if j + 2 < n else Vector3(-r[n - 2].x, r[n - 2].y, r[n - 2].z)
		var t1 := (p2 - p1) if j in sharp else (p2 - p0) * 0.5
		var t2 := (p2 - p1) if (j + 1) in sharp else (p3 - p1) * 0.5
		var steps: int = SUBS[j]
		for s in steps:
			var t := float(s) / steps
			var t2_ := t * t
			var t3 := t2_ * t
			pts.append(p1 * (2.0 * t3 - 3.0 * t2_ + 1.0) + t1 * (t3 - 2.0 * t2_ + t) + p2 * (-2.0 * t3 + 3.0 * t2_) + t2 * (t3 - t2_))
			ks.append(j + t)
	pts.append(r[n - 1])
	ks.append(n - 1)
	return [pts, ks]


## A point on the body surface at `z`, `s` of the way round the ring (landmark + fraction).
static func _surf(p: Dictionary, z: float, s: float) -> Vector3:
	var r := _ring(p, z)
	var j := clampi(int(s), 0, r.size() - 2)
	return r[j].lerp(r[j + 1], s - j)


## The top of the body (the roof, hood or deck's middle) at `z`.
static func _top(p: Dictionary, z: float) -> float:
	return _ring(p, z)[RING_POINTS - 1].y


## What a strip of the shell is made of: strip `sub` of landmark segment `j` at `u`. Glass
## over the cabin, black round it (the frames along the side windows' tops, the belt
## moulding under them, the frit round the windshield and rear window), trim underneath.
static func _material(p: Dictionary, j: int, sub: int, u: float) -> int:
	if j <= 2:
		return Sw.TRIM
	var L: float = p.len
	var c := _cabin(p, u)
	if j == 7 and c > 0.001 and u > p.cpil:
		return Sw.GBLACK if absf(u - p.bpil) < 0.03 else Sw.GLASS
	if j >= 9 and c > 0.001 and c < 0.999:
		var edge := 0.035 / L
		if (j == 9 and sub == 0) or (u > 0.0 and u < p.ws1 + edge) or (u < 0.0 and (u > p.rw1 - edge or u < p.rw0 + edge * 0.6)):
			return Sw.GBLACK
		return Sw.GLASS
	if j == 8 and sub == 0 and c > 0.001 and u > p.cpil - 0.02:
		return Sw.GBLACK
	if j == 6 and sub == SUBS[6] - 1 and c > 0.001 and u > p.cpil:
		return Sw.GBLACK
	return Sw.PAINT


## Where the panels' edges fall along the car (z, m), and the cabin's.
static func _layout(p: Dictionary) -> Dictionary:
	var L: float = p.len
	var r: float = p.r
	var d := {}
	d.arch_f = p.wf * L - r - 0.05
	d.arch_r = p.wr * L + r + 0.05
	d.door_f = minf(p.wf * L - r - 0.12, p.ws0 * L + 0.25)
	d.door_r = p.bpil * L - 0.015 if p.doors == 4 else maxf(d.door_f - 1.15, d.arch_r + 0.12)
	d.rdoor_r = maxf(p.cpil * L + 0.02, d.arch_r + 0.04)
	d.bonnet_r = p.ws0 * L + 0.05
	d.bonnet_f = L - 0.15
	d.boot_f = p.rw1 * L - 0.03 if p.get("hatch", false) else p.rw0 * L - 0.05
	d.boot_r = -L + 0.1
	d.bump_f = L - 0.32
	d.bump_r = -L + 0.28
	# The cabin: from the dash (just behind the windshield's foot) back to the rear seats'.
	d.cab_f = p.ws0 * L - 0.03
	d.cab_r = maxf(p.rw0 * L + 0.05, d.arch_r - 0.1)
	return d


## Which piece of the car the shell's strip `j` at `z` (in `m`) belongs to.
static func _panel(p: Dictionary, d: Dictionary, j: int, z: float, m: int) -> String:
	if m == Sw.GLASS:
		if j == 7 and z < d.door_f and z > d.door_r:
			return "window"
		if p.get("hatch", false) and j >= 9 and z < d.boot_f:
			return "hatch_glass"
		return "glass"
	if z > d.bump_f and j <= BUMPER_ROWS_F:
		return "bumper_f"
	if z < d.bump_r and j <= BUMPER_ROWS_R:
		return "bumper_r"
	if j == SILL_ROW and z < d.arch_f and z > d.arch_r:
		return "sill"
	if j in DOOR_ROWS and z < d.door_f and z > d.door_r:
		return "door"
	if j in LID_ROWS and z > d.bonnet_r and z < d.bonnet_f:
		return "bonnet"
	if j in LID_ROWS and z < d.boot_f and z > d.boot_r:
		return "boot"
	return "body"


## The stations the shell is lofted through: every few cm, closer where the ends close
## (evenly round the superellipse), and on every body line and panel edge.
static func _stations(p: Dictionary, d: Dictionary) -> Array[float]:
	var L: float = p.len
	var r: float = p.r
	var zs: Array[float] = []
	var z: float = -L + p.rcr
	while z < L - p.rcf:
		zs.append(z)
		z += 0.04
	var n: float = p.plan_n
	for e in [1.0, -1.0]:
		var rc: float = p.rcf if e > 0.0 else p.rcr
		const M := 22
		for i in M + 1:
			var th := PI * 0.5 * i / M
			zs.append(e * (L - rc + rc * pow(sin(th), 2.0 / n)))
	for u: float in [p.ws0, p.ws1, p.rw1, p.rw0, p.cpil, p.bpil - 0.03, p.bpil + 0.03]:
		if absf(u) < 1.0:
			zs.append(u * L)
	for u: float in [p.ws1 + 0.035 / L, p.rw1 - 0.035 / L, p.rw0 + 0.021 / L]:
		zs.append(u * L)
	for zw: float in [p.wf * L, p.wr * L]:
		for e in [-0.012, 0.0]:
			zs.append(zw - (r + 0.05) + e)
			zs.append(zw + (r + 0.05) - e)
		for k in range(-6, 7):
			zs.append(zw + k * (r + 0.05) / 6.5)
	for key in ["door_f", "door_r", "bonnet_r", "bonnet_f", "boot_f", "boot_r", "bump_f", "bump_r", "cab_f", "cab_r"]:
		zs.append(d[key])
	if p.doors == 4:
		zs.append(d.rdoor_r)
	zs.sort()
	# (Near the tips the closing stations crowd together in z, but not in width: keep them.)
	var out: Array[float] = []
	for v in zs:
		var tip := absf(v) > L - 0.03
		if out.is_empty() or v - out[-1] > (0.0002 if tip else 0.004):
			out.append(v)
	if out[-1] < L:
		out.append(L)
	if out[0] > -L:
		out.push_front(-L)
	return out


# ------------------------------------------------------------------ meshes

## A mesh as it's built: unindexed triangles, each corner with its skin UV, its finish
## (COLOR: r mirroring, g lens, b 0: car.gdshader reads it as Porsche Unleashed's) and UV2
## (x: 1 turns with the steering, -1 the driver's head, -3 drawn one-sided; y the depth bias).
## Normals are smoothed within a group, flat outside one; `shapes` are its blend shapes.
class _Mesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var grp := PackedInt32Array()
	var shapes: Array[PackedVector3Array] = []
	var env := 0.5
	var lens := 0.0
	var mark := 0.0
	var bias := 0.0
	var group := -1

	func is_empty() -> bool:
		return pos.is_empty()

	## One triangle facing `out`; `t` holds one UV per corner or one for all three, `marks`
	## one UV2.x per corner (else `mark`).
	func tri(v: Array, t: Array, out: Vector3, marks := []) -> void:
		var n: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
		if n.length_squared() < 1e-14:
			return
		# Godot's front faces wind clockwise: the right-hand normal points into the body.
		var order := [0, 2, 1] if n.dot(out) > 0.0 else [0, 1, 2]
		for k: int in order:
			pos.append(v[k])
			uv.append(t[k] if t.size() == 3 else t[0])
			uv2.append(Vector2(marks[k] if marks.size() == 3 else mark, bias))
			col.append(Color(env, lens, 0.0, 1.0))
			grp.append(group)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, t: Array) -> void:
		if t.size() == 4:
			tri([a, b, c], [t[0], t[1], t[2]], out)
			tri([a, c, d], [t[0], t[2], t[3]], out)
		else:
			tri([a, b, c], t, out)
			tri([a, c, d], t, out)

	## A box turned by `xf` (its middle the origin), half extents `h`, in swatch `sw`; with
	## `rect` its faces show that patch of the skin instead (only the face towards `face`, a
	## local axis direction, when that's given).
	func box(xf: Transform3D, h: Vector3, sw: int, rect := Rect2i(), face := Vector3.ZERO, flip := false) -> void:
		var keep_env := env
		var keep_group := group
		env = ENV[sw]
		group = -1
		for axis in 3:
			for s in [1.0, -1.0]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var w := n.cross(u)
				var fc := n * h
				var hu := u * h
				var hw := w * h
				var q := [fc - hu - hw, fc + hu - hw, fc + hu + hw, fc - hu + hw]
				var world := []
				for k in 4:
					world.append(xf * (q[k] as Vector3))
				var on_face := rect.size != Vector2i.ZERO and (face == Vector3.ZERO or face == n)
				if on_face:
					# Across the face as seen from outside (+X to the right from behind, on the
					# left from in front), down it from its top.
					var right := Vector3.UP.cross(n) if absf(n.y) < 0.5 else Vector3.RIGHT
					var down := -n.cross(right) if absf(n.y) < 0.5 else Vector3.FORWARD
					var ts := []
					for k in 4:
						var lq: Vector3 = q[k]
						var a := 0.5 + lq.dot(right) / (2.0 * absf((h * right.abs()).length()) + 1e-6)
						var b := 0.5 + lq.dot(down) / (2.0 * absf((h * down.abs()).length()) + 1e-6)
						if flip:
							a = 1.0 - a
						ts.append(ProceduralCar._patch(rect, clampf(a, 0.0, 1.0), clampf(b, 0.0, 1.0)))
					quad(world[0], world[1], world[2], world[3], xf.basis * n, ts)
				else:
					quad(world[0], world[1], world[2], world[3], xf.basis * n, [ProceduralCar._sw(sw)])
		env = keep_env
		group = keep_group

	## A tube from `a` to `b`, `n` sides, radius `ra` at a and `rb` at b, closed at both ends;
	## `ma`, `mb` its UV2.x marks at each end.
	func tube(a: Vector3, b: Vector3, ra: float, rb: float, n: int, sw: int, caps := true, ma := 0.0, mb := 0.0) -> void:
		var keep_env := env
		var keep_group := group
		env = ENV[sw]
		group = 99
		var ax := (b - a).normalized()
		var x := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var y := ax.cross(x)
		var t := [ProceduralCar._sw(sw)]
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var d0 := x * cos(a0) + y * sin(a0)
			var d1 := x * cos(a1) + y * sin(a1)
			var out := x * cos((a0 + a1) * 0.5) + y * sin((a0 + a1) * 0.5)
			tri([a + d0 * ra, b + d0 * rb, b + d1 * rb], t, out, [ma, mb, mb])
			tri([a + d0 * ra, b + d1 * rb, a + d1 * ra], t, out, [ma, mb, ma])
			if caps:
				tri([a, a + d0 * ra, a + d1 * ra], t, -ax, [ma, ma, ma])
				tri([b, b + d0 * rb, b + d1 * rb], t, ax, [mb, mb, mb])
		env = keep_env
		group = keep_group

	## A ball, `n` round, squashed by `scale`.
	func ball(c: Vector3, r: float, n: int, sw: int, scale := Vector3.ONE) -> void:
		var keep_env := env
		var keep_group := group
		env = ENV[sw]
		group = 98
		var t := [ProceduralCar._sw(sw)]
		var rows := n / 2
		for i in rows:
			var t0 := PI * i / rows
			var t1 := PI * (i + 1) / rows
			for k in n:
				var p0 := TAU * k / n
				var p1 := TAU * (k + 1) / n
				var q := [_sph(t0, p0), _sph(t1, p0), _sph(t1, p1), _sph(t0, p1)]
				var w := []
				for e: Vector3 in q:
					w.append(c + e * r * scale)
				quad(w[0], w[1], w[2], w[3], (q[0] + q[2]).normalized(), t)
		env = keep_env
		group = keep_group

	static func _sph(t: float, ph: float) -> Vector3:
		return Vector3(sin(t) * cos(ph), cos(t), sin(t) * sin(ph))

	## A solid of revolution about X: profile `prof` (x along the axle, y the radius), `n`
	## round; `side` mirrors it outboard to -X; each segment's UV a patch across (or a swatch).
	func revolve(prof: Array, n: int, side: float, sw: int, rect := Rect2i(), group_id := 97) -> void:
		var keep_env := env
		var keep_group := group
		env = ENV[sw]
		group = group_id
		for k in prof.size() - 1:
			var q0: Vector2 = prof[k]
			var q1: Vector2 = prof[k + 1]
			var t := q1 - q0
			var nn := Vector2(-t.y, t.x)
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var am := (a0 + a1) * 0.5
				var ts := [ProceduralCar._sw(sw)]
				if rect.size != Vector2i.ZERO:
					var b0 := float(k) / (prof.size() - 1)
					var b1 := float(k + 1) / (prof.size() - 1)
					ts = [ProceduralCar._patch(rect, b0, 0.0), ProceduralCar._patch(rect, b1, 0.0),
						ProceduralCar._patch(rect, b1, 1.0), ProceduralCar._patch(rect, b0, 1.0)]
				quad(_rv(q0, a0, side), _rv(q1, a0, side), _rv(q1, a1, side), _rv(q0, a1, side),
					Vector3(nn.x * side, nn.y * cos(am), nn.y * sin(am)), ts)
		env = keep_env
		group = keep_group

	static func _rv(q: Vector2, a: float, side: float) -> Vector3:
		return Vector3(q.x * side, q.y * cos(a), q.y * sin(a))

	func append(o: _Mesh) -> void:
		pos.append_array(o.pos)
		uv.append_array(o.uv)
		uv2.append_array(o.uv2)
		col.append_array(o.col)
		grp.append_array(o.grp)

	func normals(at: PackedVector3Array) -> PackedVector3Array:
		var out := PackedVector3Array()
		out.resize(at.size())
		var sums := {}
		for i in range(0, at.size() - 2, 3):
			var fn := (at[i + 2] - at[i]).cross(at[i + 1] - at[i])
			for k in 3:
				out[i + k] = fn
				if grp[i + k] >= 0:
					var key := Vector4i(roundi(at[i + k].x * 2000.0), roundi(at[i + k].y * 2000.0), roundi(at[i + k].z * 2000.0), grp[i + k])
					sums[key] = sums.get(key, Vector3.ZERO) + fn
		for i in at.size():
			if grp[i] >= 0:
				var key := Vector4i(roundi(at[i].x * 2000.0), roundi(at[i].y * 2000.0), roundi(at[i].z * 2000.0), grp[i])
				var s: Vector3 = sums[key]
				# (Not round a crease sharper than the triangle's own side of it.)
				if s.normalized().dot(out[i].normalized()) > 0.5:
					out[i] = s
			out[i] = out[i].normalized()
		return out

	## The mesh, less `offset` (its part's origin).
	func commit(offset := Vector3.ZERO) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var at := PackedVector3Array()
		for v in pos:
			at.append(v - offset)
		arrays[Mesh.ARRAY_VERTEX] = at
		arrays[Mesh.ARRAY_NORMAL] = normals(at)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = col
		var mesh := ArrayMesh.new()
		var blends := []
		if not shapes.is_empty():
			mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
			for k in shapes.size():
				mesh.add_blend_shape("frame%d" % k)
				var sp := PackedVector3Array()
				for v in shapes[k]:
					sp.append(v - offset)
				var b := []
				b.resize(Mesh.ARRAY_MAX)
				b[Mesh.ARRAY_VERTEX] = sp
				b[Mesh.ARRAY_NORMAL] = normals(sp)
				blends.append(b)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
		return mesh


## The outside of the shell, for casting pictures onto (_project): its triangles, their
## outward normals, the piece each is part of, filed by where they lie along the car.
class _Shell:
	const BIN := 0.1
	var tris := PackedVector3Array()
	var normals := PackedVector3Array()
	var pieces := PackedStringArray()
	var bins := {}   # int -> Array of triangle indices

	func add(a: Vector3, b: Vector3, c: Vector3, out: Vector3, piece: String) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		if n.dot(out) < 0.0:
			n = -n
		var i := pieces.size()
		tris.append_array([a, b, c])
		normals.append(n.normalized())
		pieces.append(piece)
		var lo := floori(minf(a.z, minf(b.z, c.z)) / BIN)
		var hi := floori(maxf(a.z, maxf(b.z, c.z)) / BIN)
		for k in range(lo, hi + 1):
			if not bins.has(k):
				bins[k] = []
			(bins[k] as Array).append(i)


static func _mx(v: Vector3, side: float) -> Vector3:
	return Vector3(v.x * side, v.y, v.z)


static func _sw(i: int) -> Vector2:
	return Vector2(i * SWATCH + SWATCH * 0.5, SWATCH * 0.5) / SKIN


## UV at (`a`, `b`) across a skin patch (0..1 each, b down the picture), a texel in from its edge.
static func _patch(rect: Rect2i, a: float, b: float) -> Vector2:
	return (Vector2(rect.position) + Vector2(1, 1) + Vector2(a, b) * (Vector2(rect.size) - Vector2(2, 2))) / SKIN


## The body chart's UV at landmark position `k` (j + fraction) of station `z`.
static func _chart(p: Dictionary, z: float, k: float) -> Vector2:
	return _patch(BODY_RECT, (z + p.len) / (2.0 * p.len), k / (RING_POINTS - 1.0))


static func _piece(parts: Dictionary, key: String) -> _Mesh:
	if not parts.has(key):
		parts[key] = _Mesh.new()
	return parts[key]


## Ring point `v` (of landmark segment `k`) moved into the car by `by` m: the flank in, the roof down.
static func _inset(v: Vector3, k: int, by: float) -> Vector3:
	if k >= 9:
		return Vector3(v.x * (1.0 - by * 1.5), v.y - by, v.z)
	return Vector3(maxf(absf(v.x) - by, 0.0) * signf(v.x), v.y, v.z)


## The piece name a shell piece takes on side `side` (the doors, windows and sills each side's own).
static func _sided(piece: String, side: float) -> String:
	match piece:
		"door", "window":
			return "%s%d" % [piece, Nfs5Car.DOOR_LEFT if side > 0.0 else Nfs5Car.DOOR_RIGHT]
		"sill":
			return "sill%d" % (Nfs5Car.SILL_LEFT if side > 0.0 else Nfs5Car.SILL_RIGHT)
	return piece


## Where a grid of rays (`na` across `size.x`, `nb` down `size.y`, round `centre`, looking
## along `dir`) first meets the outside of the body: per ray [point, piece, normal, depth
## along `dir`], or [] for a miss. Also returns the across and up directions: [grid, right, up].
static func _cast(shell: _Shell, centre: Vector3, dir: Vector3, size: Vector2, na: int, nb: int) -> Array:
	var dd := dir.normalized()
	var right := Vector3.UP.cross(-dd)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := (-dd).cross(right).normalized()
	# The triangles under it, facing it, with their outline in its plane.
	var reach := 0.9
	var zr := absf(right.z) * size.x * 0.5 + absf(up.z) * size.y * 0.5 + absf(dd.z) * reach
	var cand: Array[int] = []
	var boxes: Array[Rect2] = []
	var seen := {}
	for b in range(floori((centre.z - zr) / _Shell.BIN), floori((centre.z + zr) / _Shell.BIN) + 1):
		if not shell.bins.has(b):
			continue
		for i: int in shell.bins[b]:
			if seen.has(i):
				continue
			seen[i] = true
			if shell.normals[i].dot(dd) > -0.05:
				continue
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			var depth_ok := false
			for k in 3:
				var q := shell.tris[i * 3 + k] - centre
				var pq := Vector2(q.dot(right), q.dot(up))
				lo = lo.min(pq)
				hi = hi.max(pq)
				if absf(q.dot(dd)) < reach:
					depth_ok = true
			if not depth_ok or hi.x < -size.x * 0.5 - 0.01 or lo.x > size.x * 0.5 + 0.01 \
					or hi.y < -size.y * 0.5 - 0.01 or lo.y > size.y * 0.5 + 0.01:
				continue
			cand.append(i)
			boxes.append(Rect2(lo, hi - lo).grow(0.002))
	var grid := []
	for ia in na:
		var col := []
		for ib in nb:
			# (A hair off the middle: a ray down the seam between the halves can slip through.)
			var pa := (ia / maxf(na - 1.0, 1.0) - (0.5 if na > 1 else 0.0)) * size.x + 0.0007
			var pb := ((0.5 if nb > 1 else 0.0) - ib / maxf(nb - 1.0, 1.0)) * size.y
			var from := centre + right * pa + up * pb - dd * reach
			var best := INF
			var hit := []
			for ci in cand.size():
				if not boxes[ci].has_point(Vector2(pa, pb)):
					continue
				var i := cand[ci]
				var at: Variant = Geometry3D.ray_intersects_triangle(from, dd, shell.tris[i * 3], shell.tris[i * 3 + 1], shell.tris[i * 3 + 2])
				if at == null:
					continue
				var t: float = ((at as Vector3) - from).dot(dd)
				if t < best:
					best = t
					hit = [at, shell.pieces[i], shell.normals[i], t]
			col.append(hit)
		grid.append(col)
	return [grid, right, up]


## The heights (y0, y1) of the stretch of the body at `x` that faces along -`dir` (the nose's
## or tail's upright face, bumper and all), looking for it between `lo` and `hi` at `z`.
static func _face_band(shell: _Shell, x: float, z: float, dir: Vector3, lo: float, hi: float) -> Vector2:
	const N := 40
	var c := _cast(shell, Vector3(x, (lo + hi) * 0.5, z), dir, Vector2(0.0, hi - lo), 1, N)
	var col: Array = c[0][0]
	var best := Vector2(INF, -INF)
	var run := Vector2(INF, -INF)
	for ib in range(N - 1, -1, -1):   # bottom up
		var h: Array = col[ib]
		var facing := not h.is_empty() and (h[2] as Vector3).dot(-dir.normalized()) > 0.8
		if facing:
			var y: float = (h[0] as Vector3).y
			run = Vector2(minf(run.x, y), maxf(run.y, y))
			if run.y - run.x > best.y - best.x:
				best = run
		else:
			run = Vector2(INF, -INF)
	return best


## A picture from the skin cast onto the outside of the body: the rectangle `size` (m) round
## `centre`, looking along `dir` (into the body), `rect` stretched across it (mirrored with
## `flip`), laid on whatever it meets first a few mm proud; each bit goes with the piece of
## the body it lies on, and none spans a step (where rays fell past an edge onto something
## behind). `lens` marks a lamp's lens. Returns where its middle landed (INF: nowhere).
static func _project(shell: _Shell, parts: Dictionary, centre: Vector3, dir: Vector3, size: Vector2, rect: Rect2i,
		flip := false, lens := 0.0, env := 0.5, na := 11, nb := 6, lift := 0.004) -> Vector3:
	var dd := dir.normalized()
	var grid: Array = _cast(shell, centre, dd, size, na, nb)[0]
	var mid: Vector3 = Vector3.INF
	var centre_hit: Array = grid[na / 2][nb / 2]
	if not centre_hit.is_empty():
		mid = centre_hit[0]
	var step := maxf(size.x / (na - 1.0), size.y / (nb - 1.0))
	for ia in na - 1:
		for ib in nb - 1:
			var cs := [grid[ia][ib], grid[ia + 1][ib], grid[ia + 1][ib + 1], grid[ia][ib + 1]]
			if cs.any(func(h: Array) -> bool: return h.is_empty()):
				continue
			var torn := false
			for e in 4:
				if ((cs[e][0] as Vector3) - (cs[(e + 1) % 4][0] as Vector3)).length() > step * 3.0 + 0.015:
					torn = true
			if torn:
				continue
			var a0 := ia / (na - 1.0)
			var a1 := (ia + 1) / (na - 1.0)
			if flip:
				a0 = 1.0 - a0
				a1 = 1.0 - a1
			var b0 := ib / (nb - 1.0)
			var b1 := (ib + 1) / (nb - 1.0)
			var m := _piece(parts, cs[0][1])
			var keep := [m.env, m.lens, m.group]
			m.env = env
			m.lens = lens
			m.group = -1
			var q := []
			for h: Array in cs:
				q.append((h[0] as Vector3) + (h[2] as Vector3) * lift)
			m.quad(q[0], q[1], q[2], q[3], -dd,
				[_patch(rect, a0, b0), _patch(rect, a1, b0), _patch(rect, a1, b1), _patch(rect, a0, b1)])
			m.env = keep[0]
			m.lens = keep[1]
			m.group = keep[2]
	return mid


## `rect` cast onto both sides of the car: `centre` and `dir` given for the +X side, mirrored
## for the other, the picture flipped there so its outboard end stays outboard (`flip` the
## +X side's). Returns both middles, +X first.
static func _project_pair(shell: _Shell, parts: Dictionary, centre: Vector3, dir: Vector3, size: Vector2, rect: Rect2i,
		flip := false, lens := 0.0, env := 0.5, na := 11, nb := 6) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for side in [1.0, -1.0]:
		out.append(_project(shell, parts, _mx(centre, side), _mx(dir, side), size, rect, flip != (side < 0.0), lens, env, na, nb))
	return out


# ------------------------------------------------------------------ building

static func _build(p: Dictionary) -> Dictionary:
	var L: float = p.len
	var W: float = p.wid
	var r: float = p.r
	var d := _layout(p)
	var parts := {}   # piece name -> _Mesh
	var shell := _Shell.new()

	var stations := _stations(p, d)
	var rings: Array[PackedVector3Array] = []
	var ks := PackedFloat32Array()
	var creases: Array = p.get("creases", [])
	var sharp: Array = SHARP + creases
	for v in stations:
		var f := _fine(_ring(p, v), sharp)
		rings.append(f[0])
		ks = f[1]

	# The shell, both halves, each strip to its piece; the paint mapped on the body chart.
	var nf := ks.size()
	var spine_y: float = GROUND + (p.clear + p.hood) * 0.5
	for i in stations.size() - 1:
		var zm := (stations[i] + stations[i + 1]) * 0.5
		var um := zm / L
		for f in nf - 1:
			var j := int(ks[f] + 1e-4)
			var sub := roundi((ks[f] - j) * SUBS[j])
			var m := _material(p, j, sub, um)
			var piece := _panel(p, d, j, zm, m)
			for side in [1.0, -1.0]:
				var key := _sided(piece, side)
				var pm := _piece(parts, key)
				var a := _mx(rings[i][f], side)
				var b := _mx(rings[i + 1][f], side)
				var c := _mx(rings[i + 1][f + 1], side)
				var e := _mx(rings[i][f + 1], side)
				# Outward: across the strip round the ring, crossed with along the car.
				var out: Vector3 = (e - b).cross(c - a) if side > 0.0 else (c - a).cross(e - b)
				# (Where the ends close the strips can turn on themselves: outward is away from
				# the car's spine, a line along its middle.)
				var q := (a + b + c + e) * 0.25
				var spine := q - Vector3(0.0, spine_y, clampf(q.z, -L + 0.9, L - 0.9))
				if out.length_squared() < 1e-12 or (j >= 3 and out.dot(spine) < 0.0):
					out = spine
				var t := [_sw(m)]
				if m == Sw.PAINT:
					t = [_chart(p, stations[i], ks[f]), _chart(p, stations[i + 1], ks[f]), _chart(p, stations[i + 1], ks[f + 1]), _chart(p, stations[i], ks[f + 1])]
				# (Normals split along the creases: the paint each side of one is shaded apart.)
				var band := 0
				for k: int in creases:
					if j >= k:
						band += 1
				pm.group = (1 + band * 50) if m == Sw.PAINT else m + 2
				pm.env = ENV[m]
				pm.quad(a, b, c, e, out, t)
				if m != Sw.GLASS and j >= 3:
					shell.add(a, b, c, out, key)
					shell.add(a, c, e, out, key)
				# The insides: a door's trim panel, a lid's underside (one-sided), the cabin's
				# walls and headlining.
				var inner := ""
				var by := 0.0
				var sw := Sw.CABIN
				if piece == "door":
					inner = key
					by = 0.07
				elif piece in ["bonnet", "boot"]:
					inner = piece
					by = 0.02
					sw = Sw.DARK
				elif piece == "body" and m in [Sw.PAINT, Sw.GBLACK] and zm < d.cab_f and zm > d.cab_r \
						and (j in DOOR_ROWS or (j >= 8 and _cabin(p, um) > 0.001)):
					inner = "cabin"
					by = 0.05 if j < 8 else 0.025
				if inner != "":
					var im := _piece(parts, inner)
					im.group = 40 + sw
					im.env = ENV[sw]
					im.mark = Nfs5Car.ONE_SIDED_MARK if sw == Sw.DARK else 0.0
					im.quad(_mx(_inset(rings[i][f], j, by), side), _mx(_inset(rings[i + 1][f], j, by), side),
						_mx(_inset(rings[i + 1][f + 1], j, by), side), _mx(_inset(rings[i][f + 1], j, by), side),
						-out, [_sw(sw)])
					im.mark = 0.0

	var lights: Array[Dictionary] = []
	var dressing := _dress(p, d, shell, parts, lights)

	# Pop-up headlamps: pods on the bonnet's front corners, shown raised.
	var popups: Array[Dictionary] = []
	if p.heads == "popup":
		var pod := _Mesh.new()
		var pz := L - 0.3
		for side in [1.0, -1.0]:
			var px: float = side * W * 0.6
			var top_y := _surf(p, pz, 9.0).y
			var c := Vector3(px, top_y + 0.05, pz)
			pod.box(Transform3D(Basis(), c), Vector3(0.14, 0.05, 0.1), Sw.GBLACK)
			pod.box(Transform3D(Basis(), c + Vector3(0, 0.052, -0.005)), Vector3(0.142, 0.003, 0.104), Sw.PAINT)
			pod.lens = 1.0
			pod.box(Transform3D(Basis(), c + Vector3(0, -0.002, 0.102)), Vector3(0.13, 0.042, 0.004), Sw.CHROME, HEAD_RECT, Vector3.BACK, side < 0.0)
			pod.lens = 0.0
			lights.append(_light("HWYN5", c + Vector3(0, 0, 0.11)))
		# (Down, they sink into the bonnet: Car tips them forward about their back edge.)
		popups.append({"name": "popup", "mesh": pod.commit(), "center": Vector3.ZERO})

	# Door mirrors: a rounded housing on an arm from the front corner of each door's window.
	var zm_mirror: float = minf(d.door_f - 0.1, lerpf(p.ws0, p.ws1, 0.25) * L)
	var mring := _ring(p, zm_mirror)
	for side in [1.0, -1.0]:
		var g: int = Nfs5Car.DOOR_LEFT if side > 0.0 else Nfs5Car.DOOR_RIGHT
		var hm := _piece(parts, "mirror%d" % g)
		var gm := _piece(parts, "mglass%d" % g)
		var base := mring[7].lerp(mring[8], 0.15)
		var pod_c := _mx(base + Vector3(0.14, 0.05, -0.02), side)
		hm.tube(_mx(base + Vector3(0.0, 0.0, 0.01), side), pod_c + Vector3(-side * 0.04, -0.02, 0.0), 0.018, 0.013, 6, Sw.GBLACK)
		hm.ball(pod_c + Vector3(0, 0, 0.012), 1.0, 14, Sw.PAINT, Vector3(0.085, 0.052, 0.05))
		gm.ball(pod_c + Vector3(0, 0, -0.03), 1.0, 14, Sw.MIRROR, Vector3(0.074, 0.043, 0.004))

	# Wipers parked on the scuttle at the windshield's foot.
	var wipers := _wipers(p, d)

	# Spoilers on the boot (or engine) lid.
	var spoilers := _spoilers(p, d)

	# Light bar across the roof; the siren dummies sit at its ends (red on +X, blue on -X).
	if p.get("lightbar", false):
		var body := _piece(parts, "body")
		var zl: float = (p.ws1 + p.rw1) * 0.5 * L
		var y: float = _top(p, zl) + 0.06
		body.box(Transform3D(Basis(), Vector3(0, y - 0.035, zl)), Vector3(0.62, 0.012, 0.13), Sw.GBLACK)
		for side in [1.0, -1.0]:
			body.box(Transform3D(Basis(), Vector3(side * 0.5, y - 0.05, zl)), Vector3(0.03, 0.03, 0.12), Sw.GBLACK)
		body.box(Transform3D(Basis(), Vector3(0, y, zl)), Vector3(0.1, 0.045, 0.11), Sw.CHROME)
		body.lens = 1.0
		body.tube(Vector3(0.1, y, zl), Vector3(0.62, y, zl), 0.045, 0.045, 12, Sw.RED)
		body.tube(Vector3(-0.1, y, zl), Vector3(-0.62, y, zl), 0.045, 0.045, 12, Sw.BLUE)
		body.lens = 0.0
		lights.append(_light("SMLN", Vector3(0.42, y, zl)))
		lights.append(_light("SMRN", Vector3(-0.42, y, zl)))
	# A radio aerial on the rear wing.
	if p.doors == 4:
		var at := _surf(p, d.boot_f - 0.12, 7.0) + Vector3(-0.05, 0, 0)
		_piece(parts, "body").tube(at, at + Vector3(0, 0.55, -0.12), 0.004, 0.002, 4, Sw.GBLACK)

	# The cabin, the driver, the bays.
	var cabin := _cabin_inside(p, d, parts)
	var driver := _driver(p, d, cabin)
	_bays(p, d, parts)

	# Wheels flush with the flanks; the model is +X outboard, mirrored for the right side.
	var wheel_l := _wheel(r, 1.0, p)
	var wheel_r := _wheel(r, -1.0, p)
	var wheels: Array[Dictionary] = []
	for slot in 4:
		var zw: float = (p.wf if slot < 2 else p.wr) * L
		var x := _ring(p, zw)[4].x - 0.025 - TYRE_W * 0.5
		var side := 1.0 if slot % 2 == 0 else -1.0
		var wl: Array = wheel_l if side > 0.0 else wheel_r
		wheels.append({"name": "wheel", "mesh": wl[0], "brake": wl[1], "center": Vector3(side * x, GROUND + r, zw), "slot": slot})

	return {"parts": _assemble(p, d, parts, wipers, spoilers, cabin, driver), "wheels": wheels, "lights": lights,
		"texture": _skin(p, d), "half_size": Vector3(W + maxf(p.flare[0], p.flare[1]), GROUND + p.roof, L), "popups": popups,
		"exhausts": dressing.exhausts, "plate": dressing.plate,
		"dash": {"eye": cabin.eye, "own_cabin": true}}


## What's cast onto the body and hung on it: the lamps (with their dummies in `lights`), the
## grille, intakes, badges, side markers and vents, the plate, the diffuser and the tail
## pipes. Returns {exhausts, plate}.
static func _dress(p: Dictionary, d: Dictionary, shell: _Shell, parts: Dictionary, lights: Array[Dictionary]) -> Dictionary:
	var L: float = p.len
	var W: float = p.wid
	var floor_y: float = GROUND + p.clear
	var fy7 := _ring(p, L - 0.1)[7].y
	var ry7 := _ring(p, -L + 0.1)[7].y
	var fwide := _ring(p, L - 0.3)[5].x
	var rwide := _ring(p, -L + 0.3)[5].x
	# The nose's and tail's upright faces (bumper and all), where things go on them.
	var nf := _face_band(shell, fwide * 0.55, L, Vector3(0, 0, -1), floor_y, fy7 + 0.12)
	var nr := _face_band(shell, rwide * 0.55, -L, Vector3(0, 0, 1), floor_y, ry7 + 0.12)
	if nf.x == INF:
		nf = Vector2(floor_y + 0.1, fy7)
	if nr.x == INF:
		nr = Vector2(floor_y + 0.1, ry7)

	# Headlamps: swept back over the front corners, or upright in the nose either side of
	# the grille; the indicators in their outboard ends.
	var hh := clampf((nf.y - nf.x) * 0.36, 0.1, 0.15)
	var head_y := nf.y - hh * 0.5 - 0.015
	match p.heads:
		"corner":
			var hd: Vector3 = p.get("head_dir", Vector3(-0.6, -0.4, -1.0))
			var back: float = p.get("head_back", 0.0)
			var at := _project_pair(shell, parts, Vector3(fwide * (0.64 - back * 0.4), nf.y - 0.01 + back * 0.3, L - back), hd,
				p.get("head_size", Vector2(0.46, 0.17)), HEAD_RECT, false, 1.0, 0.5, 15, 8)
			for k in 2:
				if at[k] != Vector3.INF:
					lights.append(_light("HWYN5", at[k]))
					lights.append(_light("IOYN5", at[k] + Vector3((1.0 - 2.0 * k) * 0.13, 0, -0.08)))
		"face":
			var at := _project_pair(shell, parts, Vector3(fwide * 0.62, head_y, L), Vector3(-0.15, -0.05, -1.0),
				Vector2(0.36, hh), HEAD_RECT, false, 1.0, 0.5, 11, 5)
			for k in 2:
				if at[k] != Vector3.INF:
					lights.append(_light("HWYN5", at[k] - Vector3((1.0 - 2.0 * k) * 0.04, 0, 0)))
					lights.append(_light("IOYN5", at[k] + Vector3((1.0 - 2.0 * k) * 0.15, 0, 0)))
		"popup":
			# Indicators and parking lamps in the bumper's corners.
			var at := _project_pair(shell, parts, Vector3(fwide * 0.74, lerpf(nf.x, nf.y, 0.6), L), Vector3(-0.35, 0, -1.0),
				Vector2(0.22, 0.05), MARKER_RECT, false, 1.0, 0.5, 7, 3)
			for k in 2:
				if at[k] != Vector3.INF:
					lights.append(_light("IOYN5", at[k]))
	# The grille, intakes in the bumper, fog lamps, the badge.
	match p.grille:
		"mesh":
			_project(shell, parts, Vector3(0, lerpf(nf.x, nf.y, 0.45), L), Vector3(0, -0.1, -1), Vector2(fwide * 0.8, 0.08), INTAKE_RECT, false, 0.0, 0.2, 13, 3)
		"bars":
			_project(shell, parts, Vector3(0, head_y, L), Vector3(0, -0.05, -1), Vector2(fwide * 0.6, hh * 0.92), GRILLE_RECT, false, 0.0, 0.8, 11, 4)
	if p.grille != "mesh":
		_project(shell, parts, Vector3(0, nf.x + 0.06, L), Vector3(0, -0.2, -1), Vector2(fwide * 0.7, 0.055), INTAKE_RECT, false, 0.0, 0.2, 13, 3)
	if p.grille != "bars":
		_project_pair(shell, parts, Vector3(fwide * 0.72, nf.x + 0.07, L), Vector3(-0.45, -0.15, -1.0),
			Vector2(0.22, 0.065), INTAKE_RECT, false, 0.0, 0.2, 7, 3)
	if p.get("fog", false):
		var at := _project_pair(shell, parts, Vector3(fwide * 0.66, nf.x + 0.07, L), Vector3(-0.2, 0, -1),
			Vector2(0.14, 0.065), HEAD_RECT, false, 1.0, 0.5, 6, 3)
		for k in 2:
			if at[k] != Vector3.INF:
				lights.append(_light("FWYN4", at[k]))
	_project(shell, parts, Vector3(0, nf.y + 0.015, L), Vector3(0, -0.7, -1), Vector2(0.07, 0.07), BADGE_RECT, false, 0.0, 0.9, 5, 5)
	# Side markers on the front wings (amber: they flash with the indicators).
	var mr := _ring(p, L - 0.42)
	_project_pair(shell, parts, Vector3(W + 0.2, lerpf(mr[4].y, mr[5].y, 0.75), L - 0.42), Vector3(-1, 0, 0.1), Vector2(0.09, 0.03), MARKER_RECT, false, 1.0, 0.5, 4, 3)
	# Vents in the flanks behind the doors, feeding the engine.
	if p.get("vents", false):
		var vz: float = (d.door_r + d.arch_r) * 0.5
		var vr := _ring(p, vz)
		_project_pair(shell, parts, Vector3(W + 0.2, lerpf(vr[4].y, vr[5].y, 0.7), vz), Vector3(-1, 0, 0), Vector2(0.34, 0.13), INTAKE_RECT, false, 0.0, 0.2, 9, 5)

	# Tail lamps along the top of the tail's upright face: stop/tail in the middle, the
	# indicator outboard, the reversing lamp inboard.
	var th := clampf((nr.y - nr.x) * 0.34, 0.1, 0.17)
	var ty := nr.y - th * 0.5 - 0.012
	match p.tails:
		"bar":
			var at := _project(shell, parts, Vector3(0, ty, -L), Vector3(0, -0.1, 1), Vector2(rwide * 1.85, th), TAIL_RECT, false, 1.0, 0.5, 25, 5)
			if at != Vector3.INF:
				for side in [1.0, -1.0]:
					var x: float = side * rwide * 0.7
					lights.append(_light("TRYN5", Vector3(x, at.y, at.z)))
					lights.append(_light("BRYN5", Vector3(x, at.y, at.z)))
					lights.append(_light("IOYN5", Vector3(side * rwide * 0.86, at.y, at.z + 0.03)))
					lights.append(_light("RWYN3", Vector3(side * 0.25, at.y, at.z - 0.02)))
		_:
			var at := _project_pair(shell, parts, Vector3(rwide * 0.6, ty, -L), Vector3(-0.35, -0.1, 1), Vector2(0.52, th), TAIL_RECT, true, 1.0, 0.5, 15, 5)
			for k in 2:
				if at[k] == Vector3.INF:
					continue
				var s := 1.0 - 2.0 * k
				lights.append(_light("TRYN5", at[k]))
				lights.append(_light("BRYN5", at[k]))
				lights.append(_light("RWYN3", at[k] - Vector3(s * 0.16, 0, -0.01)))
				lights.append(_light("IOYN5", at[k] + Vector3(s * 0.16, 0, 0.02)))
			_project(shell, parts, Vector3(0, ty, -L), Vector3(0, -0.1, 1), Vector2(0.07, 0.07), BADGE_RECT, false, 0.0, 0.9, 5, 5)
	# The plate in its recess, under the lamps.
	var plate_y := clampf(lerpf(nr.x, ty - th * 0.5, 0.5), nr.x + 0.08, ty - th * 0.5 - 0.075)
	var plate_at := _project(shell, parts, Vector3(0, plate_y, -L), Vector3(0, 0, 1), Vector2(0.36, 0.13), PLATE_RECT, false, 0.0, 0.5, 7, 4, 0.006)
	var plate := {}
	if plate_at != Vector3.INF:
		plate = {"pos": plate_at - Vector3(0, 0, 0.004), "euro": p.euro}
	if p.get("diffuser", false):
		_project(shell, parts, Vector3(0, nr.x + 0.01, -L), Vector3(0, -0.6, 1), Vector2(rwide * 1.3, 0.1), DIFF_RECT, false, 0.0, 0.2, 15, 4)
	var tail := _ring(p, -L + 0.1)

	# The tail pipes, poking out under the rear bumper.
	var exhausts: Array[Vector3] = []
	var pipes: Array[float] = []
	match int(p.pipes):
		1: pipes = [-0.5]
		2: pipes = [0.5, -0.5]
		4: pipes = [0.36, 0.5, -0.36, -0.5]
	var bump_r := _piece(parts, "bumper_r")
	for fx in pipes:
		var y := maxf(tail[2].y + 0.045, nr.x - 0.02)
		var x: float = fx * rwide
		var probe: Array = _cast(shell, Vector3(x, y + 0.07, -L), Vector3(0, 0, 1), Vector2.ZERO, 1, 1)[0][0][0]
		var z_end: float = ((probe[0] as Vector3).z if not probe.is_empty() else -L + 0.1) - 0.04
		var tip := Vector3(x, y, z_end)
		bump_r.tube(tip + Vector3(0, 0.01, 0.3), tip, 0.03, 0.036, 14, Sw.CHROME, false)
		bump_r.tube(tip + Vector3(0, 0, 0.02), tip, 0.03, 0.03, 14, Sw.DARK, true)
		exhausts.append(tip)
	# The third brake lamp, up on the parcel shelf behind the rear window.
	var shelf_z: float = p.rw0 * L + 0.06
	var shelf_y := _top(p, shelf_z) + 0.025
	var cab := _piece(parts, "cabin")
	cab.lens = 1.0
	cab.box(Transform3D(Basis(), Vector3(0, shelf_y, shelf_z)), Vector3(0.14, 0.015, 0.02), Sw.RED)
	cab.lens = 0.0
	lights.append(_light("BRYN3", Vector3(0, shelf_y, shelf_z - 0.03)))
	return {"exhausts": exhausts, "plate": plate}


static func _assemble(p: Dictionary, d: Dictionary, parts: Dictionary, wipers: Array, spoilers: Array,
		cabin: Dictionary, driver: Dictionary) -> Array[Dictionary]:
	var L: float = p.len
	var out: Array[Dictionary] = []
	# How each door and lid swings: about the door's front edge (upright), the bonnet's back
	# edge and the boot's front one (across the car), the free edge out or up.
	var motion := {}
	for g: int in [Nfs5Car.DOOR_LEFT, Nfs5Car.DOOR_RIGHT, Nfs5Car.BONNET, Nfs5Car.BOOT]:
		var key: String = {Nfs5Car.BONNET: "bonnet", Nfs5Car.BOOT: "boot"}.get(g, "door%d" % g)
		if not parts.has(key):
			continue
		var hinge: Vector3
		var axis: Vector3
		var door := g in [Nfs5Car.DOOR_LEFT, Nfs5Car.DOOR_RIGHT]
		var side := 1.0 if g == Nfs5Car.DOOR_LEFT else -1.0
		if door:
			hinge = _mx(_surf(p, d.door_f, 5.0), side)
			axis = Vector3.UP
		elif g == Nfs5Car.BONNET:
			hinge = Vector3(0, _top(p, d.bonnet_r), d.bonnet_r)
			axis = Vector3.RIGHT
		else:
			hinge = Vector3(0, _top(p, d.boot_f), d.boot_f)
			axis = Vector3.RIGHT
		var c := _box_of(parts[key]).get_center()
		var turn: float = Nfs5Car.LID_OPEN[g]
		var away := Vector3(side, 0.0, 0.0) if door else Vector3.UP
		if (Basis(axis, turn) * (c - hinge) - (c - hinge)).dot(away) < 0.0:
			turn = -turn
		motion[g] = {"lid": g, "hinge": hinge, "axis": axis, "open": turn}

	var add := func(key: String, extra: Dictionary) -> void:
		if parts.has(key) and not (parts[key] as _Mesh).is_empty():
			out.append({"name": key, "mesh": (parts[key] as _Mesh).commit(), "center": Vector3.ZERO}.merged(extra))
	var steering := {"pivot": cabin.pivot, "axis": cabin.axis}
	add.call("body", {})
	add.call("cabin", {"steering": steering})
	add.call("glass", {"glass": true})
	for g: int in [Nfs5Car.DOOR_LEFT, Nfs5Car.DOOR_RIGHT]:
		var side := 1.0 if g == Nfs5Car.DOOR_LEFT else -1.0
		add.call("door%d" % g, motion.get(g, {}))
		var wkey := "window%d" % g
		if parts.has(wkey):
			# The window goes down its own height, leaning as it does, below the door's belt
			# line (y = a + slope z, fitted along the pane's foot) out of sight.
			var foot := PackedVector2Array()
			for zz in [d.door_r + 0.05, d.door_f - 0.05]:
				var ring := _ring(p, zz)
				foot.append(Vector2(zz, ring[7].y))
			var slope := (foot[1].y - foot[0].y) / (foot[1].x - foot[0].x)
			var a := foot[0].y - slope * foot[0].x - 0.004
			var mid_ring := _ring(p, clampf(0.0, d.door_r, d.door_f))
			var h := maxf(mid_ring[8].y - mid_ring[7].y, 0.05)
			var lean := (mid_ring[8].x - mid_ring[7].x) / h
			add.call(wkey, {"glass": true, "window": g, "drop": Vector3(-lean * h * side, -h, 0.0), "belt": Vector2(a, slope)}.merged(motion.get(g, {})))
		var loose: int = Nfs5Car.MIRROR_OFF[g]
		add.call("mirror%d" % g, {"loose": loose}.merged(motion.get(g, {})))
		if parts.has("mglass%d" % g):
			var gc := _box_of(parts["mglass%d" % g]).get_center()
			add.call("mglass%d" % g, {"loose": loose, "mirror_glass": {"point": gc - Vector3(0, 0, 0.003),
				"normal": Vector3(-side * 0.15, 0.0, -1.0).normalized()}}.merged(motion.get(g, {})))
	for g: int in [Nfs5Car.SILL_LEFT, Nfs5Car.SILL_RIGHT]:
		add.call("sill%d" % g, {"loose": g})
	add.call("bumper_f", {"loose": Nfs5Car.BUMPER_FRONT})
	add.call("bumper_r", {"loose": Nfs5Car.BUMPER_REAR})
	add.call("bonnet", motion.get(Nfs5Car.BONNET, {}))
	add.call("boot", motion.get(Nfs5Car.BOOT, {}))
	add.call("hatch_glass", {"glass": true}.merged(motion.get(Nfs5Car.BOOT, {})))
	# The bays, each under its lid (shown while it's open).
	for g: int in [Nfs5Car.BONNET, Nfs5Car.BOOT]:
		add.call("bay%d" % g, {"bay": g})
	# The spoiler rides on the boot lid, and comes off on its own.
	var on_boot: Dictionary = motion.get(Nfs5Car.BOOT, {})
	for sp: Dictionary in spoilers:
		out.append(sp.merged({"loose": Nfs5Car.SPOILER}).merged(on_boot))
	for w: Dictionary in wipers:
		out.append(w)
	out.append(driver)
	for n: Dictionary in cabin.needles:
		out.append(n)
	return out


static func _box_of(m: _Mesh) -> AABB:
	var b := AABB(m.pos[0], Vector3.ZERO)
	for v in m.pos:
		b = b.expand(v)
	return b


## The wipers: two, parked along the windshield's foot, sweeping up it in WIPER_FRAMES
## blend shapes (frame 0 parked).
static func _wipers(p: Dictionary, d: Dictionary) -> Array[Dictionary]:
	var L: float = p.len
	var foot_z: float = p.ws0 * L - 0.05
	var top_z: float = lerpf(p.ws0, p.ws1, 0.75) * L
	var foot := _surf(p, foot_z, 10.0)
	var up := (Vector3(0, _top(p, top_z), top_z) - Vector3(0, _top(p, foot_z), foot_z)).normalized()
	var out: Array[Dictionary] = []
	var hw: float = _ring(p, foot_z)[7].x
	for k in 2:
		# Pivots on the right (-X); parked pointing left along the foot, swept up and over.
		var pivot := Vector3(lerpf(-hw * 0.75, hw * 0.05, k), _top(p, foot_z) + 0.02, foot_z)
		pivot.y = maxf(pivot.y, foot.y + 0.02)
		var length := hw * 0.78
		var wm: _Mesh = null
		for f in WIPER_FRAMES:
			var ang := Nfs5Car.WIPER_SWEEP * f / (WIPER_FRAMES - 1.0)
			var along := Vector3.RIGHT * cos(ang) + up * sin(ang)
			var fm := _Mesh.new()
			var tip := pivot + along * length
			var mid := pivot + along * length * 0.55
			# Lift each point off the glass to just above it.
			var lift := func(v: Vector3) -> Vector3:
				var gy := _glass_y(p, v.x, v.z)
				return Vector3(v.x, maxf(v.y, gy + 0.018), v.z)
			fm.tube(pivot, lift.call(mid), 0.012, 0.008, 5, Sw.TRIM)
			fm.tube(lift.call(mid), lift.call(tip), 0.008, 0.006, 5, Sw.TRIM)
			# The blade, under the arm's outer half.
			var b0: Vector3 = lift.call(pivot + along * length * 0.25)
			var b1: Vector3 = lift.call(tip)
			fm.tube(b0 + Vector3(0, -0.006, 0), b1 + Vector3(0, -0.006, 0), 0.006, 0.006, 4, Sw.TYRE)
			if wm == null:
				wm = fm
			wm.shapes.append(fm.pos)
		out.append({"name": "wiper%d" % k, "mesh": wm.commit(), "center": Vector3.ZERO, "wiper_frames": WIPER_FRAMES})
	return out


## The windshield's height at (x, z): its ring's top points, between the roof rail and the middle.
static func _glass_y(p: Dictionary, x: float, z: float) -> float:
	var ring := _ring(p, z)
	var ax := absf(x)
	for k in range(RING_POINTS - 1, 7, -1):
		var a := ring[k]
		var b := ring[k - 1]
		if ax >= a.x and ax <= b.x:
			return lerpf(a.y, b.y, (ax - a.x) / maxf(b.x - a.x, 1e-4))
	return ring[8].y


## The spoilers: a lip or a wing on posts, fixed; or one that rises at speed: down, up and
## on its way between them ("moving", SPOILER_FRAMES blend shapes).
static func _spoilers(p: Dictionary, d: Dictionary) -> Array[Dictionary]:
	var L: float = p.len
	var W: float = p.wid
	var out: Array[Dictionary] = []
	var zs := -L + 0.22
	var sr := _ring(p, zs)
	var deck := sr[RING_POINTS - 1].y
	match int(p.spoiler):
		1:
			var m := _Mesh.new()
			m.box(Transform3D(Basis(), Vector3(0, deck + 0.014, -L + 0.17)), Vector3(sr[6].x - 0.08, 0.016, 0.07), Sw.PAINT)
			out.append({"name": "spoiler", "mesh": m.commit(), "center": Vector3.ZERO, "spoiler": "fixed"})
		2:
			var m := _Mesh.new()
			var top := deck + 0.2
			for side in [1.0, -1.0]:
				m.box(Transform3D(Basis(), Vector3(side * W * 0.55, (top + sr[9].y) * 0.5, zs)), Vector3(0.02, (top - sr[9].y) * 0.5, 0.05), Sw.TRIM)
			m.box(Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0, top, zs - 0.02)), Vector3(W * 0.92, 0.022, 0.15), Sw.PAINT)
			for side in [1.0, -1.0]:
				m.box(Transform3D(Basis(), Vector3(side * W * 0.92, top - 0.03, zs - 0.02)), Vector3(0.012, 0.07, 0.16), Sw.PAINT)
			out.append({"name": "spoiler", "mesh": m.commit(), "center": Vector3.ZERO, "spoiler": "fixed"})
		3:
			var span: float = sr[6].x - 0.12
			var wing := func(lift: float) -> _Mesh:
				var m := _Mesh.new()
				var y := deck + 0.016 + lift
				m.box(Transform3D(Basis(Vector3.RIGHT, -0.12 * lift / SPOILER_LIFT), Vector3(0, y, zs)), Vector3(span, 0.016, 0.11), Sw.PAINT)
				for side in [1.0, -1.0]:
					var post_h := maxf(lift * 0.5, 0.004)
					m.box(Transform3D(Basis(), Vector3(side * span * 0.6, deck + post_h, zs)), Vector3(0.02, post_h, 0.06), Sw.TRIM)
				return m
			var down: _Mesh = wing.call(0.0)
			var up: _Mesh = wing.call(SPOILER_LIFT)
			out.append({"name": "spoiler_down", "mesh": down.commit(), "center": Vector3.ZERO, "spoiler": "down"})
			out.append({"name": "spoiler_up", "mesh": up.commit(), "center": Vector3.ZERO, "spoiler": "up"})
			var moving: _Mesh = wing.call(0.0)
			for f in SPOILER_FRAMES:
				moving.shapes.append((wing.call(SPOILER_LIFT * f / (SPOILER_FRAMES - 1.0)) as _Mesh).pos)
			out.append({"name": "spoiler_moving", "mesh": moving.commit(), "center": Vector3.ZERO, "spoiler": "moving",
				"spoiler_frames": SPOILER_FRAMES})
	return out


## The cabin: floor, seats, the dash with its dials and needles, the steering wheel and its
## column. Returns where the driver sits and the wheel turns: {eye, hip, pivot, axis,
## wheel (its middle), needles (their parts)}.
static func _cabin_inside(p: Dictionary, d: Dictionary, parts: Dictionary) -> Dictionary:
	var L: float = p.len
	var m := _piece(parts, "cabin")
	m.group = -1
	var floor_y: float = GROUND + p.clear + 0.1
	var roof_y: float = GROUND + p.roof
	var mid_z: float = (p.ws1 + p.rw1) * 0.5 * L
	var hw: float = _ring(p, mid_z)[6].x - 0.06
	var dx := minf(hw * 0.46, 0.4)   # the seats' middles either side
	var eye := Vector3(dx, roof_y - EYE_BELOW_ROOF, lerpf(p.ws1, p.rw1, 0.6) * L)
	var seat_y := maxf(floor_y + 0.12, eye.y - 0.78)
	var hip := Vector3(dx, seat_y + 0.04, eye.z - 0.05)
	# Floor, firewall and rear bulkhead.
	var dash_z: float = d.cab_f
	m.box(Transform3D(Basis(), Vector3(0, floor_y - 0.01, (dash_z + d.cab_r) * 0.5)), Vector3(hw, 0.01, (dash_z - d.cab_r) * 0.5), Sw.CARPET)
	m.box(Transform3D(Basis(), Vector3(0, (floor_y + _ring(p, dash_z)[6].y) * 0.5, dash_z + 0.04)),
		Vector3(hw, (_ring(p, dash_z)[6].y - floor_y) * 0.5, 0.02), Sw.DARK)
	var back_top := minf(_ring(p, d.cab_r)[7].y, roof_y - 0.1)
	m.box(Transform3D(Basis(), Vector3(0, (floor_y + back_top) * 0.5, d.cab_r - 0.02)), Vector3(hw, (back_top - floor_y) * 0.5, 0.02), Sw.CABIN)
	# The parcel shelf (or the rear deck's inside) up to the rear window.
	var shelf_z: float = p.rw0 * L
	m.box(Transform3D(Basis(), Vector3(0, _top(p, shelf_z) - 0.005, (shelf_z + d.cab_r) * 0.5 - 0.02)),
		Vector3(hw, 0.012, maxf((shelf_z - d.cab_r) * 0.5, 0.05) + 0.03), Sw.CARPET)
	# The dash: from the windshield's foot back toward the driver, under the glass.
	var dash_top: float = _ring(p, d.cab_f)[7].y - 0.015
	var dash_back := eye.z + 0.62
	m.box(Transform3D(Basis(), Vector3(0, (dash_top + floor_y + 0.25) * 0.5, (dash_back + dash_z) * 0.5)),
		Vector3(hw, (dash_top - floor_y - 0.25) * 0.5, (dash_z - dash_back) * 0.5), Sw.DARK)
	# Its binnacle over the dials, and the dials' faces looking at the driver.
	var bin_c := Vector3(dx, dash_top + 0.025, dash_back + 0.05)
	var tilt := Basis(Vector3.RIGHT, 0.25)
	var face_c := bin_c + Vector3(0, -0.005, -0.03)
	m.box(Transform3D(Basis(), face_c + Vector3(0, 0.068, 0.04)), Vector3(0.2, 0.01, 0.07), Sw.DARK)
	m.box(Transform3D(tilt, face_c), Vector3(0.18, 0.055, 0.006), Sw.DARK, DIAL_RECT, Vector3.FORWARD)
	var needles: Array[Dictionary] = []
	var dial_axis := tilt * Vector3.BACK   # into the dial, away from the driver
	for k in 2:
		var hub := face_c + tilt * Vector3((0.09 if k == 0 else -0.09), 0.0, -0.008)
		var nm := _Mesh.new()
		nm.box(Transform3D(tilt, hub + tilt * Vector3(0, 0.022, 0)), Vector3(0.0025, 0.024, 0.0015), Sw.AMBER)
		nm.box(Transform3D(tilt, hub), Vector3(0.006, 0.006, 0.002), Sw.TRIM)
		needles.append({"name": "needle_speed" if k == 0 else "needle_rpm", "mesh": nm.commit(hub), "center": hub,
			"needle": "speed" if k == 0 else "rpm", "axis": dial_axis, "zero": Nfs5Car.NEEDLE_ZERO * TAU})
	# The centre console and the gear lever.
	m.box(Transform3D(Basis(), Vector3(0, floor_y + 0.1, (dash_back + hip.z) * 0.5)), Vector3(0.09, 0.1, (dash_back - hip.z) * 0.5), Sw.DARK)
	m.tube(Vector3(0, floor_y + 0.2, hip.z + 0.35), Vector3(0, floor_y + 0.36, hip.z + 0.31), 0.008, 0.008, 5, Sw.CHROME, false)
	m.ball(Vector3(0, floor_y + 0.37, hip.z + 0.31), 0.025, 8, Sw.TRIM)
	# The seats: cushion and back, the back leaning as far as the roof makes it.
	var lean := clampf(0.25 + (0.78 - (eye.y - seat_y)) * 1.2, 0.2, 0.7)
	var rows: Array[float] = [hip.z]
	if p.doors == 4:
		rows.append(d.cab_r + 0.35)
	for row in rows.size():
		for side in [1.0, -1.0]:
			var sx: float = side * dx
			var sz: float = rows[row]
			var sy := seat_y if row == 0 else maxf(floor_y + 0.1, seat_y - 0.02)
			m.box(Transform3D(Basis(), Vector3(sx, sy - 0.02, sz + 0.2)), Vector3(0.24, 0.06, 0.24), Sw.CABIN, SEAT_RECT, Vector3.UP)
			var bb := Basis(Vector3.RIGHT, -lean)
			var back_c := Vector3(sx, sy + 0.04, sz - 0.02) + bb * Vector3(0, 0.3, -0.06)
			m.box(Transform3D(bb, back_c), Vector3(0.24, 0.3, 0.06), Sw.CABIN, SEAT_RECT, Vector3.BACK)
			if row == 0:
				m.box(Transform3D(bb, back_c + bb * Vector3(0, 0.38, 0)), Vector3(0.13, 0.08, 0.05), Sw.CABIN)
	# The steering wheel, square to its column (forward and down from the driver's chest).
	var axis := Vector3(0, -0.42, 1.0).normalized()
	var wheel_c := Vector3(dx, eye.y - 0.42, eye.z + 0.5)
	var wb := Basis.looking_at(-axis, Vector3.UP)   # its Z down the column, X across the wheel
	m.mark = 1.0
	const N := 32
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		m.tube(wheel_c + wb * Vector3(cos(a0), sin(a0), 0) * WHEEL_RADIUS, wheel_c + wb * Vector3(cos(a1), sin(a1), 0) * WHEEL_RADIUS,
			0.016, 0.016, 6, Sw.TRIM, false, 1.0, 1.0)
	for a in [0.0, PI, PI * 1.5]:
		m.tube(wheel_c, wheel_c + wb * Vector3(cos(a), sin(a), 0) * WHEEL_RADIUS, 0.012, 0.01, 4, Sw.TRIM, false, 1.0, 1.0)
	m.tube(wheel_c + axis * 0.02, wheel_c - axis * 0.03, 0.05, 0.05, 10, Sw.TRIM, true, 1.0, 1.0)
	m.mark = 0.0
	m.tube(wheel_c + axis * 0.03, wheel_c + axis * 0.3, 0.03, 0.04, 8, Sw.DARK, false)
	return {"eye": eye, "hip": hip, "pivot": wheel_c, "axis": axis, "wheel": wheel_c, "basis": wb, "needles": needles}


## The driver, in race suit and helmet (in the car's colour), hands on the wheel at a quarter
## to three: they turn with it (UV2.x 1), his forearms stretching to them; his head goes
## in the in-car view (UV2.x Nfs5Car.HEAD_MARK).
static func _driver(p: Dictionary, d: Dictionary, cabin: Dictionary) -> Dictionary:
	var m := _Mesh.new()
	var eye: Vector3 = cabin.eye
	var hip: Vector3 = cabin.hip
	var wheel_c: Vector3 = cabin.wheel
	var wb: Basis = cabin.basis
	var neck := eye + Vector3(0, -0.13, -0.06)
	var chest := neck + Vector3(0, -0.08, 0)
	# Torso from the hips up to the neck, the shoulders across its top.
	m.tube(hip + Vector3(0, 0.05, 0), chest, 0.15, 0.17, 8, Sw.SUIT)
	m.box(Transform3D(Basis(), chest - Vector3(0, 0.02, 0)), Vector3(0.2, 0.06, 0.08), Sw.SUIT)
	m.tube(chest, neck + Vector3(0, 0.03, 0), 0.05, 0.05, 6, Sw.SUIT)
	# The head: the helmet in the paint, its visor.
	m.mark = Nfs5Car.HEAD_MARK
	m.ball(eye + Vector3(0, 0.02, -0.03), 0.135, 12, Sw.PAINT, Vector3(0.9, 1.0, 1.05))
	m.box(Transform3D(Basis(Vector3.RIGHT, 0.1), eye + Vector3(0, 0.0, 0.085)), Vector3(0.09, 0.04, 0.03), Sw.VISOR)
	m.mark = 0.0
	# Arms: upper arms from the shoulders, forearms stretching to the hands on the rim.
	for side in [1.0, -1.0]:
		var shoulder := chest + Vector3(side * 0.19, 0.02, 0)
		var grip := wheel_c + wb * Vector3(side * cos(0.35), sin(0.35), 0) * WHEEL_RADIUS
		var elbow := (shoulder + grip) * 0.5 + Vector3(side * 0.07, -0.1, -0.02)
		m.tube(shoulder, elbow, 0.05, 0.045, 6, Sw.SUIT)
		m.tube(elbow, grip, 0.045, 0.035, 6, Sw.SUIT, true, 0.0, 1.0)
		m.mark = 1.0
		m.ball(grip, 0.04, 6, Sw.TRIM, Vector3(1.0, 1.1, 0.9))
		m.mark = 0.0
	# Legs: thighs to the knees, shins down to the pedals.
	for side in [1.0, -1.0]:
		var h := hip + Vector3(side * 0.1, 0.0, 0.05)
		var knee := Vector3(h.x, maxf(h.y + 0.1, eye.y - 0.62), hip.z + 0.45)
		var foot := Vector3(h.x * 0.9, GROUND + p.clear + 0.16, knee.z + 0.35)
		m.tube(h, knee, 0.075, 0.06, 6, Sw.SUIT)
		m.tube(knee, foot, 0.055, 0.045, 6, Sw.SUIT)
		m.box(Transform3D(Basis(), foot + Vector3(0, 0.02, 0.05)), Vector3(0.045, 0.035, 0.11), Sw.TRIM)
	return {"name": "driver", "mesh": m.commit(), "center": Vector3.ZERO, "driver": true,
		"steering": {"pivot": cabin.pivot, "axis": cabin.axis}}


## The bays under the bonnet and the boot lid (shown while their lid is open): a tub of
## inner wings, floor and bulkheads; the engine in one, luggage space in the other.
static func _bays(p: Dictionary, d: Dictionary, parts: Dictionary) -> void:
	var rear_engine: bool = p.engine == "rear"
	for g: int in [Nfs5Car.BONNET, Nfs5Car.BOOT]:
		var z0: float = d.bonnet_r if g == Nfs5Car.BONNET else d.boot_r
		var z1: float = d.bonnet_f if g == Nfs5Car.BONNET else d.boot_f
		if p.get("hatch", false) and g == Nfs5Car.BOOT:
			z1 = d.cab_r
		if z1 - z0 < 0.2:
			continue
		var m := _piece(parts, "bay%d" % g)
		m.group = -1
		var zc := (z0 + z1) * 0.5
		var ring := _ring(p, zc)
		var hw := ring[6].x - 0.1
		var floor_y := ring[0].y + 0.1
		var top := minf(_ring(p, z0)[7].y, _ring(p, z1)[7].y) - 0.03
		var hz := (z1 - z0) * 0.5 - 0.02
		var hy := (top - floor_y) * 0.5
		var cy := (top + floor_y) * 0.5
		m.box(Transform3D(Basis(), Vector3(0, floor_y, zc)), Vector3(hw, 0.01, hz), Sw.DARK)
		for side in [1.0, -1.0]:
			m.box(Transform3D(Basis(), Vector3(side * hw, cy, zc)), Vector3(0.01, hy, hz), Sw.DARK)
		for e in [-1.0, 1.0]:
			m.box(Transform3D(Basis(), Vector3(0, cy, zc + e * hz)), Vector3(hw, hy, 0.01), Sw.DARK)
		var engine := (g == Nfs5Car.BOOT) == rear_engine
		if engine:
			var ew := minf(hw * 0.55, 0.32)
			var eh := minf(hy * 2.0 - 0.06, 0.26)
			var el := minf(hz * 0.8, 0.3)
			var ec := Vector3(0, floor_y + eh * 0.5, zc)
			m.box(Transform3D(Basis(), ec), Vector3(ew, eh * 0.5, el), Sw.DARK)
			# Two cam covers (red, ribbed), the air box and the battery.
			for side in [1.0, -1.0]:
				m.box(Transform3D(Basis(Vector3.BACK, side * 0.3), ec + Vector3(side * ew * 0.5, eh * 0.5, 0)),
					Vector3(ew * 0.42, 0.025, el * 0.95), Sw.RED, CAM_RECT, Vector3.UP)
			m.tube(ec + Vector3(-ew * 0.2, eh * 0.5 + 0.03, el * 0.6), ec + Vector3(-ew * 0.2, eh * 0.5 + 0.05, el * 0.6), 0.12, 0.12, 12, Sw.TRIM)
			m.box(Transform3D(Basis(), Vector3(hw * 0.7, floor_y + 0.1, zc - hz * 0.5)), Vector3(0.1, 0.09, 0.08), Sw.TRIM)
			m.tube(Vector3(-hw * 0.7, floor_y + 0.02, zc + hz * 0.5), Vector3(-hw * 0.7, floor_y + 0.18, zc + hz * 0.5), 0.06, 0.06, 8, Sw.WHITE)
		else:
			# Carpet, and the spare wheel under its cover.
			m.box(Transform3D(Basis(), Vector3(0, floor_y + 0.02, zc)), Vector3(hw - 0.02, 0.01, hz - 0.02), Sw.CARPET)
			m.tube(Vector3(0, floor_y + 0.03, zc), Vector3(0, floor_y + 0.1, zc), minf(hz, hw) * 0.7, minf(hz, hw) * 0.7, 14, Sw.CARPET)


## A wheel: the tyre (its tread a pattern round it, rounded shoulders, bulging walls) on a
## rim: a polished lip, the barrel, and spokes modelled from the hub out to the lip, dished;
## or a pressed steel wheel or hub cap, the skin's picture with its holes cut out. Behind
## them the brake disc and calliper (which steer and ride with the wheel but don't turn).
## Axle along X, `side` outboard. Returns [wheel, brake].
static func _wheel(r: float, side: float, p: Dictionary) -> Array:
	const N := 40
	var m := _Mesh.new()
	var rr := r * 0.66
	var hx := TYRE_W * 0.5
	var face := hx - 0.025   # the rim's outer face
	# The tyre: its walls plain rubber, the tread band the tread's pattern (each step round
	# the picture once).
	m.revolve([Vector2(-hx + 0.012, rr), Vector2(-hx - 0.004, r * 0.76), Vector2(-hx - 0.007, r * 0.86), Vector2(-hx * 0.95, r * 0.95),
		Vector2(-hx * 0.82, r * 0.99)], N, side, Sw.TYRE, WALL_RECT, 10)
	m.revolve([Vector2(-hx * 0.82, r * 0.99), Vector2(-hx * 0.3, r), Vector2(hx * 0.3, r), Vector2(hx * 0.82, r * 0.99)], N, side, Sw.TYRE, TREAD_RECT, 11)
	m.revolve([Vector2(hx * 0.82, r * 0.99), Vector2(hx * 0.95, r * 0.95), Vector2(hx + 0.007, r * 0.86), Vector2(hx + 0.004, r * 0.76),
		Vector2(hx - 0.012, rr)], N, side, Sw.TYRE, WALL_RECT, 10)
	# The rim's lip over the bead, and its barrel inside (dark, where the spokes show it).
	m.revolve([Vector2(hx - 0.012, rr), Vector2(face + 0.012, rr * 1.025), Vector2(face + 0.016, rr * 0.985), Vector2(face + 0.006, rr * 0.95)], N, side, Sw.ALLOY)
	m.revolve([Vector2(face + 0.006, rr * 0.95), Vector2(face - 0.02, rr * 0.93), Vector2(-hx * 0.8, rr * 0.93)], N, side, Sw.DARK)
	# The back of the wheel, dark.
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		m.env = 0.0
		m.tri([Vector3(-hx * 0.8 * side, 0, 0), _rev(Vector2(-hx * 0.8, rr * 0.93), a0, side), _rev(Vector2(-hx * 0.8, rr * 0.93), a1, side)],
			[_sw(Sw.TRIM)], Vector3(side, 0, 0))
	if p.rim == "spoke":
		_spokes(m, rr, face, side, int(p.spokes))
	else:
		# The steel wheel's or hub cap's face, the skin's picture, its holes cut out.
		m.env = 0.6
		var dish := face - 0.006
		for i in N:
			var a0 := TAU * i / N
			var a1 := TAU * (i + 1) / N
			m.tri([Vector3(dish * side, 0, 0), _rev(Vector2(dish, rr * 0.95), a0, side), _rev(Vector2(dish, rr * 0.95), a1, side)],
				[_patch(RIM_RECT, 0.5, 0.5), _rim_uv(a0, 0.95), _rim_uv(a1, 0.95)], Vector3(side, 0, 0))
	var brake := _Mesh.new()
	var disc_x := face - 0.07
	brake.tube(Vector3((disc_x - 0.013) * side, 0, 0), Vector3((disc_x + 0.013) * side, 0, 0), rr * 0.8, rr * 0.8, 28, Sw.CHROME)
	brake.tube(Vector3((disc_x + 0.013) * side, 0, 0), Vector3((disc_x + 0.03) * side, 0, 0), rr * 0.32, rr * 0.3, 14, Sw.DARK)
	# The calliper over the disc's trailing top.
	var cal := Vector3((disc_x + 0.006) * side, rr * 0.64 * cos(0.6), -rr * 0.64 * sin(0.6))
	var cal_red: bool = p.rim == "spoke"
	brake.box(Transform3D(Basis(Vector3.RIGHT, 0.6), cal), Vector3(0.032, rr * 0.2, 0.055), Sw.RED if cal_red else Sw.DARK)
	return [m.commit(), brake.commit()]


## An alloy's spokes, `count` of them (two by two from 10 on), from the hub out to the lip,
## dished (the hub sunk in), their faces polished; the hub, its centre cap and nuts.
static func _spokes(m: _Mesh, rr: float, face: float, side: float, count: int) -> void:
	var pairs := count >= 10
	var arms := count / 2 if pairs else count
	const K := 6
	for i in arms:
		var base_a := TAU * i / arms
		for twin in ([-1.0, 1.0] if pairs else [0.0]):
			var a: float = base_a + twin * 0.13
			var dirv := Vector3(0, cos(a), sin(a))
			var tng := Vector3(0, -sin(a), cos(a))
			var ring := []
			for k in K + 1:
				var t := float(k) / K
				var rad := lerpf(rr * 0.27, rr * 0.95, t)
				var x := lerpf(face - 0.03, face + 0.004, sqrt(t))
				var w := lerpf(rr * (0.26 if not pairs else 0.12), rr * (0.13 if not pairs else 0.07), t) * (5.0 / maxf(arms, 5.0)) ** 0.4
				var depth := 0.028
				var c := dirv * rad + Vector3(x * side, 0, 0)
				ring.append([c + tng * w * 0.5, c - tng * w * 0.5, c - tng * w * 0.4 - Vector3(depth * side, 0, 0), c + tng * w * 0.4 - Vector3(depth * side, 0, 0)])
			for k in K:
				var r0: Array = ring[k]
				var r1: Array = ring[k + 1]
				m.group = 150
				m.env = ENV[Sw.ALLOY]
				# Face, then the two sides.
				m.quad(r0[0], r1[0], r1[1], r0[1], Vector3(side, 0, 0), [_sw(Sw.ALLOY)])
				m.group = -1
				m.env = 0.6
				m.quad(r0[0], r1[0], r1[3], r0[3], tng, [_sw(Sw.ALLOY)])
				m.quad(r0[1], r1[1], r1[2], r0[2], -tng, [_sw(Sw.ALLOY)])
	# The hub: a dished disc the spokes stand on, the centre cap (the badge) and the nuts.
	m.revolve([Vector2(face - 0.035, rr * 0.3), Vector2(face - 0.026, rr * 0.29), Vector2(face - 0.022, rr * 0.2), Vector2(face - 0.02, 0.0)], 24, side, Sw.ALLOY)
	m.env = 0.9
	var cap_x := face - 0.012
	for i in 24:
		var a0 := TAU * i / 24
		var a1 := TAU * (i + 1) / 24
		m.tri([Vector3(cap_x * side, 0, 0), _rev(Vector2(cap_x, rr * 0.13), a0, side), _rev(Vector2(cap_x, rr * 0.13), a1, side)],
			[_patch(BADGE_RECT, 0.5, 0.5), _patch(BADGE_RECT, 0.5 + 0.5 * sin(a0), 0.5 - 0.5 * cos(a0)), _patch(BADGE_RECT, 0.5 + 0.5 * sin(a1), 0.5 - 0.5 * cos(a1))],
			Vector3(side, 0, 0))
	m.tube(Vector3((face - 0.02) * side, 0, 0), Vector3(cap_x * side, 0, 0), rr * 0.14, rr * 0.13, 16, Sw.ALLOY, false)
	for i in 5:
		var a := TAU * i / 5 + 0.3
		var at := Vector3(0, cos(a), sin(a)) * rr * 0.21
		m.tube(at + Vector3((face - 0.022) * side, 0, 0), at + Vector3((face - 0.01) * side, 0, 0), 0.009, 0.008, 6, Sw.CHROME)


static func _rev(q: Vector2, a: float, side: float) -> Vector3:
	return Vector3(q.x * side, q.y * cos(a), q.y * sin(a))


static func _rim_uv(a: float, s := 1.0) -> Vector2:
	return _patch(RIM_RECT, 0.5 + 0.5 * s * sin(a), 0.5 - 0.5 * s * cos(a))


# ------------------------------------------------------------------ skin

## The skin as it's painted: RGBA bytes, with shapes drawn antialiased by their distance
## fields (negative inside).
class _Canvas:
	var px := PackedByteArray()

	func _init(fill: Color) -> void:
		var img := Image.create(SKIN, SKIN, false, Image.FORMAT_RGBA8)
		img.fill(fill)
		px = img.get_data()

	func set_px(x: int, y: int, c: Color) -> void:
		var o := (y * SKIN + x) * 4
		px[o] = clampi(c.r8, 0, 255)
		px[o + 1] = clampi(c.g8, 0, 255)
		px[o + 2] = clampi(c.b8, 0, 255)
		px[o + 3] = clampi(c.a8, 0, 255)

	func get_px(x: int, y: int) -> Color:
		var o := (y * SKIN + x) * 4
		return Color8(px[o], px[o + 1], px[o + 2], px[o + 3])

	## `c` over the texel, `k` of it (its alpha replacing the texel's as far).
	func blend(x: int, y: int, c: Color, k: float) -> void:
		if k <= 0.0:
			return
		var o := (y * SKIN + x) * 4
		k = minf(k, 1.0)
		px[o] = roundi(lerpf(px[o], c.r8, k))
		px[o + 1] = roundi(lerpf(px[o + 1], c.g8, k))
		px[o + 2] = roundi(lerpf(px[o + 2], c.b8, k))
		px[o + 3] = roundi(lerpf(px[o + 3], c.a8, k))

	func fill(r: Rect2i, c: Color) -> void:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				set_px(x, y, c)

	## A rounded rectangle (in texels, within `clip`), `c` inside; the edge antialiased.
	func rbox(clip: Rect2i, ctr: Vector2, half: Vector2, rad: float, c: Color) -> void:
		var lo := Vector2i((ctr - half - Vector2.ONE * 2).floor()).max(clip.position)
		var hi := Vector2i((ctr + half + Vector2.ONE * 2).ceil()).min(clip.end)
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				var q := (Vector2(x + 0.5, y + 0.5) - ctr).abs() - half + Vector2.ONE * rad
				var dist := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - rad
				blend(x, y, c, 0.5 - dist)

	func disc(clip: Rect2i, ctr: Vector2, rad: float, c: Color) -> void:
		rbox(clip, ctr, Vector2(rad, rad), rad, c)

	## A ring: between radii `r0` and `r1`.
	func ring(clip: Rect2i, ctr: Vector2, r0: float, r1: float, c: Color) -> void:
		var lo := Vector2i((ctr - Vector2.ONE * (r1 + 2)).floor()).max(clip.position)
		var hi := Vector2i((ctr + Vector2.ONE * (r1 + 2)).ceil()).min(clip.end)
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(ctr)
				blend(x, y, c, minf(0.5 - (r0 - dd), 0.5 - (dd - r1)))

	## Every texel of `r` through `f(x, y, colour) -> colour` (x, y within the rect).
	func each(r: Rect2i, f: Callable) -> void:
		for y in r.size.y:
			for x in r.size.x:
				set_px(r.position.x + x, r.position.y + y, f.call(x, y, get_px(r.position.x + x, r.position.y + y)))

	func image() -> Image:
		return Image.create_from_data(SKIN, SKIN, false, Image.FORMAT_RGBA8, px)


## The parts of the skin every preset shares (painted once): the swatches, grille, intake,
## dials, seats, cam covers, marker, diffuser, tread and walls.
static var _common_skin := PackedByteArray()


static func _skin(p: Dictionary, d: Dictionary) -> ImageTexture:
	var cv := _Canvas.new(Color8(30, 30, 32))
	if _common_skin.is_empty():
		_paint_common(cv)
		_common_skin = cv.px
	else:
		cv.px = _common_skin.duplicate()
	_paint_head(cv, p)
	_paint_tail(cv, p)
	_paint_own(cv, p)
	if p.rim != "spoke":
		_paint_rim(cv, p)
	_paint_body(cv, p, d)
	var img := cv.image()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _paint_common(cv: _Canvas) -> void:
	var swatches := [Color8(128, 128, 128, PAINT_A), Color8(14, 18, 24), Color8(24, 24, 26), Color8(190, 193, 198),
		Color8(150, 14, 12), Color8(230, 232, 236), Color8(30, 30, 32), Color8(220, 120, 20), Color8(20, 50, 200),
		Color8(228, 228, 224), Color8(128, 128, 128, CABIN_A), Color8(44, 45, 48), Color8(70, 70, 70, CABIN_A),
		Color8(38, 44, 62), Color8(150, 155, 165), Color8(10, 10, 14), Color8(14, 14, 16), Color8(176, 178, 182)]
	for i in swatches.size():
		cv.fill(Rect2i(i * SWATCH, 0, SWATCH, SWATCH), swatches[i])
	_paint_grille(cv)
	_paint_intake(cv, INTAKE_RECT)
	_paint_dials(cv)
	_paint_misc(cv)


## The headlamp: a dark housing under clear glass, its reflectors and projector lenses, a
## daytime running strip, the amber indicator at its outboard (right-hand) end.
static func _paint_head(cv: _Canvas, p: Dictionary) -> void:
	var r := HEAD_RECT
	var o := Vector2(r.position)
	var style: String = p.heads
	# The housing behind the glass: brushed silver, darker toward its edges.
	cv.each(r, func(x: int, y: int, _c: Color) -> Color:
		var e := minf(minf(x, r.size.x - 1 - x) / 40.0, minf(y, r.size.y - 1 - y) / 30.0)
		var g := int(lerpf(70.0, 168.0, clampf(e, 0.0, 1.0)) + 14.0 * sin(y * 0.9))
		return Color8(g, g + 2, g + 6))
	# Its rim, a dark seal round the glass.
	cv.each(r, func(x: int, y: int, c: Color) -> Color:
		return Color8(26, 27, 30) if x < 4 or y < 4 or x > r.size.x - 5 or y > r.size.y - 5 else c)
	# The indicator: amber behind facets, at the outboard end.
	cv.rbox(r, o + Vector2(226, 64), Vector2(24, 54), 10.0, Color8(210, 118, 24))
	for k in 7:
		cv.rbox(r, o + Vector2(226, 18 + k * 15), Vector2(20, 2), 1.0, Color8(236, 150, 50))
	if style == "face":
		# An older lamp: the reflector behind ribbed glass, the high beam's round in it.
		cv.rbox(r, o + Vector2(98, 64), Vector2(92, 52), 6.0, Color8(204, 208, 216))
		for gy in range(16, 114, 6):
			cv.rbox(r, o + Vector2(98, gy), Vector2(90, 0.8), 0.4, Color8(170, 176, 188))
		for gx in range(10, 190, 9):
			cv.rbox(r, o + Vector2(gx, 64), Vector2(0.6, 50), 0.3, Color8(182, 186, 196))
		cv.disc(r, o + Vector2(152, 64), 26.0, Color8(176, 180, 190))
		cv.disc(r, o + Vector2(152, 64), 18.0, Color8(236, 238, 244))
	else:
		# A reflector bowl for the low beam with its projector lens, a smaller one for the
		# high beam, the running-light strip along the bottom.
		for spot in [[70.0, 60.0, 40.0], [156.0, 60.0, 30.0]]:
			var c := o + Vector2(spot[0], spot[1])
			var rad: float = spot[2]
			cv.each(Rect2i(Vector2i(c - Vector2.ONE * rad), Vector2i.ONE * int(rad * 2.0 + 1.0)), func(x: int, y: int, col: Color) -> Color:
				var dd := Vector2(x - rad, y - rad).length() / rad
				if dd > 1.0:
					return col
				var g := int(lerpf(235.0, 150.0, dd) - 20.0 * absf(sin(atan2(y - rad, x - rad) * 3.0)) * dd)
				return Color8(g, g + 2, g + 8))
			cv.ring(r, c, rad * 0.42, rad * 0.5, Color8(110, 112, 120))
			cv.disc(r, c, rad * 0.42, Color8(60, 66, 80))
			cv.disc(r, c, rad * 0.3, Color8(200, 210, 228))
			cv.disc(r, c + Vector2(-rad * 0.12, -rad * 0.14), rad * 0.1, Color8(255, 255, 255))
		cv.rbox(r, o + Vector2(110, 113), Vector2(96, 3.5), 3.5, Color8(248, 250, 255))
	# The glass's sheen across the top.
	cv.each(Rect2i(r.position + Vector2i(6, 6), Vector2i(r.size.x - 12, 22)), func(_x: int, y: int, c: Color) -> Color:
		return c.lerp(Color8(255, 255, 255, c.a8), 0.18 * (1.0 - y / 22.0)))


## The tail lamp: its housing, the red stop/tail lamp (round pairs, ribbed bands or louvres),
## the amber indicator at its right-hand end (outboard once cast), the reversing lamp at
## its left. The bar across the tail has an indicator at both ends and the reversing lamps
## in the middle.
static func _paint_tail(cv: _Canvas, p: Dictionary) -> void:
	var r := TAIL_RECT
	var o := Vector2(r.position)
	var style: String = p.tails
	cv.fill(r, Color8(60, 8, 8))
	cv.rbox(r, o + Vector2(128, 64), Vector2(126, 62), 16.0, Color8(26, 22, 22))
	match style:
		"round":
			cv.rbox(r, o + Vector2(128, 64), Vector2(122, 56), 14.0, Color8(90, 10, 10))
			for cx in [96.0, 160.0]:
				cv.disc(r, o + Vector2(cx, 64), 30.0, Color8(150, 16, 14))
				cv.ring(r, o + Vector2(cx, 64), 22.0, 28.0, Color8(215, 30, 24))
				cv.disc(r, o + Vector2(cx, 64), 12.0, Color8(240, 60, 48))
			cv.disc(r, o + Vector2(36, 64), 22.0, Color8(226, 226, 222))
			cv.disc(r, o + Vector2(220, 64), 22.0, Color8(232, 132, 26))
		"bar":
			cv.rbox(r, o + Vector2(128, 64), Vector2(122, 50), 10.0, Color8(130, 12, 10))
			for gx in range(16, 240, 8):
				cv.rbox(r, o + Vector2(gx, 64), Vector2(1.5, 48), 0.5, Color8(70, 8, 8))
			for cx in [34.0, 222.0]:
				cv.disc(r, o + Vector2(cx, 64), 26.0, Color8(232, 132, 26))
			for cx in [74.0, 182.0]:
				cv.disc(r, o + Vector2(cx, 64), 28.0, Color8(215, 28, 22))
				cv.disc(r, o + Vector2(cx, 64), 12.0, Color8(245, 70, 56))
			cv.rbox(r, o + Vector2(128, 64), Vector2(20, 20), 6.0, Color8(226, 226, 222))
		_:
			cv.rbox(r, o + Vector2(42, 64), Vector2(34, 52), 8.0, Color8(226, 226, 222))
			cv.rbox(r, o + Vector2(136, 64), Vector2(54, 52), 8.0, Color8(150, 14, 12))
			for gy in range(18, 112, 9):
				cv.rbox(r, o + Vector2(136, gy), Vector2(52, 2.0), 1.0, Color8(215, 30, 24))
			cv.rbox(r, o + Vector2(136, 64), Vector2(46, 8), 4.0, Color8(240, 64, 50))
			cv.rbox(r, o + Vector2(222, 64), Vector2(28, 52), 8.0, Color8(232, 132, 26))
	cv.each(Rect2i(r.position + Vector2i(6, 6), Vector2i(r.size.x - 12, 14)), func(_x: int, y: int, c: Color) -> Color:
		return c.lerp(Color8(255, 255, 255, c.a8), 0.1 * (1.0 - y / 14.0)))


## The grille: chrome surround, horizontal bars.
static func _paint_grille(cv: _Canvas) -> void:
	var r := GRILLE_RECT
	var o := Vector2(r.position)
	cv.fill(r, Color8(10, 10, 12))
	cv.rbox(r, o + Vector2(128, 64), Vector2(126, 62), 16.0, Color8(196, 198, 204))
	cv.rbox(r, o + Vector2(128, 64), Vector2(118, 54), 12.0, Color8(12, 12, 14))
	for gy in range(22, 110, 14):
		cv.rbox(r, o + Vector2(128, gy), Vector2(112, 3.0), 1.5, Color8(176, 178, 184))
	cv.disc(r, o + Vector2(128, 64), 16.0, Color8(210, 212, 218))
	cv.disc(r, o + Vector2(128, 64), 11.0, Color8(30, 60, 120))


## An intake: a dark surround round black honeycomb mesh.
static func _paint_intake(cv: _Canvas, r: Rect2i) -> void:
	cv.fill(r, Color8(16, 16, 18))
	cv.each(r, func(x: int, y: int, _c: Color) -> Color:
		if x < 6 or y < 6 or x >= r.size.x - 6 or y >= r.size.y - 6:
			return Color8(36, 36, 40)
		# Hexagonal cells: dark holes in a lighter web.
		var q := Vector2(x / 9.0, y / 9.0 * 1.1547)
		var row := floori(q.y)
		var qx := q.x + (0.5 if row % 2 == 1 else 0.0)
		var dx := absf(fposmod(qx, 1.0) - 0.5)
		var dy := absf(fposmod(q.y, 1.0) - 0.5)
		return Color8(4, 4, 5) if dx < 0.36 and dy < 0.38 else Color8(42, 42, 46))


static func _paint_dials(cv: _Canvas) -> void:
	var r := DIAL_RECT
	cv.each(r, func(x: int, y: int, _c: Color) -> Color:
		var cx := 64 if x < 128 else 192
		var dv := Vector2(x - cx, y - 64)
		var dd := dv.length()
		if dd > 61.0:
			return Color8(30, 30, 32)
		if dd > 57.0:
			return Color8(160, 162, 168)
		# Ticks round three quarters of the face, from the bottom left over the top.
		var a := fposmod(atan2(dv.x, -dv.y) + PI * 0.75 + PI, TAU) - PI
		if dd > 43.0 and absf(a) < PI * 0.75 and fposmod(a * 12.0 / PI, 1.0) < 0.2:
			return Color8(235, 235, 230)
		if dd > 49.0 and a > PI * 0.5 and a < PI * 0.75 and x >= 128:
			return Color8(200, 30, 20)   # the red line
		return Color8(12, 12, 14))


## The seats' leather, the cam covers, the side marker, the diffuser, the tyre's tread and walls.
static func _paint_misc(cv: _Canvas) -> void:
	cv.each(SEAT_RECT, func(x: int, y: int, _c: Color) -> Color:
		# Pleats: stitched lines across the leather (all at the cabin's alpha: tinted with it).
		if y % 16 == 0 or x < 3 or x > 124:
			return Color8(80, 80, 80, CABIN_A)
		return Color8(128, 128, 128, CABIN_A) if absf(x - 64) < 40 else Color8(110, 110, 110, CABIN_A))
	cv.each(CAM_RECT, func(_x: int, y: int, _c: Color) -> Color:
		return Color8(60, 8, 6) if y % 12 < 3 else Color8(170, 20, 16))
	var mo := Vector2(MARKER_RECT.position)
	cv.fill(MARKER_RECT, Color8(30, 30, 32))
	cv.rbox(MARKER_RECT, mo + Vector2(64, 32), Vector2(60, 28), 14.0, Color8(220, 116, 20))
	for gx in range(16, 120, 10):
		cv.rbox(MARKER_RECT, mo + Vector2(gx, 32), Vector2(1.5, 24), 1.0, Color8(245, 160, 60))
	cv.each(DIFF_RECT, func(x: int, y: int, _c: Color) -> Color:
		if y < 4 or y > 59:
			return Color8(14, 14, 16)
		return Color8(48, 48, 52) if x % 16 < 3 else Color8(20, 20, 22))
	# The tread: blocks between four grooves round the tyre, sipes across them; the walls
	# plain but for a rib round the rim and faint lettering.
	cv.each(TREAD_RECT, func(x: int, y: int, _c: Color) -> Color:
		var u := x / float(TREAD_RECT.size.x)
		for g in [0.2, 0.4, 0.6, 0.8]:
			if absf(u - g) < 0.022:
				return Color8(14, 14, 15)
		var lane := floori(u * 5.0)
		var v := fposmod(y / 64.0 + lane * 0.27 + u * 0.35, 1.0)
		if v < 0.08:
			return Color8(16, 16, 17)
		return Color8(36, 36, 38))
	cv.each(WALL_RECT, func(x: int, y: int, _c: Color) -> Color:
		var v := x / float(WALL_RECT.size.x)
		if v < 0.06:
			return Color8(40, 40, 42)
		if v > 0.42 and v < 0.62 and (y / 6) % 3 != 0 and hash(y / 6 + (x / 9) * 7) % 3 != 0:
			return Color8(46, 46, 48)
		return Color8(32, 32, 34))


## The skin's patches that differ by preset: the plate (its own registration), the badge.
static func _paint_own(cv: _Canvas, p: Dictionary) -> void:
	var plate := hash(p.name)
	cv.each(PLATE_RECT, func(x: int, y: int, _c: Color) -> Color:
		if x < 5 or y < 5 or x > 250 or y > 122:
			return Color8(18, 18, 20)
		if x < 9 or y < 9 or x > 246 or y > 118:
			return Color8(30, 40, 90)
		if y >= 36 and y <= 92 and x >= 24 and x <= 230 and (x - 24) % 32 < 24:
			var cell := (x - 24) / 32
			var bits := (plate >> (cell * 5)) | 0x11
			var colm := ((x - 24) % 32) / 8
			var row := (y - 36) / 19
			if (bits >> ((colm + row * 2) % 5)) & 1:
				return Color8(30, 30, 40)
		return Color8(235, 235, 225))
	var bo := Vector2(BADGE_RECT.position)
	cv.fill(BADGE_RECT, Color8(30, 30, 32))
	cv.disc(BADGE_RECT, bo + Vector2(64, 64), 62.0, Color8(205, 208, 214))
	cv.disc(BADGE_RECT, bo + Vector2(64, 64), 52.0, Color8(150, 152, 158))
	cv.disc(BADGE_RECT, bo + Vector2(64, 64), 46.0, Color8(24, 40, 96) if p.euro else Color8(120, 16, 14))
	cv.rbox(BADGE_RECT, bo + Vector2(64, 64), Vector2(30, 6), 3.0, Color8(225, 228, 232))
	cv.rbox(BADGE_RECT, bo + Vector2(64, 64), Vector2(6, 30), 3.0, Color8(225, 228, 232))


## A steel wheel's or hub cap's face (the alloys are modelled): metal, the holes cut out.
static func _paint_rim(cv: _Canvas, p: Dictionary) -> void:
	var spokes: int = p.spokes
	var style: String = p.rim
	cv.each(RIM_RECT, func(x: int, y: int, _c: Color) -> Color:
		var dv := Vector2(x - 127.5, y - 127.5) / 128.0
		var rho := dv.length()
		var th := atan2(dv.y, dv.x)
		if rho > 0.98:
			return Color8(30, 30, 32)
		var shade := 0.86 + 0.14 * cos(th + 0.8) - 0.12 * smoothstep(0.85, 0.98, rho)
		if style == "steel":
			# Painted black steel, its holes, the small chrome centre cap.
			if rho < 0.18:
				return _shaded(Color8(200, 202, 208), shade)
			var hole := Vector2.from_angle((floorf(th / TAU * spokes + 0.5)) * TAU / spokes) * 0.58
			if (dv - hole).length() < 0.1:
				return Color(0, 0, 0, 0)
			if absf(rho - 0.36) < 0.02 or absf(rho - 0.8) < 0.015:
				return Color8(28, 28, 30)
			return _shaded(Color8(48, 48, 52), shade)
		# A hub cap: silver plastic, ribs round it, slots to the brakes.
		var f := fposmod(th / TAU * spokes, 1.0)
		var off := minf(f, 1.0 - f)
		if rho > 0.5 and rho < 0.8 and off < 0.14:
			return Color(0, 0, 0, 0) if off < 0.1 else Color8(60, 60, 64)
		if absf(rho - 0.85) < 0.012 or absf(rho - 0.42) < 0.01:
			return Color8(110, 112, 118)
		return _shaded(Color8(196, 198, 204), shade))


## The body chart (BODY_RECT, see _chart()): the paint, shaded as the games' skins are (darker
## low down and round the wheel arches, under the shoulder), with the shut lines round the
## doors, lids and bumpers (car.gdshader cuts them into it), the door handles, the fuel flap
## and a cruiser's white doors.
static func _paint_body(cv: _Canvas, p: Dictionary, d: Dictionary) -> void:
	var L: float = p.len
	var w := BODY_RECT.size.x
	var h := BODY_RECT.size.y
	var sx := 2.0 * L / (w - 2)              # m per texel along the car
	var sk := (RING_POINTS - 1.0) / (h - 2)  # landmarks per texel round it
	# Lines as [z0, z1, k0, k1]: along the car (k0 == k1) or round it (z0 == z1).
	var lines: Array[Array] = []
	var dk: int = DOOR_ROWS[0]
	var tk: int = DOOR_ROWS[-1] + 1
	lines.append([d.door_f, d.door_f, dk, tk])
	lines.append([d.door_r, d.door_r, dk, tk])
	lines.append([d.door_r, d.door_f, dk, dk])
	if p.doors == 4:
		lines.append([d.rdoor_r, d.rdoor_r, dk, tk])
		lines.append([d.rdoor_r, d.door_r, dk, dk])
	for e in [[d.bonnet_r, d.bonnet_f], [d.boot_r, d.boot_f]]:
		lines.append([e[0], e[0], LID_ROWS[0], RING_POINTS - 1])
		lines.append([e[1], e[1], LID_ROWS[0], RING_POINTS - 1])
		lines.append([e[0], e[1], LID_ROWS[0], LID_ROWS[0]])
	lines.append([d.bump_f, d.bump_f, 0, BUMPER_ROWS_F + 1])
	lines.append([d.bump_f, L, BUMPER_ROWS_F + 1, BUMPER_ROWS_F + 1])
	lines.append([d.bump_r, d.bump_r, 0, BUMPER_ROWS_R + 1])
	lines.append([-L, d.bump_r, BUMPER_ROWS_R + 1, BUMPER_ROWS_R + 1])
	lines.append([d.arch_r, d.arch_f, SILL_ROW + 1, SILL_ROW + 1])
	# The fuel flap on the rear wing (both sides alike: the chart is).
	var flap_z: float = (d.arch_r + d.boot_f) * 0.5 if p.engine == "rear" else d.arch_r - 0.05
	var flap := Rect2(flap_z - 0.07, 5.2, 0.14, 0.62)
	lines.append([flap.position.x, flap.end.x, flap.position.y, flap.position.y])
	lines.append([flap.position.x, flap.end.x, flap.end.y, flap.end.y])
	lines.append([flap.position.x, flap.position.x, flap.position.y, flap.end.y])
	lines.append([flap.end.x, flap.end.x, flap.position.y, flap.end.y])
	# Texel (x, y) of the chart is at z = -L + (x - 0.5) sx, landmark k = (y - 0.5) sk (_patch).
	var near := PackedFloat32Array()
	near.resize(w * h)
	near.fill(INF)
	for ln: Array in lines:
		var x0 := clampi(int((minf(ln[0], ln[1]) + L) / sx) - 2, 0, w - 1)
		var x1 := clampi(int((maxf(ln[0], ln[1]) + L) / sx) + 4, 0, w - 1)
		var y0 := clampi(int(minf(ln[2], ln[3]) / sk) - 2, 0, h - 1)
		var y1 := clampi(int(maxf(ln[2], ln[3]) / sk) + 4, 0, h - 1)
		for ty in range(y0, y1 + 1):
			var k := (ty - 0.5) * sk
			for tx in range(x0, x1 + 1):
				var z := -L + (tx - 0.5) * sx
				var dz := maxf(maxf(ln[0] - z, z - ln[1]), 0.0) / sx
				var dkk := maxf(maxf(ln[2] - k, k - ln[3]), 0.0) / sk
				near[ty * w + tx] = minf(near[ty * w + tx], Vector2(dz, dkk).length())
	var handles: Array[Rect2] = []
	for rear_edge: float in ([d.door_r, d.rdoor_r] if p.doors == 4 else [d.door_r]):
		handles.append(Rect2(rear_edge + 0.07, 5.55, 0.15, 0.3))
	var cream_z0: float = d.rdoor_r if p.doors == 4 else d.door_r
	var twotone: bool = p.get("twotone", false)
	# The shading: each column's landmark heights, to find how far each texel is from the
	# arches and the sill.
	var wheels := [Vector2(p.wf * L, GROUND + p.r), Vector2(p.wr * L, GROUND + p.r)]
	var arch_r: float = p.r + 0.05
	var col_y := []
	for tx in w:
		var ring := _ring(p, -L + (tx - 0.5) * sx)
		var ys := PackedFloat32Array()
		for q in ring:
			ys.append(q.y)
		col_y.append(ys)
	var o := BODY_RECT.position
	var px := cv.px
	var hrects: Array[Rect2] = handles
	var wz := [wheels[0].x, wheels[1].x]
	var wy: float = wheels[0].y
	for ty in h:
		var k := clampf((ty - 0.5) * sk, 0.0, RING_POINTS - 1.0)
		var kj := mini(int(k), RING_POINTS - 2)
		var kf := k - kj
		# Low down darker, under the shoulder a touch darker, the top lighter.
		var shade_k := lerpf(0.78, 1.0, smoothstep(2.6, 5.0, k)) * (1.0 - 0.06 * smoothstep(5.2, 5.9, k) * (1.0 - smoothstep(5.9, 6.3, k))) \
			* lerpf(1.0, 1.06, smoothstep(7.0, 9.0, k))
		var low := k < 7.0
		var cream_row := twotone and k >= dk and k <= tk
		var handle_row := false
		for hr in hrects:
			if k >= hr.position.y and k <= hr.end.y:
				handle_row = true
		var row_o := ((o.y + ty) * SKIN + o.x) * 4
		for tx in w:
			var z := -L + (tx - 0.5) * sx
			var ao := shade_k
			if low:
				var ys: PackedFloat32Array = col_y[tx]
				var y := ys[kj] + (ys[kj + 1] - ys[kj]) * kf
				for zw: float in wz:
					var dz := z - zw
					if absf(dz) < arch_r + 0.16:
						var dd := sqrt(dz * dz + (y - wy) * (y - wy)) - arch_r
						if dd > -0.02 and dd < 0.14:
							ao *= lerpf(0.72, 1.0, smoothstep(-0.02, 0.14, dd))
			var cr := 128.0
			var cg := 128.0
			var cb := 128.0
			var ca := PAINT_A
			if cream_row and z < d.door_f and z > cream_z0:
				cr = 228.0
				cg = 228.0
				cb = 224.0
				ca = 255
			if handle_row:
				for hr in hrects:
					if hr.has_point(Vector2(z, k)):
						if k < 5.68:
							cr = 50.0
							cg = 50.0
							cb = 52.0
						else:
							cr = 196.0
							cg = 198.0
							cb = 202.0
							ca = 255
			var nl := near[ty * w + tx]
			var shade := ao * (1.0 if nl > 1.4 else lerpf(0.3, 1.0, clampf(nl - 0.4, 0.0, 1.0)))
			var at := row_o + tx * 4
			px[at] = int(cr * shade)
			px[at + 1] = int(cg * shade)
			px[at + 2] = int(cb * shade)
			px[at + 3] = ca
	cv.px = px


static func _shaded(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

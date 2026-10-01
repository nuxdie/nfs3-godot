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
## whose lenses light, tail pipes and a plate. The skin is painted here, panel shut lines and
## door handles and all, for the same paint/glass/rubber shader (car.gdshader) as the games'
## cars, which reads its vertices' finish as Porsche Unleashed's (COLOR: r how much it
## mirrors, g a lamp's lens, b 0).

const GROUND := -0.6   # the road below the car's origin at rest

# Body lines in metres, heights above the road. Positions along the car are fractions
# of its half length `len` (front +1): ws0/ws1 windshield base/top, rw1/rw0 rear window
# top/base, bpil the B pillar (none outside -1..1), cpil where the side glass ends,
# wf/wr the axles. rc rounds the corners in plan, re the ends in side view.
# Besides: "engine" front or rear (which bay it fills; the other carries luggage), "doors"
# 2 or 4 (the rear ones don't open), "hatch" (the boot lid takes the rear window with it),
# "heads" corner (set into the wings), face (in the nose) or popup, "tails" round or strip,
# "spoiler" 0 none, 1 a lip, 2 a wing on posts, 3 one that rises at speed, "pipes" how many
# tail pipes, "fog" lamps in the front bumper, "euro" the plate, "interior" the cabin's
# colour, "paints" the other colours it comes in (the menu's).
const PRESETS := [
	{"name": "Stinger GT", "color": Color(0.85, 0.1, 0.08), "mass": 1400.0, "top": 80.0, "torque": 520.0,
		"len": 2.25, "wid": 0.95, "roof": 1.27, "nose": 0.56, "hood": 0.84, "deck": 0.92, "tail": 0.86, "crown": 0.05,
		"ws0": 0.2, "ws1": -0.08, "rw1": -0.4, "rw0": -0.66, "bpil": 2.0, "cpil": -0.42, "tumble": 0.76,
		"clear": 0.15, "r": 0.33, "wf": 0.64, "wr": -0.6, "rc": 0.34, "re": 0.24,
		"heads": "corner", "tails": "round", "rim": "spoke", "spokes": 5, "spoiler": 3,
		"engine": "rear", "doors": 2, "pipes": 2, "euro": true, "interior": Color(0.45, 0.32, 0.2),
		"paints": [Color(0.1, 0.1, 0.12), Color(0.8, 0.8, 0.78), Color(0.95, 0.75, 0.1), Color(0.1, 0.25, 0.55)]},
	{"name": "Vortex V12", "color": Color(0.95, 0.75, 0.1), "mass": 1550.0, "top": 90.0, "torque": 600.0,
		"len": 2.25, "wid": 1.0, "roof": 1.12, "nose": 0.5, "hood": 0.72, "deck": 0.96, "tail": 0.92, "crown": 0.03,
		"ws0": 0.42, "ws1": 0.02, "rw1": -0.22, "rw0": -0.7, "bpil": 2.0, "cpil": -0.25, "tumble": 0.72,
		"clear": 0.13, "r": 0.34, "wf": 0.62, "wr": -0.6, "rc": 0.38, "re": 0.2,
		"heads": "corner", "tails": "strip", "rim": "spoke", "spokes": 10, "spoiler": 2,
		"engine": "rear", "doors": 2, "pipes": 4, "euro": true, "interior": Color(0.12, 0.12, 0.13),
		"paints": [Color(0.85, 0.1, 0.08), Color(0.08, 0.08, 0.1), Color(0.9, 0.9, 0.88), Color(0.3, 0.6, 0.2)]},
	{"name": "Aero RS", "color": Color(0.1, 0.35, 0.9), "mass": 1250.0, "top": 76.0, "torque": 430.0,
		"len": 2.1, "wid": 0.9, "roof": 1.28, "nose": 0.55, "hood": 0.74, "deck": 0.78, "tail": 0.76, "crown": 0.06,
		"ws0": 0.28, "ws1": 0.0, "rw1": -0.25, "rw0": -0.9, "bpil": 2.0, "cpil": -0.5, "tumble": 0.74,
		"clear": 0.14, "r": 0.32, "wf": 0.66, "wr": -0.62, "rc": 0.4, "re": 0.28,
		"heads": "popup", "tails": "strip", "rim": "spoke", "spokes": 6, "spoiler": 1, "hatch": true,
		"engine": "front", "doors": 2, "pipes": 1, "euro": false, "interior": Color(0.2, 0.2, 0.24),
		"paints": [Color(0.9, 0.9, 0.9), Color(0.75, 0.05, 0.05), Color(0.1, 0.1, 0.1), Color(0.55, 0.55, 0.58)]},
	{"name": "Interceptor", "color": Color(0.08, 0.08, 0.1), "mass": 1700.0, "top": 82.0, "torque": 560.0,
		"len": 2.5, "wid": 0.98, "roof": 1.45, "nose": 0.78, "hood": 0.95, "deck": 1.0, "tail": 0.96, "crown": 0.04,
		"ws0": 0.3, "ws1": 0.06, "rw1": -0.3, "rw0": -0.5, "bpil": -0.12, "cpil": -0.42, "tumble": 0.8,
		"clear": 0.17, "r": 0.33, "wf": 0.64, "wr": -0.6, "rc": 0.22, "re": 0.14,
		"heads": "face", "tails": "strip", "rim": "steel", "spokes": 8, "spoiler": 0,
		"engine": "front", "doors": 4, "pipes": 2, "fog": true, "euro": false, "interior": Color(0.16, 0.16, 0.17),
		"lightbar": true, "twotone": true, "paints": []},
	{"name": "Sedan", "color": Color(0.6, 0.62, 0.55), "mass": 1500.0, "top": 50.0, "torque": 300.0,
		"len": 2.3, "wid": 0.92, "roof": 1.44, "nose": 0.76, "hood": 0.92, "deck": 0.98, "tail": 0.94, "crown": 0.04,
		"ws0": 0.3, "ws1": 0.06, "rw1": -0.32, "rw0": -0.52, "bpil": -0.12, "cpil": -0.44, "tumble": 0.8,
		"clear": 0.16, "r": 0.31, "wf": 0.64, "wr": -0.6, "rc": 0.22, "re": 0.14,
		"heads": "face", "tails": "strip", "rim": "hubcap", "spokes": 12, "spoiler": 0,
		"engine": "front", "doors": 4, "pipes": 1, "euro": true, "interior": Color(0.35, 0.3, 0.25),
		"paints": [Color(0.15, 0.2, 0.35), Color(0.45, 0.1, 0.1), Color(0.85, 0.85, 0.8), Color(0.25, 0.3, 0.22)]},
]

# The skin: flat swatches along the top row (the paint at Porsche Unleashed's paint alpha,
# the cabin's at its interior alpha), patterned patches below them, and the body's own
# chart (BODY_RECT: along the car across, round the ring down), where the shut lines are.
enum Sw { PAINT, GLASS, TRIM, CHROME, RED, WHITE, TYRE, AMBER, BLUE, CREAM, CABIN, DARK, CARPET, SUIT, MIRROR, VISOR }
## How much each swatch mirrors the surroundings (COLOR.r, car.gdshader): 0 matte, 0.5
## gloss, 1 chrome.
const ENV := [0.5, 0.5, 0.05, 1.0, 0.5, 0.5, 0.0, 0.5, 0.5, 0.5, 0.0, 0.1, 0.0, 0.0, 1.0, 0.5]
const SKIN := 512
const SWATCH := 32
const PAINT_A := 117   # Nfs5Car's paint alpha
const CABIN_A := 224   # ... and its cabin's (Nfs5Car.CABIN_ALPHA)
const HEAD_RECT := Rect2i(0, 32, 128, 64)
const TAIL_RECT := Rect2i(128, 32, 128, 64)
const GRILLE_RECT := Rect2i(256, 32, 128, 64)
const DIAL_RECT := Rect2i(384, 32, 128, 64)
const SEAT_RECT := Rect2i(0, 96, 128, 64)
const PLATE_RECT := Rect2i(128, 96, 128, 64)
const CAM_RECT := Rect2i(256, 96, 128, 64)
const RIM_RECT := Rect2i(0, 160, 128, 128)
const BODY_RECT := Rect2i(0, 288, 512, 224)
const RING_POINTS := 12
const TYRE_W := 0.24
## The rows of the ring each piece takes (strip j runs from ring point j to j + 1): the
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


static func make(preset: int, tint := Color(0, 0, 0, 0)) -> ProceduralCar:
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
	if p.spoiler == 3:
		c.carp[47] = PackedFloat32Array([1.0])
		c.carp[48] = PackedFloat32Array([SPOILER_SPEED])
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


## Underside: level between the axles, lifting under the overhangs.
static func _bottom(p: Dictionary, u: float) -> float:
	var b: float = p.clear
	if u > p.wf:
		b += (u - p.wf) / (1.0 - p.wf) * 0.12
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


## The body's cross-section at `z`, the +X half from the middle of the floor round to the
## middle of the roof (or hood). Points: 0 floor, 1-2 wheel-well liner, 3 sill, 4-5 flank,
## 6 shoulder, 7 window sill, 8 window top, 9 roof rail, 10-11 roof (or hood, or glass).
static func _ring(p: Dictionary, z: float) -> PackedVector3Array:
	var L: float = p.len
	var u := z / L
	var c := _cabin(p, u)
	var rc: float = p.rc
	var hw: float = p.wid
	var dz := absf(z) - (L - rc)
	if dz > 0.0:
		hw -= rc - sqrt(maxf(rc * rc - dz * dz, 0.0))
	hw *= 1.0 - 0.05 * maxf(u, 0.0) * maxf(u, 0.0)
	var bot := _bottom(p, u)
	var belt := _belt(p, u)
	var roof: float = p.roof
	var crown: float = p.crown
	var rail: float = hw * p.tumble - 0.08
	var pts: Array[Vector2] = [
		Vector2(0.0, bot), Vector2(hw - 0.34, bot), Vector2(hw - 0.3, bot + 0.02), Vector2(hw - 0.05, bot + 0.05),
		Vector2(hw, bot + 0.25 * (belt - bot)), Vector2(hw - 0.01, belt - 0.1), Vector2(hw - 0.07, belt),
		Vector2(hw * 0.9, belt + 0.01).lerp(Vector2(hw - 0.13, belt + 0.03), c),
		Vector2(hw * 0.84, belt + crown * 0.3).lerp(Vector2(hw * p.tumble, roof - 0.09), c),
		Vector2(hw * 0.76, belt + crown * 0.5).lerp(Vector2(rail, roof - 0.02), c),
		Vector2(hw * 0.38, belt + crown * 0.9).lerp(Vector2(rail * 0.5, roof - 0.004), c),
		Vector2(0.0, belt + crown).lerp(Vector2(0.0, roof), c),
	]
	# Wheel arches: the well is cut up into the flank, and the wings swell over the tyres.
	var a := _arch(p, z)
	if a > -INF:
		for k in [2, 3, 4]:
			pts[k].y = maxf(pts[k].y, a)
		pts[5].y = maxf(pts[5].y, a + 0.04)
		pts[6].y = maxf(pts[6].y, a + 0.07)
		# The hood's edges hump over the wells too, or the wells would show through a low hood.
		for k in [7, 8, 9]:
			pts[k].y = maxf(pts[k].y, a + 0.07 - 0.02 * (k - 7))
		pts[7].y = maxf(pts[7].y, lerpf(pts[7].y, pts[6].y + 0.02, c))
	# Round the ends off in side view.
	var re: float = p.re
	var ez := absf(z) - (L - re)
	if ez > 0.0:
		var k := 0.72 + 0.28 * sqrt(maxf(1.0 - (ez / re) * (ez / re), 0.0))
		var mid := (bot + belt) * 0.5
		for i in pts.size():
			pts[i].y = mid + (pts[i].y - mid) * k
	var out := PackedVector3Array()
	for q in pts:
		out.append(Vector3(q.x, GROUND + q.y, z))
	return out


## A point on the body surface at `z`, `s` of the way round the ring (point index + fraction).
static func _surf(p: Dictionary, z: float, s: float) -> Vector3:
	var r := _ring(p, z)
	var j := clampi(int(s), 0, r.size() - 2)
	return r[j].lerp(r[j + 1], s - j)


## The top of the body (the roof, hood or deck's middle) at `z`.
static func _top(p: Dictionary, z: float) -> float:
	return _ring(p, z)[RING_POINTS - 1].y


## What a strip of the shell between two ring points `j`, `j + 1` is made of at `u`.
static func _material(p: Dictionary, j: int, u: float) -> int:
	if j <= 2:
		return Sw.TRIM
	var c := _cabin(p, u)
	if j == 7 and c > 0.001 and u > p.cpil:
		return Sw.TRIM if absf(u - p.bpil) < 0.03 else Sw.GLASS
	if j >= 9 and c > 0.001 and c < 0.999:
		return Sw.GLASS
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
	d.bonnet_f = L - 0.14
	d.boot_f = p.rw1 * L - 0.03 if p.get("hatch", false) else p.rw0 * L - 0.05
	d.boot_r = -L + 0.12
	d.bump_f = L - 0.3
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


static func _mx(v: Vector3, side: float) -> Vector3:
	return Vector3(v.x * side, v.y, v.z)


static func _sw(i: int) -> Vector2:
	return Vector2(i * SWATCH + SWATCH * 0.5, SWATCH * 0.5) / SKIN


## UV at (`a`, `b`) across a skin patch (0..1 each, b down the picture), a texel in from its edge.
static func _patch(rect: Rect2i, a: float, b: float) -> Vector2:
	return (Vector2(rect.position) + Vector2(1, 1) + Vector2(a, b) * (Vector2(rect.size) - Vector2(2, 2))) / SKIN


## The body chart's UV for ring point `k` at `z`.
static func _chart(p: Dictionary, z: float, k: float) -> Vector2:
	return _patch(BODY_RECT, (z + p.len) / (2.0 * p.len), k / (RING_POINTS - 1.0))


static func _piece(parts: Dictionary, key: String) -> _Mesh:
	if not parts.has(key):
		parts[key] = _Mesh.new()
	return parts[key]


## Ring point `v` (index `k`) moved into the car by `by` m: the flank in, the roof down.
static func _inset(v: Vector3, k: int, by: float) -> Vector3:
	if k >= 9:
		return Vector3(v.x * (1.0 - by * 1.5), v.y - by, v.z)
	return Vector3(maxf(absf(v.x) - by, 0.0) * signf(v.x), v.y, v.z)


# ------------------------------------------------------------------ building

static func _build(p: Dictionary) -> Dictionary:
	var L: float = p.len
	var W: float = p.wid
	var r: float = p.r
	var d := _layout(p)
	var parts := {}   # piece name -> _Mesh

	# Stations along the car: close together round the ends, and on every body line and edge.
	var zs: Array[float] = []
	var z := -L
	while z < L:
		zs.append(z)
		z += 0.035 if absf(z) > L - maxf(p.rc, p.re) - 0.05 else 0.08
	zs.append(L)
	for u: float in [p.ws0, p.ws1, p.rw1, p.rw0, p.cpil, p.bpil - 0.03, p.bpil + 0.03]:
		if absf(u) < 1.0:
			zs.append(u * L)
	for zw: float in [p.wf * L, p.wr * L]:
		for e in [-0.012, 0.0]:
			zs.append(zw - (r + 0.05) + e)
			zs.append(zw + (r + 0.05) - e)
	for key in ["door_f", "door_r", "bonnet_r", "bonnet_f", "boot_f", "boot_r", "bump_f", "bump_r", "cab_f", "cab_r"]:
		zs.append(d[key])
	if p.doors == 4:
		zs.append(d.rdoor_r)
	zs.sort()
	var stations: Array[float] = []
	for v in zs:
		if stations.is_empty() or v - stations[-1] > 0.004:
			stations.append(v)
	var rings: Array[PackedVector3Array] = []
	for v in stations:
		rings.append(_ring(p, v))

	# The shell, both halves, each strip to its piece; the paint mapped on the body chart.
	for i in stations.size() - 1:
		var zm := (stations[i] + stations[i + 1]) * 0.5
		var um := zm / L
		for j in RING_POINTS - 1:
			var m := _material(p, j, um)
			var piece := _panel(p, d, j, zm, m)
			for side in [1.0, -1.0]:
				var key := piece
				match piece:
					"door", "window": key = "%s%d" % [piece, Nfs5Car.DOOR_LEFT if side > 0.0 else Nfs5Car.DOOR_RIGHT]
					"sill": key = "sill%d" % (Nfs5Car.SILL_LEFT if side > 0.0 else Nfs5Car.SILL_RIGHT)
				var pm := _piece(parts, key)
				var a := _mx(rings[i][j], side)
				var b := _mx(rings[i + 1][j], side)
				var c := _mx(rings[i + 1][j + 1], side)
				var e := _mx(rings[i][j + 1], side)
				# Outward: across the strip round the ring, crossed with along the car.
				var out: Vector3 = (e - b).cross(c - a) if side > 0.0 else (c - a).cross(e - b)
				var t := [_sw(m)]
				if m == Sw.PAINT:
					t = [_chart(p, stations[i], j), _chart(p, stations[i + 1], j), _chart(p, stations[i + 1], j + 1), _chart(p, stations[i], j + 1)]
				pm.group = 1 if m == Sw.PAINT else m + 2
				pm.env = ENV[m]
				pm.quad(a, b, c, e, out, t)
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
				elif piece == "body" and m == Sw.PAINT and zm < d.cab_f and zm > d.cab_r \
						and (j in DOOR_ROWS or (j >= 8 and _cabin(p, um) > 0.001)):
					inner = "cabin"
					by = 0.05 if j < 8 else 0.025
				if inner != "":
					var im := _piece(parts, inner)
					im.group = 40 + sw
					im.env = ENV[sw]
					im.mark = Nfs5Car.ONE_SIDED_MARK if sw == Sw.DARK else 0.0
					im.quad(_mx(_inset(rings[i][j], j, by), side), _mx(_inset(rings[i + 1][j], j, by), side),
						_mx(_inset(rings[i + 1][j + 1], j + 1, by), side), _mx(_inset(rings[i][j + 1], j + 1, by), side),
						-out, [_sw(sw)])
					im.mark = 0.0
	# End caps: the lower part with the bumpers.
	for e in [0, stations.size() - 1]:
		var ring := rings[e]
		var dir := 1.0 if e > 0 else -1.0
		var mid := Vector3.ZERO
		for q in ring:
			mid += q
		mid /= ring.size()
		mid.x = 0.0
		var low := BUMPER_ROWS_F if e > 0 else BUMPER_ROWS_R
		for j in RING_POINTS - 1:
			var pm := _piece(parts, ("bumper_f" if e > 0 else "bumper_r") if j <= low else "body")
			pm.group = 20 + e
			pm.env = ENV[Sw.PAINT]
			for side in [1.0, -1.0]:
				pm.tri([mid, _mx(ring[j], side), _mx(ring[j + 1], side)], [_sw(Sw.PAINT)], Vector3(0, 0, dir))

	var lights: Array[Dictionary] = []
	var front := rings[-1]
	var rear := rings[0]
	var f_lo := front[0].y
	var f_hi := front[RING_POINTS - 1].y
	var f_hw := front[4].x
	var r_lo := rear[0].y
	var r_hi := rear[RING_POINTS - 1].y
	var r_hw := rear[4].x
	var body := _piece(parts, "body")
	var bump_f := _piece(parts, "bumper_f")
	var bump_r := _piece(parts, "bumper_r")

	# Headlamps: set into the front wings' corners, in the nose, or popping up out of the
	# bonnet; the indicators beside them.
	match p.heads:
		"corner":
			for side in [1.0, -1.0]:
				body.group = -1
				body.lens = 1.0
				body.env = 0.5
				var lamp := _decal(body, p, L - 0.34, L - 0.03, 5.1, 6.9, side, HEAD_RECT)
				body.lens = 0.0
				lights.append(_light("HWYN5", lamp))
				lights.append(_light("IOYN5", _surf(p, L - 0.08, 6.4) * Vector3(side, 1, 1)))
			bump_f.box(Transform3D(Basis(), Vector3(0, lerpf(f_lo, f_hi, 0.3), L + 0.004)),
				Vector3(f_hw * 0.62, (f_hi - f_lo) * 0.12, 0.012), Sw.TRIM, GRILLE_RECT, Vector3.BACK)
		"face":
			var y := lerpf(f_lo, f_hi, 0.7)
			var hy := (f_hi - f_lo) * 0.13
			for side in [1.0, -1.0]:
				var at := Vector3(side * f_hw * 0.66, y, L + 0.004)
				body.lens = 1.0
				body.box(Transform3D(Basis(), at), Vector3(f_hw * 0.22, hy, 0.012), Sw.CHROME, HEAD_RECT, Vector3.BACK, side < 0.0)
				body.lens = 0.0
				lights.append(_light("HWYN5", at - Vector3(side * f_hw * 0.04, 0, 0)))
				lights.append(_light("IOYN5", at + Vector3(side * f_hw * 0.17, 0, 0)))
			body.box(Transform3D(Basis(), Vector3(0, y, L + 0.004)), Vector3(f_hw * 0.36, hy, 0.012), Sw.CHROME, GRILLE_RECT, Vector3.BACK)
		"popup":
			for side in [1.0, -1.0]:
				# Indicators in the bumper's corners.
				var at := Vector3(side * f_hw * 0.8, lerpf(f_lo, f_hi, 0.42), L - 0.02)
				bump_f.lens = 1.0
				bump_f.box(Transform3D(Basis(), at), Vector3(0.09, 0.025, 0.02), Sw.AMBER)
				bump_f.lens = 0.0
				lights.append(_light("IOYN5", at))
			bump_f.box(Transform3D(Basis(), Vector3(0, lerpf(f_lo, f_hi, 0.3), L + 0.004)),
				Vector3(f_hw * 0.5, (f_hi - f_lo) * 0.08, 0.012), Sw.TRIM, GRILLE_RECT, Vector3.BACK)
	# The front bumper's bar, and fog lamps in it.
	bump_f.box(Transform3D(Basis(), Vector3(0, lerpf(f_lo, f_hi, 0.16), L + 0.015)), Vector3(f_hw + 0.02, (f_hi - f_lo) * 0.07, 0.03), Sw.TRIM)
	if p.get("fog", false):
		for side in [1.0, -1.0]:
			var at := Vector3(side * f_hw * 0.55, lerpf(f_lo, f_hi, 0.16), L + 0.05)
			bump_f.lens = 1.0
			bump_f.box(Transform3D(Basis(), at), Vector3(0.07, 0.035, 0.012), Sw.CHROME, HEAD_RECT, Vector3.BACK, side < 0.0)
			bump_f.lens = 0.0
			lights.append(_light("FWYN4", at))
	# Tail: lamps (indicator outboard, reversing inboard), plate, bumper and pipes.
	var ty := lerpf(r_lo, r_hi, 0.74)
	for side in [1.0, -1.0]:
		var at := Vector3(side * r_hw * 0.64, ty, -L - 0.004)
		var hx := r_hw * 0.3
		body.lens = 1.0
		body.box(Transform3D(Basis(), at), Vector3(hx, (r_hi - r_lo) * 0.1, 0.012), Sw.RED, TAIL_RECT, Vector3.FORWARD, side > 0.0)
		body.lens = 0.0
		lights.append(_light("TRYN5", at))
		lights.append(_light("BRYN5", at))
		lights.append(_light("RWYN3", at - Vector3(side * hx * 0.72, 0, 0)))
		lights.append(_light("IOYN5", at + Vector3(side * hx * 0.75, 0, 0)))
	var plate_y := lerpf(r_lo, r_hi, 0.46)
	body.box(Transform3D(Basis(), Vector3(0, plate_y, -L - 0.008)), Vector3(0.17, 0.085, 0.01), Sw.WHITE, PLATE_RECT, Vector3.FORWARD)
	bump_r.box(Transform3D(Basis(), Vector3(0, lerpf(r_lo, r_hi, 0.17), -L - 0.015)), Vector3(r_hw + 0.02, (r_hi - r_lo) * 0.09, 0.03), Sw.TRIM)
	var exhausts: Array[Vector3] = []
	var pipes: Array[float] = []
	match int(p.pipes):
		1: pipes = [-0.5]
		2: pipes = [0.5, -0.5]
		4: pipes = [0.42, 0.56, -0.42, -0.56]
	for fx in pipes:
		var at := Vector3(fx * r_hw, r_lo + 0.03, -L + 0.12)
		var tip := at - Vector3(0, 0, 0.2)
		bump_r.tube(at, tip, 0.032, 0.036, 10, Sw.CHROME, false)
		bump_r.tube(tip + Vector3(0, 0, 0.015), tip - Vector3(0, 0, 0.0), 0.026, 0.026, 10, Sw.TRIM, true)
		exhausts.append(tip)
	# The third brake lamp, up on the parcel shelf behind the rear window.
	var shelf_z: float = p.rw0 * L + 0.06
	var shelf_y := _top(p, shelf_z) + 0.025
	_piece(parts, "cabin").lens = 1.0
	_piece(parts, "cabin").box(Transform3D(Basis(), Vector3(0, shelf_y, shelf_z)), Vector3(0.14, 0.015, 0.02), Sw.RED)
	_piece(parts, "cabin").lens = 0.0
	lights.append(_light("BRYN3", Vector3(0, shelf_y, shelf_z - 0.03)))

	# Pop-up headlamps: pods on the bonnet's front corners, shown raised.
	var popups: Array[Dictionary] = []
	if p.heads == "popup":
		var pod := _Mesh.new()
		var pz := L - 0.24
		for side in [1.0, -1.0]:
			var px: float = side * f_hw * 0.6
			var top_y := _surf(p, pz, 9.5).y
			var c := Vector3(px, top_y + 0.045, pz)
			pod.box(Transform3D(Basis(), c), Vector3(0.13, 0.045, 0.09), Sw.TRIM)
			pod.box(Transform3D(Basis(), c + Vector3(0, 0.047, 0)), Vector3(0.13, 0.003, 0.09), Sw.PAINT)
			pod.lens = 1.0
			pod.box(Transform3D(Basis(), c + Vector3(0, 0, 0.092)), Vector3(0.12, 0.038, 0.004), Sw.CHROME, HEAD_RECT, Vector3.BACK, side < 0.0)
			pod.lens = 0.0
			lights.append(_light("HWYN5", c + Vector3(0, 0, 0.1)))
		# (Down, they sink into the bonnet: Car tips them forward about their back edge.)
		popups.append({"name": "popup", "mesh": pod.commit(), "center": Vector3.ZERO})

	# Door mirrors on stalks from the front corner of each door's window.
	var zm_mirror: float = minf(d.door_f - 0.1, lerpf(p.ws0, p.ws1, 0.25) * L)
	var mring := _ring(p, zm_mirror)
	for side in [1.0, -1.0]:
		var g: int = Nfs5Car.DOOR_LEFT if side > 0.0 else Nfs5Car.DOOR_RIGHT
		var hm := _piece(parts, "mirror%d" % g)
		var gm := _piece(parts, "mglass%d" % g)
		var base := mring[7].lerp(mring[8], 0.2)
		hm.box(Transform3D(Basis(), _mx(base + Vector3(0.05, 0, 0), side)), Vector3(0.05, 0.012, 0.02), Sw.TRIM)
		var pod_c := _mx(base + Vector3(0.13, 0.03, 0), side)
		hm.box(Transform3D(Basis(), pod_c), Vector3(0.06, 0.045, 0.045), Sw.PAINT)
		gm.box(Transform3D(Basis(), pod_c + Vector3(0, 0, -0.047)), Vector3(0.052, 0.037, 0.003), Sw.MIRROR)

	# Wipers parked on the scuttle at the windshield's foot.
	var wipers := _wipers(p, d)

	# Spoilers on the boot (or engine) lid.
	var spoilers := _spoilers(p, d)

	# Light bar across the roof; the siren dummies sit at its ends (red on +X, blue on -X).
	if p.get("lightbar", false):
		var zl: float = (p.ws1 + p.rw1) * 0.5 * L
		var y: float = GROUND + p.roof + 0.05
		body.box(Transform3D(Basis(), Vector3(0, y, zl)), Vector3(0.1, 0.05, 0.11), Sw.TRIM)
		body.lens = 1.0
		body.box(Transform3D(Basis(), Vector3(0.3, y, zl)), Vector3(0.2, 0.05, 0.1), Sw.RED)
		body.box(Transform3D(Basis(), Vector3(-0.3, y, zl)), Vector3(0.2, 0.05, 0.1), Sw.BLUE)
		body.lens = 0.0
		lights.append(_light("SMLN", Vector3(0.4, y, zl)))
		lights.append(_light("SMRN", Vector3(-0.4, y, zl)))

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
		var x := _ring(p, zw)[4].x - 0.02 - TYRE_W * 0.5
		var side := 1.0 if slot % 2 == 0 else -1.0
		var wl: Array = wheel_l if side > 0.0 else wheel_r
		wheels.append({"name": "wheel", "mesh": wl[0], "brake": wl[1], "center": Vector3(side * x, GROUND + r, zw), "slot": slot})

	return {"parts": _assemble(p, d, parts, wipers, spoilers, cabin, driver), "wheels": wheels, "lights": lights,
		"texture": _skin(p, d), "half_size": Vector3(W, GROUND + p.roof, L), "popups": popups,
		"exhausts": exhausts, "plate": {"pos": Vector3(0, plate_y, -L - 0.014), "euro": p.euro},
		"dash": {"eye": cabin.eye, "own_cabin": true}}


## The pieces as Car takes them: what opens about its hinge ("lid", "hinge", "axis", "open"),
## the windows that wind down ("window", "drop", "belt"), what comes off ("loose"), the bays
## shown with their lids open ("bay"), the glass, the moving parts' frames.
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


## A lamp (or any patch of the skin) laid on the body surface over `z0..z1` along the car and
## `s0..s1` round the ring, just proud of it. Returns its middle.
static func _decal(m: _Mesh, p: Dictionary, z0: float, z1: float, s0: float, s1: float,
		side: float, rect: Rect2i) -> Vector3:
	const NA := 7
	const NB := 5
	var grid: Array[PackedVector3Array] = []
	for i in NA:
		var row := PackedVector3Array()
		var z := lerpf(z0, z1, i / (NA - 1.0))
		for k in NB:
			var s := lerpf(s0, s1, k / (NB - 1.0))
			var q := _surf(p, z, s)
			var n := (_surf(p, z, s + 0.05) - _surf(p, z, s - 0.05)).cross(_surf(p, z + 0.01, s) - _surf(p, z - 0.01, s))
			row.append(_mx(q + n.normalized() * 0.008, side))
		grid.append(row)
	for i in NA - 1:
		for k in NB - 1:
			var a := grid[i][k]
			var b := grid[i + 1][k]
			var c := grid[i + 1][k + 1]
			var e := grid[i][k + 1]
			var out: Vector3 = (e - b).cross(c - a) if side > 0.0 else (c - a).cross(e - b)
			m.quad(a, b, c, e, out, [_patch(rect, i / (NA - 1.0), 1.0 - k / (NB - 1.0)), _patch(rect, (i + 1) / (NA - 1.0), 1.0 - k / (NB - 1.0)),
				_patch(rect, (i + 1) / (NA - 1.0), 1.0 - (k + 1) / (NB - 1.0)), _patch(rect, i / (NA - 1.0), 1.0 - (k + 1) / (NB - 1.0))])
	return grid[NA / 2][NB / 2]


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


## A wheel: a tyre with rounded shoulders round a recessed rim, its face the skin's wheel
## picture with the gaps between the spokes cut out; behind it the brake disc and calliper
## (which steer and ride with the wheel but don't turn). Axle along X, `side` outboard.
## Returns [wheel, brake].
static func _wheel(r: float, side: float, p: Dictionary) -> Array:
	const N := 28
	var m := _Mesh.new()
	var rr := r * 0.66
	var hx := TYRE_W * 0.5
	var dish := hx - 0.035
	# The tyre's section, inner bead over the tread to the outer bead; the rim's barrel inside.
	var tyre: Array[Vector2] = [Vector2(-hx, rr), Vector2(-hx - 0.005, r * 0.83), Vector2(-hx * 0.9, r * 0.97),
		Vector2(-hx * 0.6, r), Vector2(hx * 0.6, r), Vector2(hx * 0.9, r * 0.97), Vector2(hx + 0.005, r * 0.83), Vector2(hx, rr)]
	var barrel: Array[Vector2] = [Vector2(hx, rr), Vector2(dish, rr), Vector2(-hx * 0.8, rr * 0.98)]
	for sec in [[tyre, Sw.TYRE, 1.0], [barrel, Sw.CHROME, -1.0]]:
		var prof: Array[Vector2] = sec[0]
		m.group = sec[1] + 1
		m.env = ENV[sec[1]]
		for k in prof.size() - 1:
			var t := prof[k + 1] - prof[k]
			var n: Vector2 = Vector2(-t.y, t.x) * float(sec[2])   # the tyre outward, the barrel inward
			for i in N:
				var a0 := TAU * i / N
				var a1 := TAU * (i + 1) / N
				var am := (a0 + a1) * 0.5
				m.quad(_rev(prof[k], a0, side), _rev(prof[k + 1], a0, side), _rev(prof[k + 1], a1, side), _rev(prof[k], a1, side),
					Vector3(n.x * side, n.y * cos(am), n.y * sin(am)), [_sw(sec[1])])
	# The rim's face (cut out between the spokes) and the dark back of the wheel.
	m.group = -1
	m.env = 0.7
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var c := Vector3(dish * side, 0, 0)
		m.tri([c, _rev(Vector2(dish, rr), a0, side), _rev(Vector2(dish, rr), a1, side)],
			[_patch(RIM_RECT, 0.5, 0.5), _rim_uv(a0), _rim_uv(a1)], Vector3(side, 0, 0))
		m.env = 0.0
		m.tri([Vector3(-hx * 0.8 * side, 0, 0), _rev(Vector2(-hx * 0.8, rr * 0.98), a0, side), _rev(Vector2(-hx * 0.8, rr * 0.98), a1, side)],
			[_sw(Sw.TRIM)], Vector3(side, 0, 0))
		m.env = 0.7
	# The hub's cap, proud of the face.
	m.tube(Vector3((dish - 0.002) * side, 0, 0), Vector3((dish + 0.012) * side, 0, 0), r * 0.1, r * 0.08, 10, Sw.CHROME)
	var brake := _Mesh.new()
	var disc_x := dish - 0.05
	brake.tube(Vector3((disc_x - 0.012) * side, 0, 0), Vector3((disc_x + 0.012) * side, 0, 0), rr * 0.82, rr * 0.82, 20, Sw.CHROME)
	brake.tube(Vector3((disc_x + 0.012) * side, 0, 0), Vector3((disc_x + 0.016) * side, 0, 0), rr * 0.3, rr * 0.3, 10, Sw.DARK)
	# The calliper over the disc's trailing top.
	var cal := Vector3((disc_x + 0.005) * side, rr * 0.62 * cos(0.6), -rr * 0.62 * sin(0.6))
	var cal_red: bool = p.rim == "spoke"
	brake.box(Transform3D(Basis(Vector3.RIGHT, 0.6), cal), Vector3(0.03, rr * 0.18, 0.05), Sw.RED if cal_red else Sw.DARK)
	return [m.commit(), brake.commit()]


static func _rev(q: Vector2, a: float, side: float) -> Vector3:
	return Vector3(q.x * side, q.y * cos(a), q.y * sin(a))


static func _rim_uv(a: float) -> Vector2:
	return _patch(RIM_RECT, 0.5 + 0.5 * sin(a), 0.5 - 0.5 * cos(a))


# ------------------------------------------------------------------ skin

static func _skin(p: Dictionary, d: Dictionary) -> ImageTexture:
	var img := Image.create(SKIN, SKIN, false, Image.FORMAT_RGBA8)
	img.fill(Color8(34, 34, 36))
	var swatches := [Color8(128, 128, 128, PAINT_A), Color8(14, 18, 24), Color8(26, 26, 28), Color8(185, 188, 194),
		Color8(150, 14, 12), Color8(230, 232, 236), Color8(34, 34, 36), Color8(220, 120, 20), Color8(20, 50, 200),
		Color8(228, 228, 224), Color8(128, 128, 128, CABIN_A), Color8(44, 45, 48), Color8(70, 70, 70, CABIN_A),
		Color8(38, 44, 62), Color8(150, 155, 165), Color8(10, 10, 14)]
	for i in swatches.size():
		img.fill_rect(Rect2i(i * SWATCH, 0, SWATCH, SWATCH), swatches[i])
	var rim := Color8(70, 72, 76)
	_paint(img, HEAD_RECT, func(x: int, y: int) -> Color:
		if x < 3 or y < 3 or x > 124 or y > 60:
			return rim
		if x > 104:
			return Color8(225, 130, 30)   # the indicator, outboard
		for cx in [34, 80]:
			var dd := Vector2(x - cx, y - 32).length()
			if dd < 22.0:
				return Color8(245, 246, 250) if dd < 13.0 else Color8(150, 155, 165) if dd > 19.0 else Color8(205, 210, 220)
		return Color8(195, 200, 212))
	var round_tails: bool = p.tails == "round"
	_paint(img, TAIL_RECT, func(x: int, y: int) -> Color:
		if x < 3 or y < 3 or x > 124 or y > 60:
			return Color8(40, 6, 6)
		if x > 104:
			return Color8(225, 130, 30)   # indicator, outboard
		if x < 24:
			return Color8(225, 225, 220)   # reversing lamp, inboard
		if round_tails:
			var dd := Vector2(x - 64, y - 32).length()
			if dd < 26.0:
				return Color8(215, 25, 20) if dd < 17.0 else Color8(120, 10, 10)
			return Color8(30, 30, 32)
		return Color8(205, 22, 18) if y % 10 < 6 else Color8(140, 12, 10))
	_paint(img, GRILLE_RECT, func(x: int, y: int) -> Color:
		if x < 3 or y < 3 or x > 124 or y > 60:
			return Color8(170, 172, 176)
		return Color8(55, 56, 58) if (y % 8 < 3 or x % 16 < 2) else Color8(10, 10, 12))
	_paint(img, DIAL_RECT, func(x: int, y: int) -> Color:
		var cx := 32 if x < 64 else 96
		var dv := Vector2(x - cx, y - 32)
		var dd := dv.length()
		if dd > 30.0:
			return Color8(30, 30, 32)
		if dd > 28.0:
			return Color8(160, 162, 168)
		# Ticks round three quarters of the face, from the bottom left over the top.
		var a := fposmod(atan2(dv.x, -dv.y) + PI * 0.75 + PI, TAU) - PI
		if dd > 21.0 and absf(a) < PI * 0.75 and fposmod(a * 12.0 / PI, 1.0) < 0.22:
			return Color8(235, 235, 230)
		if dd > 24.0 and a > PI * 0.5 and a < PI * 0.75 and x >= 64:
			return Color8(200, 30, 20)   # the red line
		return Color8(12, 12, 14))
	_paint(img, SEAT_RECT, func(x: int, y: int) -> Color:
		# Pleats: stitched lines across the leather (all at the cabin's alpha: tinted with it).
		if y % 12 == 0 or x < 2 or x > 125:
			return Color8(80, 80, 80, CABIN_A)
		return Color8(128, 128, 128, CABIN_A) if absf(x - 64) < 40 else Color8(110, 110, 110, CABIN_A))
	var plate := hash(p.name)
	_paint(img, PLATE_RECT, func(x: int, y: int) -> Color:
		if x < 3 or y < 3 or x > 124 or y > 60:
			return Color8(30, 40, 90)
		if y >= 18 and y <= 46 and x >= 12 and x <= 115 and (x - 12) % 16 < 12:
			# Characters: a few strokes per cell.
			var cell := (x - 12) / 16
			var bits := (plate >> (cell * 5)) | 0x11
			var colm := ((x - 12) % 16) / 4
			var row := (y - 18) / 10
			if (bits >> ((colm + row * 2) % 5)) & 1:
				return Color8(30, 30, 40)
		return Color8(235, 235, 225))
	_paint(img, CAM_RECT, func(x: int, y: int) -> Color:
		if y % 8 < 2:
			return Color8(60, 8, 6)
		return Color8(170, 20, 16))
	var spokes: int = p.spokes
	var style: String = p.rim
	_paint(img, RIM_RECT, func(x: int, y: int) -> Color:
		var dv := Vector2(x - 63.5, y - 63.5) / 64.0
		var rho := dv.length()
		var th := atan2(dv.y, dv.x)
		if rho > 0.97:
			return Color8(34, 34, 36)
		if rho > 0.88:
			return Color8(215, 217, 222)
		if rho < 0.2:
			for k in 5:
				if (dv - Vector2.from_angle(TAU * k / 5.0) * 0.14).length() < 0.03:
					return Color8(40, 40, 44)
			return Color8(185, 187, 192)
		var gap := Color(0, 0, 0, 0)   # cut out: the brake behind shows through
		var shade := 0.88 + 0.12 * cos(th + 0.8)
		var metal := Color8(200, 202, 208) * shade
		metal.a = 1.0
		var f := fposmod(th / TAU * spokes, 1.0)
		var off := minf(f, 1.0 - f)   # angular distance to the nearest spoke, in spokes
		if style == "steel":
			var steel := Color8(150, 150, 152) * shade
			steel.a = 1.0
			var hole := Vector2.from_angle((floorf(th / TAU * spokes + 0.5)) * TAU / spokes) * 0.6
			return gap if (dv - hole).length() < 0.09 else steel
		if style == "hubcap":
			return Color8(40, 40, 44) if rho > 0.45 and rho < 0.8 and off < 0.12 else metal
		return metal if off < 0.12 + 0.14 * (1.0 - rho) * 5.0 / spokes else gap)
	_paint_body(img, p, d)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The body chart (BODY_RECT, see _chart()): the paint, with the shut lines drawn round the
## doors, lids and bumpers (car.gdshader cuts them into it), the door handles, and a
## cruiser's white doors.
static func _paint_body(img: Image, p: Dictionary, d: Dictionary) -> void:
	var L: float = p.len
	var w := BODY_RECT.size.x
	var h := BODY_RECT.size.y
	var sx := 2.0 * L / (w - 2)              # m per texel along the car
	var sk := (RING_POINTS - 1.0) / (h - 2)  # ring points per texel round it
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
	# Texel (x, y) of the chart is at z = -L + (x - 0.5) sx, ring point k = (y - 0.5) sk (_patch).
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
		handles.append(Rect2(rear_edge + 0.07, 6.15, 0.16, 0.3))
	var cream_z0: float = d.rdoor_r if p.doors == 4 else d.door_r
	var twotone: bool = p.get("twotone", false)
	var px := PackedByteArray()
	px.resize(w * h * 4)
	for ty in h:
		var k := (ty - 0.5) * sk
		for tx in w:
			var z := -L + (tx - 0.5) * sx
			var c := Color8(128, 128, 128, PAINT_A)
			if twotone and k >= dk and k <= tk and z < d.door_f and z > cream_z0:
				c = Color8(228, 228, 224)
			for hr in handles:
				if hr.has_point(Vector2(z, k)):
					c = Color8(60, 60, 62, PAINT_A) if k < 6.27 else Color8(190, 192, 196)
			var shade := lerpf(0.3, 1.0, clampf(near[ty * w + tx] - 0.4, 0.0, 1.0))
			var o := (ty * w + tx) * 4
			px[o] = int(c.r8 * shade)
			px[o + 1] = int(c.g8 * shade)
			px[o + 2] = int(c.b8 * shade)
			px[o + 3] = c.a8
	img.blit_rect(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px), Rect2i(Vector2i.ZERO, BODY_RECT.size), BODY_RECT.position)


static func _paint(img: Image, rect: Rect2i, f: Callable) -> void:
	for y in rect.size.y:
		for x in rect.size.x:
			img.set_pixel(rect.position.x + x, rect.position.y + y, f.call(x, y))

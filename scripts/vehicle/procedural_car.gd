class_name ProceduralCar
## Stand-in car data (same interface as Nfs3Car), used when no NFS3 install is
## available and for generic cop/traffic cars. Each preset is modelled from a handful
## of body lines: a lofted shell with wheel arches and a glasshouse, lamps, grille,
## plate, mirrors and spoiler, detailed wheels, and a generated skin that goes through
## the same paint/glass/rubber shader (car.gdshader) as the NFS3 cars.

const GROUND := -0.6   # the road below the car's origin at rest

# Body lines in metres, heights above the road. Positions along the car are fractions
# of its half length `len` (front +1): ws0/ws1 windshield base/top, rw1/rw0 rear window
# top/base, bpil the B pillar (none outside -1..1), cpil where the side glass ends,
# wf/wr the axles. rc rounds the corners in plan, re the ends in side view.
const PRESETS := [
	{"name": "Stinger GT", "color": Color(0.85, 0.1, 0.08), "mass": 1400.0, "top": 80.0, "torque": 520.0,
		"len": 2.25, "wid": 0.95, "roof": 1.27, "nose": 0.56, "hood": 0.84, "deck": 0.92, "tail": 0.86, "crown": 0.05,
		"ws0": 0.2, "ws1": -0.08, "rw1": -0.4, "rw0": -0.66, "bpil": 2.0, "cpil": -0.42, "tumble": 0.76,
		"clear": 0.15, "r": 0.33, "wf": 0.64, "wr": -0.6, "rc": 0.34, "re": 0.24,
		"heads": "corner", "tails": "round", "rim": "spoke", "spokes": 5, "spoiler": 1},
	{"name": "Vortex V12", "color": Color(0.95, 0.75, 0.1), "mass": 1550.0, "top": 90.0, "torque": 600.0,
		"len": 2.25, "wid": 1.0, "roof": 1.12, "nose": 0.5, "hood": 0.72, "deck": 0.96, "tail": 0.92, "crown": 0.03,
		"ws0": 0.42, "ws1": 0.02, "rw1": -0.22, "rw0": -0.7, "bpil": 2.0, "cpil": -0.25, "tumble": 0.72,
		"clear": 0.13, "r": 0.34, "wf": 0.62, "wr": -0.6, "rc": 0.38, "re": 0.2,
		"heads": "corner", "tails": "strip", "rim": "spoke", "spokes": 10, "spoiler": 2},
	{"name": "Aero RS", "color": Color(0.1, 0.35, 0.9), "mass": 1250.0, "top": 76.0, "torque": 430.0,
		"len": 2.1, "wid": 0.9, "roof": 1.28, "nose": 0.55, "hood": 0.74, "deck": 0.78, "tail": 0.76, "crown": 0.06,
		"ws0": 0.28, "ws1": 0.0, "rw1": -0.25, "rw0": -0.9, "bpil": 2.0, "cpil": -0.5, "tumble": 0.74,
		"clear": 0.14, "r": 0.32, "wf": 0.66, "wr": -0.62, "rc": 0.4, "re": 0.28,
		"heads": "corner", "tails": "strip", "rim": "spoke", "spokes": 6, "spoiler": 1},
	{"name": "Interceptor", "color": Color(0.08, 0.08, 0.1), "mass": 1700.0, "top": 82.0, "torque": 560.0,
		"len": 2.5, "wid": 0.98, "roof": 1.45, "nose": 0.78, "hood": 0.95, "deck": 1.0, "tail": 0.96, "crown": 0.04,
		"ws0": 0.3, "ws1": 0.06, "rw1": -0.3, "rw0": -0.5, "bpil": -0.12, "cpil": -0.42, "tumble": 0.8,
		"clear": 0.17, "r": 0.33, "wf": 0.64, "wr": -0.6, "rc": 0.22, "re": 0.14,
		"heads": "face", "tails": "strip", "rim": "steel", "spokes": 8, "spoiler": 0,
		"lightbar": true, "twotone": true},
	{"name": "Sedan", "color": Color(0.6, 0.62, 0.55), "mass": 1500.0, "top": 50.0, "torque": 300.0,
		"len": 2.3, "wid": 0.92, "roof": 1.44, "nose": 0.76, "hood": 0.92, "deck": 0.98, "tail": 0.94, "crown": 0.04,
		"ws0": 0.3, "ws1": 0.06, "rw1": -0.32, "rw0": -0.52, "bpil": -0.12, "cpil": -0.44, "tumble": 0.8,
		"clear": 0.16, "r": 0.31, "wf": 0.64, "wr": -0.6, "rc": 0.22, "re": 0.14,
		"heads": "face", "tails": "strip", "rim": "hubcap", "spokes": 12, "spoiler": 0},
]

# The skin: flat swatches along the top row (the paint and glass carry the mid alpha the
# shader reads as paintable), patterned patches below them.
enum Sw { PAINT, GLASS, TRIM, CHROME, RED, WHITE, TYRE, AMBER, BLUE, CREAM }
const SKIN := 256
const HEAD_RECT := Rect2i(0, 32, 64, 32)
const TAIL_RECT := Rect2i(64, 32, 64, 32)
const GRILLE_RECT := Rect2i(128, 32, 64, 32)
const PLATE_RECT := Rect2i(192, 32, 64, 32)
const RIM_RECT := Rect2i(0, 128, 128, 128)
const TYRE_W := 0.24

var id := ""
var display_name := ""
var texture: Texture2D = null
var body_parts: Array[Dictionary] = []
var wheels: Array[Dictionary] = []
var popup_lights: Array[Dictionary] = []
var half_size := Vector3.ONE
var colours: Array[Color] = []
var lights: Array[Dictionary] = []
var carp := {}
var error := ""
var body_color := Color.WHITE

# Built meshes and skin per preset; only the paint colour differs between cars of one preset.
static var _models := {}


static func make(preset: int, tint := Color(0, 0, 0, 0)) -> ProceduralCar:
	preset = clampi(preset, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[preset]
	var c := ProceduralCar.new()
	c.id = "proc%d" % preset
	c.display_name = p.name
	c.body_color = p.color if tint.a == 0 else tint
	# The skin's paint is mid-grey, so the colour goes on at double strength (as NFS3's do).
	c.colours = [Color(c.body_color.r * 2.0, c.body_color.g * 2.0, c.body_color.b * 2.0)]
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
	if not _models.has(preset):
		_models[preset] = _build(p)
	var m: Dictionary = _models[preset]
	c.texture = m.texture
	c.half_size = m.half_size
	c.lights = m.lights
	c.body_parts.append({"name": "body", "mesh": m.body, "center": Vector3.ZERO})
	c.wheels = m.wheels
	return c


## A lamp as NFS3's light dummies name it (see Nfs3Car.decode_light()).
static func _light(dname: String, pos: Vector3) -> Dictionary:
	var l := Nfs3Car.decode_light(dname)
	l.pos = pos
	return l


static func _torque_curve(peak: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 41:
		var rpm := i * 256.0
		out.append(peak * clampf(0.55 + 0.45 * sin(clampf(rpm / 5500.0, 0.0, 1.4) * PI * 0.5), 0.0, 1.0) * (1.0 - clampf((rpm - 6500.0) / 4000.0, 0.0, 0.6)))
	return out


func carp_value(key: int, default := 0.0, index := 0) -> float:
	if carp.has(key) and carp[key].size() > index:
		return carp[key][index]
	return default


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
		Vector2(hw, bot + 0.4 * (belt - bot)), Vector2(hw - 0.01, belt - 0.1), Vector2(hw - 0.07, belt),
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


## What a strip of the shell between two ring points `j`, `j + 1` is made of at `u`.
static func _material(p: Dictionary, j: int, u: float) -> int:
	if j <= 2:
		return Sw.TRIM
	var c := _cabin(p, u)
	if j == 7 and c > 0.001 and u > p.cpil:
		return Sw.TRIM if absf(u - p.bpil) < 0.03 else Sw.GLASS
	if j >= 9 and c > 0.001 and c < 0.999:
		return Sw.GLASS
	# Cruisers: white doors on the black car.
	if p.get("twotone", false) and j >= 3 and j <= 5 and u > p.bpil - 0.4 and u < p.bpil + 0.36:
		return Sw.CREAM
	return Sw.PAINT


# ------------------------------------------------------------------ building

static func _build(p: Dictionary) -> Dictionary:
	var L: float = p.len
	var W: float = p.wid
	var r: float = p.r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Stations along the car: close together round the ends, and on every body line.
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
		for d in [-0.012, 0.0]:
			zs.append(zw - (r + 0.05) + d)
			zs.append(zw + (r + 0.05) - d)
	zs.sort()
	var stations: Array[float] = []
	for v in zs:
		if stations.is_empty() or v - stations[-1] > 0.004:
			stations.append(v)
	var rings: Array[PackedVector3Array] = []
	for v in stations:
		rings.append(_ring(p, v))

	# The shell, both halves.
	for i in stations.size() - 1:
		var um := (stations[i] + stations[i + 1]) * 0.5 / L
		for j in rings[i].size() - 1:
			var m := _material(p, j, um)
			st.set_smooth_group(m + 1)
			for side in [1.0, -1.0]:
				var a := _mx(rings[i][j], side)
				var b := _mx(rings[i + 1][j], side)
				var c := _mx(rings[i + 1][j + 1], side)
				var d := _mx(rings[i][j + 1], side)
				# Outward: across the strip round the ring, crossed with along the car.
				var out: Vector3 = (d - b).cross(c - a) if side > 0.0 else (c - a).cross(d - b)
				_quad(st, a, b, c, d, out, _sw(m))
	# End caps.
	for e in [0, stations.size() - 1]:
		var ring := rings[e]
		var dir := 1.0 if e > 0 else -1.0
		var mid := Vector3.ZERO
		for q in ring:
			mid += q
		mid /= ring.size()
		mid.x = 0.0
		st.set_smooth_group(20 + e)
		for j in ring.size() - 1:
			for side in [1.0, -1.0]:
				_tri(st, [mid, _mx(ring[j], side), _mx(ring[j + 1], side)], [_sw(Sw.PAINT)], Vector3(0, 0, dir))

	var lights: Array[Dictionary] = []
	var front := rings[-1]
	var rear := rings[0]
	var f_lo := front[0].y
	var f_hi := front[11].y
	var f_hw := front[4].x
	var r_lo := rear[0].y
	var r_hi := rear[11].y
	var r_hw := rear[4].x
	var group := 30
	# Headlamps: set into the front wings' corners on the sports cars, in the nose on the saloons.
	if p.heads == "corner":
		for side in [1.0, -1.0]:
			st.set_smooth_group(group)
			group += 1
			var lamp := _decal(st, p, L - 0.34, L - 0.03, 5.1, 6.9, side, HEAD_RECT)
			lights.append(_light("HFLN", lamp))
		_box(st, Vector3(0, lerpf(f_lo, f_hi, 0.32), L + 0.004), Vector3(f_hw * 0.72, (f_hi - f_lo) * 0.16, 0.012),
			Sw.TRIM, GRILLE_RECT, 1.0)
	else:
		var y := lerpf(f_lo, f_hi, 0.7)
		var hy := (f_hi - f_lo) * 0.13
		for side in [1.0, -1.0]:
			var pos := Vector3(side * f_hw * 0.66, y, L + 0.004)
			_box(st, pos, Vector3(f_hw * 0.22, hy, 0.012), Sw.CHROME, HEAD_RECT, 1.0, side < 0.0)
			lights.append(_light("HFLN", pos))
		_box(st, Vector3(0, y, L + 0.004), Vector3(f_hw * 0.36, hy, 0.012), Sw.CHROME, GRILLE_RECT, 1.0)
		_box(st, Vector3(0, lerpf(f_lo, f_hi, 0.22), L + 0.02), Vector3(f_hw + 0.02, (f_hi - f_lo) * 0.12, 0.035), Sw.TRIM)
	# Tail: lamps, plate, bumper and twin exhausts.
	var ty := lerpf(r_lo, r_hi, 0.74)
	for side in [1.0, -1.0]:
		var pos := Vector3(side * r_hw * 0.64, ty, -L - 0.004)
		_box(st, pos, Vector3(r_hw * 0.3, (r_hi - r_lo) * 0.1, 0.012), Sw.RED, TAIL_RECT, -1.0, side > 0.0)
		lights.append(_light("TRLN", pos))
		var ex := Vector3(side * r_hw * 0.5, r_lo + 0.02, -L - 0.02)
		_box(st, ex, Vector3(0.045, 0.035, 0.07), Sw.CHROME)
		_box(st, ex - Vector3(0, 0, 0.066), Vector3(0.03, 0.022, 0.006), Sw.TRIM)
	_box(st, Vector3(0, lerpf(r_lo, r_hi, 0.42), -L - 0.008), Vector3(0.2, 0.055, 0.01), Sw.WHITE, PLATE_RECT, -1.0)
	_box(st, Vector3(0, lerpf(r_lo, r_hi, 0.18), -L - 0.015), Vector3(r_hw + 0.02, (r_hi - r_lo) * 0.1, 0.03), Sw.TRIM)

	# Door mirrors on stalks from the front corner of the side windows.
	var zm: float = lerpf(p.ws0, p.ws1, 0.3) * L
	var mring := _ring(p, zm)
	for side in [1.0, -1.0]:
		var base := mring[7].lerp(mring[8], 0.25)
		_box(st, _mx(base + Vector3(0.05, 0, 0), side), Vector3(0.05, 0.012, 0.02), Sw.TRIM)
		_box(st, _mx(base + Vector3(0.12, 0.02, 0), side), Vector3(0.045, 0.04, 0.05), Sw.PAINT)
	# Spoiler: a lip on the tail, or a wing on posts.
	if p.spoiler == 1:
		var sr := _ring(p, -L + 0.2)
		_box(st, Vector3(0, sr[11].y + 0.012, -L + 0.2), Vector3(sr[6].x - 0.08, 0.014, 0.07), Sw.PAINT)
	elif p.spoiler == 2:
		var sr := _ring(p, -L + 0.22)
		var top := sr[11].y + 0.2
		for side in [1.0, -1.0]:
			_box(st, Vector3(side * W * 0.55, (top + sr[9].y) * 0.5, -L + 0.22), Vector3(0.02, (top - sr[9].y) * 0.5, 0.05), Sw.TRIM)
		_box(st, Vector3(0, top, -L + 0.2), Vector3(W * 0.92, 0.022, 0.15), Sw.PAINT)
		for side in [1.0, -1.0]:
			_box(st, Vector3(side * W * 0.92, top - 0.03, -L + 0.2), Vector3(0.012, 0.07, 0.16), Sw.PAINT)
	# Light bar across the roof; the siren dummies sit at its ends (red on +X, blue on -X).
	if p.get("lightbar", false):
		var zl: float = (p.ws1 + p.rw1) * 0.5 * L
		var y: float = GROUND + p.roof + 0.05
		_box(st, Vector3(0, y, zl), Vector3(0.1, 0.05, 0.11), Sw.TRIM)
		_box(st, Vector3(0.3, y, zl), Vector3(0.2, 0.05, 0.1), Sw.RED)
		_box(st, Vector3(-0.3, y, zl), Vector3(0.2, 0.05, 0.1), Sw.BLUE)
		lights.append(_light("SMLN", Vector3(0.4, y, zl)))
		lights.append(_light("SMRN", Vector3(-0.4, y, zl)))

	st.generate_normals()
	var body := st.commit()

	# Wheels flush with the flanks; the model is +X outboard, mirrored for the right side.
	var wheel_l := _wheel(r, 1.0)
	var wheel_r := _wheel(r, -1.0)
	var wheels: Array[Dictionary] = []
	for slot in 4:
		var zw: float = (p.wf if slot < 2 else p.wr) * L
		var x := _ring(p, zw)[4].x - 0.02 - TYRE_W * 0.5
		var side := 1.0 if slot % 2 == 0 else -1.0
		wheels.append({"name": "wheel", "mesh": wheel_l if side > 0.0 else wheel_r,
			"center": Vector3(side * x, GROUND + r, zw), "slot": slot})
	return {"body": body, "wheels": wheels, "lights": lights, "texture": _skin(p),
		"half_size": Vector3(W, GROUND + p.roof, L)}


## A lamp (or any patch of the skin) laid on the body surface over `z0..z1` along the car and
## `s0..s1` round the ring, just proud of it. Returns its middle.
static func _decal(st: SurfaceTool, p: Dictionary, z0: float, z1: float, s0: float, s1: float,
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
			var d := grid[i][k + 1]
			var out: Vector3 = (d - b).cross(c - a) if side > 0.0 else (c - a).cross(d - b)
			var uv := [_patch(rect, i / (NA - 1.0), 1.0 - k / (NB - 1.0)), _patch(rect, (i + 1) / (NA - 1.0), 1.0 - k / (NB - 1.0)),
				_patch(rect, (i + 1) / (NA - 1.0), 1.0 - (k + 1) / (NB - 1.0)), _patch(rect, i / (NA - 1.0), 1.0 - (k + 1) / (NB - 1.0))]
			_tri(st, [a, b, c], [uv[0], uv[1], uv[2]], out)
			_tri(st, [a, c, d], [uv[0], uv[2], uv[3]], out)
	return grid[NA / 2][NB / 2]


## A wheel: a tyre with rounded shoulders round a recessed rim; axle along X, `side` the
## outboard direction.
static func _wheel(r: float, side: float) -> ArrayMesh:
	const N := 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rr := r * 0.66
	var hx := TYRE_W * 0.5
	var dish := hx - 0.035
	# The tyre's section, inner bead over the tread to the outer bead.
	var tyre: Array[Vector2] = [Vector2(-hx, rr), Vector2(-hx - 0.005, r * 0.83), Vector2(-hx * 0.9, r * 0.97),
		Vector2(-hx * 0.6, r), Vector2(hx * 0.6, r), Vector2(hx * 0.9, r * 0.97), Vector2(hx + 0.005, r * 0.83), Vector2(hx, rr)]
	var barrel: Array[Vector2] = [Vector2(hx, rr), Vector2(dish, rr)]
	for sec in [[tyre, Sw.TYRE], [barrel, Sw.CHROME]]:
		var prof: Array[Vector2] = sec[0]
		st.set_smooth_group(sec[1] + 1)
		for k in prof.size() - 1:
			var t := prof[k + 1] - prof[k]
			var n := Vector2(-t.y, t.x)   # outward, going over the top of the section
			for i in N:
				var a0 := TAU * i / N
				var a1 := TAU * (i + 1) / N
				var q := [_rev(prof[k], a0, side), _rev(prof[k + 1], a0, side), _rev(prof[k + 1], a1, side), _rev(prof[k], a1, side)]
				var am := (a0 + a1) * 0.5
				_quad(st, q[0], q[1], q[2], q[3], Vector3(n.x * side, n.y * cos(am), n.y * sin(am)), _sw(sec[1]))
	# The rim's face (the skin's wheel picture) and the back of the wheel.
	st.set_smooth_group(0xFFFFFFFF)
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var c := Vector3(dish * side, 0, 0)
		var q0 := _rev(Vector2(dish, rr), a0, side)
		var q1 := _rev(Vector2(dish, rr), a1, side)
		_tri(st, [c, q0, q1], [_patch(RIM_RECT, 0.5, 0.5), _rim_uv(a0), _rim_uv(a1)], Vector3(side, 0, 0))
		var b0 := _rev(Vector2(-hx, rr), a0, side)
		var b1 := _rev(Vector2(-hx, rr), a1, side)
		_tri(st, [Vector3(-hx * side, 0, 0), b0, b1], [_sw(Sw.TRIM)], Vector3(-side, 0, 0))
	st.generate_normals()
	return st.commit()


static func _rev(q: Vector2, a: float, side: float) -> Vector3:
	return Vector3(q.x * side, q.y * cos(a), q.y * sin(a))


static func _rim_uv(a: float) -> Vector2:
	return _patch(RIM_RECT, 0.5 + 0.5 * sin(a), 0.5 - 0.5 * cos(a))


static func _mx(v: Vector3, side: float) -> Vector3:
	return Vector3(v.x * side, v.y, v.z)


static func _sw(i: int) -> Vector2:
	return Vector2(i * 24 + 12, 12) / SKIN


## UV at (`a`, `b`) across a skin patch (0..1 each, b down the picture), a texel in from its edge.
static func _patch(rect: Rect2i, a: float, b: float) -> Vector2:
	return (Vector2(rect.position) + Vector2(1, 1) + Vector2(a, b) * (Vector2(rect.size) - Vector2(2, 2))) / SKIN


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, uv: Vector2) -> void:
	_tri(st, [a, b, c], [uv], out)
	_tri(st, [a, c, d], [uv], out)


## One triangle facing `out`; `uv` holds one UV per corner, or a single one for all three.
static func _tri(st: SurfaceTool, v: Array, uv: Array, out: Vector3) -> void:
	var n: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
	if n.length_squared() < 1e-12:
		return
	# Godot's front faces wind clockwise: the right-hand normal points into the body.
	var order := [0, 2, 1] if n.dot(out) > 0.0 else [0, 1, 2]
	for k in order:
		st.set_uv(uv[k] if uv.size() == 3 else uv[0])
		st.add_vertex(v[k])


## An axis-aligned box in swatch `sw`; its face towards `face` z (+1 front, -1 back) can show
## a skin patch instead, mirrored with `flip`.
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, sw: int, rect := Rect2i(), face := 0.0, flip := false) -> void:
	var sg := 0xFFFFFFFF
	st.set_smooth_group(sg)
	for axis in 3:
		for s in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var w := n.cross(u)
			var fc := c + n * h
			var hu := u * h
			var hw := w * h
			var q := [fc - hu - hw, fc + hu - hw, fc + hu + hw, fc - hu + hw]
			if axis == 2 and s == face and rect.size != Vector2i.ZERO:
				var uvs := []
				for k in 4:
					# Seen from outside, +X is on the right from the front and on the left from behind.
					var a: float = (q[k].x - (c.x - h.x)) / (2.0 * h.x)
					if (face < 0.0) != flip:
						a = 1.0 - a
					uvs.append(_patch(rect, a, ((c.y + h.y) - q[k].y) / (2.0 * h.y)))
				_tri(st, [q[0], q[1], q[2]], [uvs[0], uvs[1], uvs[2]], n)
				_tri(st, [q[0], q[2], q[3]], [uvs[0], uvs[2], uvs[3]], n)
			else:
				_quad(st, q[0], q[1], q[2], q[3], n, _sw(sw))


# ------------------------------------------------------------------ skin

static func _skin(p: Dictionary) -> ImageTexture:
	var img := Image.create(SKIN, SKIN, false, Image.FORMAT_RGBA8)
	img.fill(Color8(34, 34, 36))
	var swatches := [Color8(128, 128, 128, 128), Color8(12, 14, 18, 128), Color8(26, 26, 28), Color8(200, 202, 206),
		Color8(150, 14, 12), Color8(230, 232, 236), Color8(34, 34, 36), Color8(220, 120, 20), Color8(20, 50, 200),
		Color8(225, 225, 222)]
	for i in swatches.size():
		img.fill_rect(Rect2i(i * 24, 0, 24, 24), swatches[i])
	_paint(img, HEAD_RECT, func(x: int, y: int) -> Color:
		if x < 2 or y < 2 or x > 61 or y > 29:
			return Color8(70, 72, 76)
		if x > 55:
			return Color8(225, 130, 30)
		for cx in [18, 42]:
			var d := Vector2(x - cx, y - 16).length()
			if d < 11.0:
				return Color8(245, 246, 250) if d < 7.0 else Color8(150, 155, 165)
		return Color8(195, 200, 212))
	var round_tails: bool = p.tails == "round"
	_paint(img, TAIL_RECT, func(x: int, y: int) -> Color:
		if x < 2 or y < 2 or x > 61 or y > 29:
			return Color8(40, 6, 6)
		if round_tails:
			for cx in [17, 45]:
				var d := Vector2(x - cx, y - 16).length()
				if d < 12.0:
					return Color8(215, 25, 20) if d < 8.0 else Color8(120, 10, 10)
			return Color8(30, 30, 32)
		if x < 12:
			return Color8(215, 215, 210)   # reversing lamp, inboard
		return Color8(205, 22, 18) if y % 6 < 3 else Color8(140, 12, 10))
	_paint(img, GRILLE_RECT, func(x: int, y: int) -> Color:
		if x < 2 or y < 2 or x > 61 or y > 29:
			return Color8(170, 172, 176)
		return Color8(55, 56, 58) if y % 5 < 2 else Color8(10, 10, 12))
	var plate := hash(p.name)
	_paint(img, PLATE_RECT, func(x: int, y: int) -> Color:
		if x < 2 or y < 2 or x > 61 or y > 29:
			return Color8(30, 40, 90)
		if y >= 9 and y <= 22 and x >= 6 and x <= 57 and (x - 6) % 8 < 6:
			# Characters: a few strokes per cell.
			var cell := (x - 6) / 8
			var bits := (plate >> (cell * 5)) | 0x11
			var col := ((x - 6) % 8) / 2
			var row := (y - 9) / 5
			if (bits >> ((col + row * 2) % 5)) & 1:
				return Color8(30, 30, 40)
		return Color8(235, 235, 225))
	var spokes: int = p.spokes
	var style: String = p.rim
	_paint(img, RIM_RECT, func(x: int, y: int) -> Color:
		var d := Vector2(x - 63.5, y - 63.5) / 64.0
		var rho := d.length()
		var th := atan2(d.y, d.x)
		if rho > 1.0:
			return Color8(34, 34, 36)
		if rho > 0.9:
			return Color8(215, 217, 222)
		if rho < 0.07:
			return Color8(120, 122, 128)
		if rho < 0.2:
			for k in 5:
				if (d - Vector2.from_angle(TAU * k / 5.0) * 0.13).length() < 0.03:
					return Color8(40, 40, 44)
			return Color8(185, 187, 192)
		var gap := Color8(22, 22, 24)
		if rho > 0.3 and rho < 0.82:
			gap = Color8(80, 80, 84)   # brake disc
			if th > 0.3 and th < 1.0 and rho > 0.55:
				gap = Color8(170, 25, 20)   # calliper
		var shade := 0.88 + 0.12 * cos(th + 0.8)
		var metal := Color8(200, 202, 208) * shade
		metal.a = 1.0
		var f := fposmod(th / TAU * spokes, 1.0)
		var off := minf(f, 1.0 - f)   # angular distance to the nearest spoke, in spokes
		if style == "steel":
			var steel := Color8(150, 150, 152) * shade
			steel.a = 1.0
			var hole := Vector2.from_angle((floorf(th / TAU * spokes + 0.5)) * TAU / spokes) * 0.6
			return gap if (d - hole).length() < 0.09 else steel
		if style == "hubcap":
			return Color8(40, 40, 44) if rho > 0.45 and rho < 0.8 and off < 0.12 else metal
		return metal if off < 0.12 + 0.14 * (1.0 - rho) * 5.0 / spokes else gap)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _paint(img: Image, rect: Rect2i, f: Callable) -> void:
	for y in rect.size.y:
		for x in rect.size.x:
			img.set_pixel(rect.position.x + x, rect.position.y + y, f.call(x, y))

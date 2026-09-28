class_name ProcPlaces
extends RefCounted
## The procedural lap's named places, so that what a sign says is really there: the town
## (its name on the welcome sign and the water tower, its hotel and bank, a painted sign
## over every shopfront), the gas station on the way out of it, a diner, a farm with a stand
## selling its corn, a campground in the state forest, the pass and the tunnel through it,
## the river and creeks under the bridges and a motel by the lake. Billboards before a place
## advertise it with the real distance and the side it's on, and the road signs name the
## forest, the pass, the river and the town as you reach them.
##
## The names come from the seed alone (names()), so the menu can call the track after its
## town without building it.

const Zone := ProceduralTrack.Zone
const Kind := ProceduralTrack.Kind
const STEP := ProceduralTrack.STEP
const MILE := 1609.0

const NATURE := ["Cedar", "Pine", "Willow", "Elk", "Bear", "Eagle", "Silver", "Crystal", "Maple",
	"Hawk", "Aspen", "Granite", "Juniper", "Timber", "Raven", "Coyote", "Laurel", "Copper", "Otter", "Sage"]
const SURNAMES := ["Hollis", "Mercer", "Dawson", "Whitaker", "Pruitt", "Calloway", "Beckett", "Harlan",
	"Tate", "Lomax", "Garrity", "Voss", "Kimball", "Sutter", "Rourke", "McCready"]
const STREETS := ["Elm St", "Oak St", "2nd St", "3rd St", "Mill St", "Park Ave", "School St", "Walnut St",
	"Depot St", "Spring St", "Court St", "Grove Ave"]
const FIRST := ["Rosie", "Mel", "Dot", "Lou", "Hank", "Earl", "Flo", "Vern", "June", "Ike"]
const BRANDS := [["EAGLE", Color(0.1, 0.3, 0.65)], ["ROADSTAR", Color(0.72, 0.1, 0.08)],
	["PIONEER", Color(0.1, 0.42, 0.25)], ["SUNRISE", Color(0.9, 0.42, 0.05)]]
const TRADES := ["BAKERY", "HARDWARE", "PHARMACY", "BARBER SHOP", "BOOKS", "RADIO & TV", "FLOWERS",
	"GENERAL STORE", "AUTO PARTS", "CAFE", "PIZZA", "LAUNDROMAT", "SHOES", "SPORTING GOODS",
	"ANTIQUES", "FIVE & DIME", "TAILOR", "HOBBY SHOP", "RECORDS", "DELI", "JEWELER", "CANDY"]
## Shop sign boards and the paint on them.
const BOARDS := [[Color(0.12, 0.28, 0.2), Color(0.95, 0.9, 0.75)], [Color(0.45, 0.1, 0.1), Color(0.98, 0.92, 0.78)],
	[Color(0.1, 0.16, 0.35), Color(0.95, 0.85, 0.45)], [Color(0.08, 0.08, 0.08), Color(0.95, 0.75, 0.3)],
	[Color(0.93, 0.9, 0.8), Color(0.15, 0.15, 0.15)]]
const AWNINGS := [Color(0.7, 0.15, 0.12), Color(0.15, 0.4, 0.25), Color(0.18, 0.3, 0.6),
	Color(0.85, 0.6, 0.15), Color(0.4, 0.4, 0.42), Color(0.9, 0.88, 0.82)]
const GREEN := Color(0.05, 0.36, 0.18)    # guide signs
const BROWN := Color(0.46, 0.28, 0.13)    # recreation signs
const CREAM := Color(0.96, 0.95, 0.9)
const STEEL := Color(0.55, 0.56, 0.58)
const PLYWOOD := Color(0.86, 0.76, 0.56)

var sc: ProcScenery
var lay: ProceduralTrack.Layout
var root: Node3D
var rng := RandomNumberGenerator.new()
var nm: Dictionary
var road_font: Font
var ad_font: Font
## Where each place stands, [node, side]: what the billboards point to.
var at := {}
var _trades: Array = []
var _shops := 0
var _blocks := 0
var _diamond: StandardMaterial3D
var _names := {}      # branch index -> its name
var _reach := 1.0     # of the lettering's draw distance, by quality preset (each label is a draw)


## The names of everything on the lap for this seed.
static func names(seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 13 + 3
	var nat := _shuffled(NATURE, r)
	var sur := _shuffled(SURNAMES, r)
	# The town is as often as not named for its river.
	var town: String = [nat[0] + " Falls", nat[0] + " Crossing", sur[0] + "ville", "Fort " + sur[0],
		nat[4] + " Springs"][r.randi() % 5]
	var brand: Array = BRANDS[r.randi() % BRANDS.size()]
	return {
		"town": town, "river": nat[0] + " River", "lake": nat[1] + " Lake", "pass": nat[2] + " Pass",
		"tunnel": nat[2] + " Tunnel", "forest": nat[3] + " State Forest", "camp": nat[3] + " Campground",
		"creeks": [nat[5] + " Creek", sur[3] + " Creek"], "farm": sur[1], "surname": sur[2],
		"diner": FIRST[r.randi() % FIRST.size()] + "'s Diner", "motel": nat[1] + " Lake Motel",
		"hotel": "Hotel " + town, "bank": town + " Savings Bank", "brand": brand[0], "brand_c": brand[1],
		"pop": r.randi_range(9, 60) * 100 + r.randi_range(0, 99), "est": r.randi_range(1851, 1908),
		"bored": r.randi_range(1929, 1958),
		# The lap is Main Street through the town and a state route beyond it.
		"route": r.randi_range(11, 96), "mile0": r.randi_range(12, 70), "church_st": "Church St",
		"streets": _shuffled(STREETS, r), "church": ["First Baptist Church", "Community Church",
			"St. " + ["Mary's", "Paul's", "John's"][r.randi() % 3] + " Church"][r.randi() % 3],
	}


static func _shuffled(a: Array, r: RandomNumberGenerator) -> Array:
	var out := a.duplicate()
	for k in range(out.size() - 1, 0, -1):
		var j := r.randi_range(0, k)
		var t: Variant = out[k]
		out[k] = out[j]
		out[j] = t
	return out


## Lays out the places (before the rest of the scenery, which keeps off them).
static func build(p_sc: ProcScenery, seed_value: int) -> ProcPlaces:
	var p := ProcPlaces.new()
	p.sc = p_sc
	p.lay = p_sc.lay
	p.root = p_sc.root
	p.rng.seed = seed_value * 17 + 11
	p._reach = [0.5, 0.75, 1.0][clampi(Game.quality, 0, 2)]
	p.nm = names(seed_value)
	p.road_font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	p.ad_font = load("res://fonts/BarlowCondensed-BoldItalic.ttf")
	p._trades = _shuffled(TRADES, p.rng)
	p._trades.insert(2, "POST OFFICE")
	p._diamond = ProcScenery._sign_mat(_diamond_image())
	p._name_branches()
	p._town_signs()
	p._water_tower()
	p._gas_station()
	p._diner()
	p._farm()
	p._forest()
	p._pass()
	p._bridges()
	p._motel()
	p._side_roads()
	return p


# --- The roads off the lap ------------------------------------------------------------------

## Street names in the order the lap meets them (both halves of a crossroads the same, the
## second one Church Street), a family's name for each farm lane, forest road numbers.
func _name_branches() -> void:
	var by_node := {}
	var streets: Array = nm.streets
	var k := 0
	for bi in lay.branches.size():
		var b := lay.branches[bi]
		match b.kind:
			"street":
				if not by_node.has(b.from):
					by_node[b.from] = nm.church_st if by_node.size() == 1 else streets[k % streets.size()]
					if by_node.size() != 2:
						k += 1
				_names[bi] = by_node[b.from]
			"lane":
				_names[bi] = SURNAMES[rng.randi() % SURNAMES.size()] + " Rd"
			"forest":
				_names[bi] = "Forest Rd %d" % rng.randi_range(101, 399)
			"camp":
				_names[bi] = nm.camp
			_:
				_names[bi] = ""


func branch_name(bi: int) -> String:
	return _names.get(bi, "")


# --- Finding room ----------------------------------------------------------------------------

## The nodes of stretch `z` in lap order from where it starts (the town's run wraps round).
func _stretch(z: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in lay.n:
		if lay.zone[i] == z and lay.zone[lay.idx(i - 1)] != z:
			var j := i
			while lay.zone[j] == z and out.size() < lay.n:
				out.append(j)
				j = lay.idx(j + 1)
			break
	return out


func _wall(i: int, s: float) -> float:
	return lay.wall_r[i] if s > 0.0 else lay.wall_l[i]


## A site `half` m (along, across) each way round the point `d` m out to side `s` of node
## `i`, clear of the road and the other places and near enough level: [lowest, highest]
## ground under it, or [].
func _site(i: int, s: float, d: float, half: Vector2, spread: float) -> Array:
	if not sc._clear(sc._beside(i, s, d), half.y, 10.0):
		return []
	# Near the road's level, not up a cutting or down a bank.
	if absf(sc._beside(i, s, d - half.y).y - lay.pts[i].y) > 2.5:
		return []
	var lo := INF
	var hi := -INF
	for a: float in [-1.0, 0.0, 1.0]:
		for c: float in [-1.0, 0.0, 1.0]:
			var p := sc._beside(i, s, d + c * half.y, a * half.x)
			if c < 0.0 and not sc._clear(p, 0.5, 10.0):
				return []
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return [lo, hi] if hi - lo <= spread else []


## The first site along `nodes` (fractions `from`..`to` of them), either side, the size of
## `half` with its near edge `gap` m past the road's wall, whose ground varies by no more than
## `spread` m (failing that, the most level one within twice that): [node, side, centre,
## low, high].
func _find(nodes: PackedInt32Array, from: float, to: float, gap: float, half: Vector2, spread: float) -> Array:
	var s0 := 1.0 if rng.randf() < 0.5 else -1.0
	var best := []
	for k in range(int(from * nodes.size()), int(to * nodes.size())):
		var i := nodes[k]
		if lay.kind[i] != Kind.OPEN or absf(lay.curv[i]) > 1.0 / 100.0:
			continue
		for s: float in [s0, -s0]:
			var d := _wall(i, s) + gap + half.y
			var site := _site(i, s, d, half, spread * 2.0)
			if site.is_empty():
				continue
			var f := [i, s, sc._beside(i, s, d), site[0], site[1]]
			if site[1] - site[0] <= spread:
				return f
			if best.is_empty() or site[1] - site[0] < best[4] - best[3]:
				best = f
	return best


func _no_fence(i: int, s: float, span: int) -> void:
	for k in range(-span, span + 1):
		sc.no_fence[lay.idx(i + k) * 2 + int(s > 0.0)] = true


## How far on from node `from` to node `to`, and which side, as a sign would put it.
func _how_far(from: int, to: int, s: float) -> String:
	var m := float(lay.idx(to - from)) * STEP
	var side := "ON RIGHT" if s > 0.0 else "ON LEFT"
	if m < 0.2 * MILE:
		return "NEXT RIGHT" if s > 0.0 else "NEXT LEFT"
	var q := roundi(m / MILE * 4.0)
	if q < 4:
		return "%s MILE  ·  %s" % [["1/4", "1/4", "1/2", "3/4"][q], side]
	var halves := roundi(m / MILE * 2.0)
	return "%d%s MI  ·  %s" % [halves / 2, " 1/2" if halves % 2 == 1 else "", side]


static func _thousands(v: int) -> String:
	var t := str(v)
	return t if t.length() <= 3 else t.substr(0, t.length() - 3) + "," + t.substr(t.length() - 3)


# --- Building blocks -------------------------------------------------------------------------

func _holder(xf: Transform3D) -> Node3D:
	var h := Node3D.new()
	h.transform = xf
	root.add_child(h)
	return h


static func _bx(size: Vector3, pos: Vector3, c: Color) -> Array:
	return [ProcScenery._box(size), pos, c]


## Painted primitives [mesh, offset (Vector3 or Transform3D), colour] as one mesh on `parent`.
func _parts(parent: Node3D, parts: Array, draw_range := 500.0, shadow := true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var xf: Transform3D = part[1] if part[1] is Transform3D else Transform3D(Basis(), part[1])
		ProcScenery._append(st, part[0], xf, part[2])
	st.set_material(sc._paint)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.visibility_range_end = draw_range
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A level lot `half` m each way at the holder's origin, on fill: its sides slope down
## `drop` m to the ground at 45 degrees. Solid ground a car can drive onto.
func _pad(h: Node3D, half: Vector2, drop: float, top_c: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := [Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, -half.y)]
	var b := []
	for v: Vector3 in t:
		b.append(Vector3(v.x + signf(v.x) * drop, -drop, v.z + signf(v.z) * drop))
	var faces := PackedVector3Array()
	var quad := func(q: Array, c: Color) -> void:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_normal(n)
			st.set_uv(Vector2(q[k].x, q[k].z) * 0.25)
			st.add_vertex(q[k])
			faces.append(h.transform * q[k])
	quad.call([t[0], t[1], t[2], t[3]], top_c)
	var bank := Color(0.3, 0.42, 0.16)
	for k in 4:
		quad.call([b[k], b[(k + 1) % 4], t[(k + 1) % 4], t[k]], bank)
	st.set_material(sc.plain_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.visibility_range_end = 700.0
	h.add_child(mi)
	var body := root.get_node_or_null("Lots") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "Lots"
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func _solid(xf: Transform3D, size: Vector3, pos: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var o := sc._body.create_shape_owner(sc._body)
	sc._body.shape_owner_add_shape(o, b)
	sc._body.shape_owner_set_transform(o, xf * Transform3D(Basis(), pos))


## Lettering `h` m tall (capitals) at `pos` on `parent`, facing its +Z turned `rot_y`.
## Neon lettering is unshaded, so it glows at night.
func _text(parent: Node3D, t: String, pos: Vector3, h: float, c: Color, font: Font, neon := false,
		draw_range := 350.0, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font = font
	l.font_size = 64
	l.pixel_size = h / (64.0 * 0.7)
	l.modulate = c
	l.outline_size = 0
	l.double_sided = false
	l.shaded = not neon
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.rotation.y = rot_y
	l.visibility_range_end = draw_range * _reach
	parent.add_child(l)
	return l


## Lines [text, capital height] stacked down a `size` board centred at `c`, each shrunk to fit
## its width.
func _lines(parent: Node3D, c: Vector3, size: Vector2, lines: Array, fg: Color, font: Font,
		neon := false, draw_range := 350.0) -> void:
	var total := 0.0
	for l: Array in lines:
		total += l[1] * 1.45
	var y := c.y + total * 0.5
	for l: Array in lines:
		var t: String = l[0]
		# Condensed capitals run about 0.6 of their height wide.
		var h := minf(l[1], size.x * 0.88 / maxf(t.length() * 0.6, 1.0))
		y -= l[1] * 0.725
		_text(parent, t, Vector3(c.x, y, c.z), h, fg, font, neon, draw_range)
		y -= l[1] * 0.725


## A `size` board centred at `c` on `parent`, facing its +Z, in `bg` with a `border`
## (transparent: none) and lettering in `fg`.
func _panel(parent: Node3D, c: Vector3, size: Vector2, bg: Color, fg: Color, lines: Array, font: Font,
		neon := false, border := Color(0, 0, 0, 0), draw_range := 350.0) -> void:
	var parts := [_bx(Vector3(size.x, size.y, 0.1), c, bg)]
	if border.a > 0.0:
		parts.append(_bx(Vector3(size.x + 0.2, size.y + 0.2, 0.08), c - Vector3(0, 0, 0.02), border))
	_parts(parent, parts, draw_range + 150.0, false)
	_lines(parent, c + Vector3(0, 0, 0.07), size, lines, fg, font, neon, draw_range)


## A road sign on two posts beside node `i` (or the first open node on from it, going `dir`),
## facing the traffic coming up to it: a `size` board in `bg`, bordered and lettered in `fg`.
func _road_sign(i: int, s: float, size: Vector2, bg: Color, fg: Color, lines: Array, low := 1.5, dir := 1) -> int:
	for k in 16:
		var j := lay.idx(i + k * dir)
		if lay.kind[j] != Kind.OPEN:
			continue
		var p := sc._beside(j, s, _wall(j, s) + 1.2 + size.x * 0.5)
		if not sc._clear(p, 0.5, 10.0):
			continue
		_no_fence(j, s, 2)
		var face := (-lay.fwd[j] - lay.flat_right[j] * s * 0.2).normalized()
		var h := _holder(ProcScenery._upright(p, face))
		var top := low + size.y
		var parts := []
		for x: float in [-size.x * 0.3, size.x * 0.3]:
			parts.append(_bx(Vector3(0.1, top + 0.4, 0.1), Vector3(x, top * 0.5 - 0.3, -0.12), STEEL))
			_solid(h.transform, Vector3(0.14, 2.4, 0.14), Vector3(x, 1.0, -0.12))
		_parts(h, parts, 400.0, false)
		_panel(h, Vector3(0, low + size.y * 0.5, 0), size, bg, fg, lines, road_font, false, fg, 400.0)
		return j
	return -1


## A yellow diamond warning sign on the right, lettered in black.
func _warning(i: int, lines: Array) -> void:
	for k in 16:
		var j := lay.idx(i + k)
		if lay.kind[j] != Kind.OPEN:
			continue
		var p := sc._beside(j, 1.0, lay.wall_r[j] + 1.2)
		if not sc._clear(p, 0.3, 10.0):
			continue
		var xf := ProcScenery._upright(p, -lay.fwd[j])
		sc._put("sign_post", xf)
		var h := _holder(xf)
		var mi := MeshInstance3D.new()
		mi.mesh = ProcScenery._board(Vector2(1.2, 1.2), 1.75, _diamond, true)
		mi.visibility_range_end = 350.0
		h.add_child(mi)
		_lines(h, Vector3(0, 1.75 + 1.2 * 0.7, 0.09), Vector2(1.15, 1.0), lines, Color(0.05, 0.05, 0.05), road_font)
		return


## A hand-painted plywood sign on one post, just off the road.
func _hand_sign(i: int, s: float, lines: Array) -> void:
	for k in 12:
		var j := lay.idx(i + k)
		var p := sc._beside(j, s, _wall(j, s) + 2.0)
		if lay.kind[j] != Kind.OPEN or not sc._clear(p, 0.4, 10.0):
			continue
		var face := (-lay.fwd[j] - lay.flat_right[j] * s * 0.4).normalized()
		var h := _holder(ProcScenery._upright(p + Vector3.DOWN * 0.1, face))
		_parts(h, [_bx(Vector3(0.12, 2.2, 0.12), Vector3(0, 1.0, -0.1), Color(0.4, 0.3, 0.2))], 300.0, false)
		_panel(h, Vector3(0, 1.55, 0), Vector2(2.2, 1.1), PLYWOOD, Color(0.55, 0.08, 0.06), lines, ad_font)
		return


static func _diamond_image() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.78, 0.1))
	for y in 64:
		for x in 64:
			if absf(x - 31.5) > 28.0 or absf(y - 31.5) > 28.0:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.05))
	return img


# --- Town ------------------------------------------------------------------------------------

func _town_signs() -> void:
	var town := _stretch(Zone.TOWN)
	if town.is_empty():
		return
	var up: String = nm.town.to_upper()
	var ink := Color(0.08, 0.28, 0.16)
	_road_sign(lay.idx(town[0] - 6), 1.0, Vector2(5.0, 2.5), CREAM, ink, [["WELCOME TO", 0.3], [up, 0.72],
		["EST. %d   ·   POP. %s" % [nm.est, _thousands(nm.pop)], 0.26]], 1.2, -1)
	_road_sign(town[town.size() - 1], 1.0, Vector2(4.4, 1.5), GREEN, CREAM, [["LEAVING " + up, 0.4],
		["COME BACK SOON", 0.26]])


## A water tower over the roofs with the town's name round its tank.
func _water_tower() -> void:
	var town := _stretch(Zone.TOWN)
	for k in range(int(town.size() * 0.3), town.size()):
		var i := town[k]
		for s: float in [1.0, -1.0]:
			var p := sc._beside(i, s, _wall(i, s) + 38.0)
			if not sc._clear(p, 7.0, 0.7):
				continue
			sc.keep_out(p, 7.0)
			# Its name turned to the traffic coming into town.
			var h := _holder(ProcScenery._upright(p, (-lay.flat_right[i] * s - lay.fwd[i] * 0.6).normalized()))
			var leg := Color(0.62, 0.64, 0.67)
			var tank := Color(0.85, 0.88, 0.9)
			var parts := []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				parts.append([ProcScenery._cyl(0.22, 0.28, 19.0, 6), Vector3(c.x * 2.8, 9.0, c.y * 2.8), leg])
				_solid(h.transform, Vector3(0.6, 18.0, 0.6), Vector3(c.x * 2.8, 9.0, c.y * 2.8))
			for y: float in [6.0, 12.0]:
				parts.append(_bx(Vector3(5.8, 0.15, 0.15), Vector3(0, y, 2.8), leg))
				parts.append(_bx(Vector3(5.8, 0.15, 0.15), Vector3(0, y, -2.8), leg))
				parts.append(_bx(Vector3(0.15, 0.15, 5.8), Vector3(2.8, y, 0), leg))
				parts.append(_bx(Vector3(0.15, 0.15, 5.8), Vector3(-2.8, y, 0), leg))
			parts.append([ProcScenery._cyl(4.3, 4.3, 5.6, 16), Vector3(0, 21.3, 0), tank])
			parts.append([ProcScenery._cyl(0.3, 4.6, 2.2, 16), Vector3(0, 25.2, 0), Color(0.6, 0.63, 0.67)])
			parts.append([ProcScenery._cyl(4.35, 4.35, 0.4, 16), Vector3(0, 18.7, 0), leg])
			_parts(h, parts, 1500.0)
			var words: PackedStringArray = nm.town.to_upper().split(" ")
			var lines := [[" ".join(words), 1.5]] if words.size() == 1 else [[words[0], 1.3], [" ".join(words.slice(1)), 1.3]]
			_lines(h, Vector3(0, 21.3, 4.32), Vector2(5.4, 4.0), lines, Color(0.12, 0.2, 0.4), road_font, false, 1500.0)
			return


## Shopfronts get an awning and a sign; the first two big blocks are the hotel and the bank,
## the rest have shops under their flats.
func dress(kind: String, xf: Transform3D, i: int, s: float) -> void:
	if kind == "block":
		_blocks += 1
		if _blocks <= 2:
			_landmark_block(xf, i, s)
			return
		xf = xf.translated_local(Vector3(0, 0, 1.0))   # its front is a metre further out
	elif kind != "shop":
		return
	var trade: String = _trades[_shops % _trades.size()]
	_shops += 1
	var b: Array = BOARDS[rng.randi() % BOARDS.size()]
	sc._put("awning", xf, AWNINGS[rng.randi() % AWNINGS.size()])
	sc._put("shop_sign", xf, b[0])
	var t := trade
	if trade == "POST OFFICE":
		t = "U.S. POST OFFICE"
	elif rng.randf() < 0.4:
		t = "%s'S %s" % [SURNAMES[rng.randi() % SURNAMES.size()].to_upper(), trade]
	var h := _holder(xf)
	_lines(h, Vector3(0, 3.8, 5.12), Vector2(8.2, 0.9), [[t, 0.56]], b[1], road_font, false, 300.0)


func _landmark_block(xf: Transform3D, i: int, s: float) -> void:
	var h := _holder(xf)
	if _blocks == 1:
		# A blade sign out over the pavement, read from up and down the street.
		var red := Color(0.35, 0.05, 0.06)
		_parts(h, [_bx(Vector3(0.3, 6.0, 1.5), Vector3(4.6, 6.6, 6.8), red),
			_bx(Vector3(4.2, 0.25, 2.4), Vector3(0, 3.2, 7.2), red),
			_bx(Vector3(0.1, 3.2, 0.1), Vector3(-1.9, 1.6, 8.3), STEEL),
			_bx(Vector3(0.1, 3.2, 0.1), Vector3(1.9, 1.6, 8.3), STEEL)], 700.0)
		for side: float in [1.0, -1.0]:
			var l := _text(h, "H\nO\nT\nE\nL", Vector3(4.6 + side * 0.17, 6.6, 6.8), 0.62, Color(1.0, 0.82, 0.35),
				ad_font, true, 600.0, side * PI * 0.5)
			l.line_spacing = -14.0
		_panel(h, Vector3(0, 4.1, 6.1), Vector2(8.5, 0.8), red, Color(1.0, 0.85, 0.45), [[nm.hotel.to_upper(), 0.48]],
			road_font)
		at["hotel"] = [i, s]
	else:
		_panel(h, Vector3(0, 3.7, 6.1), Vector2(10.5, 0.85), Color(0.86, 0.84, 0.78), Color(0.12, 0.17, 0.3),
			[[nm.bank.to_upper(), 0.5]], road_font)


## A gas station on the way out of town: a canopy over the pumps, a kiosk behind and a price
## sign by the road.
func _gas_station() -> void:
	var town := _stretch(Zone.TOWN)
	var half := Vector2(11.0, 8.5)
	var f := _find(town, 0.72, 0.95, 4.0, half, 2.5)
	if f.is_empty():
		return
	var i: int = f[0]
	var s: float = f[1]
	var c: Vector3 = f[2]
	sc.keep_out(c, 16.0)
	var xf := ProcScenery._upright(Vector3(c.x, f[4] + 0.04, c.z), -lay.flat_right[i] * s)
	var h := _holder(xf)
	var drop: float = f[4] - f[3] + 0.5
	var brand: Color = nm.brand_c
	var white := Color(0.93, 0.93, 0.92)
	_pad(h, half, drop, Color(0.62, 0.62, 0.6))
	var parts := [_bx(Vector3(14.0, 0.3, 8.0), Vector3(0, 5.85, 2.5), white),
		_bx(Vector3(14.3, 0.7, 8.3), Vector3(0, 5.4, 2.5), brand)]
	for x: float in [-5.5, 5.5]:
		for z: float in [0.0, 5.0]:
			parts.append(_bx(Vector3(0.35, 5.1, 0.35), Vector3(x, 2.55, z), white))
			_solid(xf, Vector3(0.35, 5.1, 0.35), Vector3(x, 2.55, z))
	for x: float in [-2.6, 2.6]:
		parts.append(_bx(Vector3(1.2, 0.2, 5.0), Vector3(x, 0.1, 2.5), Color(0.7, 0.7, 0.68)))
		_solid(xf, Vector3(1.2, 1.9, 5.0), Vector3(x, 0.95, 2.5))
		for z: float in [1.3, 3.7]:
			parts.append(_bx(Vector3(0.7, 1.6, 0.9), Vector3(x, 1.0, z), brand))
			parts.append(_bx(Vector3(0.72, 0.3, 0.92), Vector3(x, 1.7, z), white))
	# The price sign on its pole at the corner the traffic comes from, turned to it.
	var pole := Transform3D(Basis(Vector3.UP, s * PI * 0.25), Vector3(s * 10.5, 0, 8.0))
	parts.append(_bx(Vector3(0.35, 7.5, 0.35), pole * Vector3(0, 3.5, -0.2), STEEL))
	_solid(xf, Vector3(0.4, 7.0, 0.4), pole * Vector3(0, 3.5, -0.2))
	_parts(h, parts, 700.0)
	for z: float in [6.66, -1.66]:
		_text(h, nm.brand, Vector3(0, 5.4, z), 0.45, white, ad_font, true, 400.0, 0.0 if z > 0.0 else PI)
	sc._put("kiosk", xf.translated_local(Vector3(0, -0.3, -5.5)), CREAM)
	_panel(h, Vector3(0, 2.95, -1.9), Vector2(5.0, 0.7), brand, white, [["FOOD MART", 0.42]], road_font)
	var sign := Node3D.new()
	sign.transform = pole
	h.add_child(sign)
	_panel(sign, Vector3(0, 6.2, 0), Vector2(3.0, 2.6), brand, white, [[nm.brand, 0.6], ["REGULAR   1.09", 0.3],
		["SUPER   1.29", 0.3]], ad_font, true, white, 500.0)
	at["gas"] = [i, s]


# --- Out of town -----------------------------------------------------------------------------

## A chrome diner out on the farm road with its lot, its name on a pole and DINER on the roof.
func _diner() -> void:
	var farm := _stretch(Zone.FARM)
	var half := Vector2(12.5, 10.0)
	var f := _find(farm, 0.04, 0.4, 4.0, half, 2.5)
	if f.is_empty():
		return
	var i: int = f[0]
	var s: float = f[1]
	var c: Vector3 = f[2]
	sc.keep_out(c, 17.0)
	_no_fence(i, s, 3)
	var xf := ProcScenery._upright(Vector3(c.x, f[4] + 0.04, c.z), -lay.flat_right[i] * s)
	var h := _holder(xf)
	var drop: float = f[4] - f[3] + 0.5
	sc._put("diner", xf.translated_local(Vector3(0, -0.3, -5.5)), Color(0.86, 0.88, 0.9))
	var red := Color(0.7, 0.1, 0.1)
	var pole := Transform3D(Basis(Vector3.UP, s * PI * 0.25), Vector3(s * 11.0, 0, 9.5))
	_pad(h, half, drop, Color(0.3, 0.3, 0.32))
	var parts := [_bx(Vector3(17.2, 0.35, 9.2), Vector3(0, 3.35, -5.5), red),
		_bx(Vector3(0.15, 1.5, 0.15), Vector3(-s * 3.5 - 3.0, 4.6, -3.0), STEEL),
		_bx(Vector3(0.15, 1.5, 0.15), Vector3(-s * 3.5 + 3.0, 4.6, -3.0), STEEL),
		_bx(Vector3(0.3, 8.5, 0.3), pole * Vector3(0, 4.0, -0.2), STEEL)]
	_solid(xf, Vector3(0.35, 8.0, 0.35), pole * Vector3(0, 4.0, -0.2))
	_parts(h, parts, 700.0)
	# On the roof's far end, clear of the pole seen from up the road.
	_panel(h, Vector3(-s * 3.5, 5.6, -3.0), Vector2(7.0, 1.6), Color(0.08, 0.08, 0.1), red, [["DINER", 1.1]], ad_font, true,
		Color(0, 0, 0, 0), 700.0)
	var sign := Node3D.new()
	sign.transform = pole
	h.add_child(sign)
	_panel(sign, Vector3(0, 7.4, 0), Vector2(4.6, 1.6), CREAM, red, [[nm.diner.to_upper(), 0.7]], ad_font, false,
		red, 500.0)
	_panel(sign, Vector3(0, 5.8, 0), Vector2(2.4, 1.1), Color(0.08, 0.08, 0.1), Color(1.0, 0.25, 0.2),
		[["EAT", 0.75]], ad_font, true, Color(0, 0, 0, 0), 500.0)
	at["diner"] = [i, s]


## A named farm: the barn with the family's name painted on it, the house and silo, a stand
## at the road selling what the fields grow, a mailbox, and signs for the stand on the way.
func _farm() -> void:
	var farm := _stretch(Zone.FARM)
	var half := Vector2(20.0, 13.0)
	var f := _find(farm, 0.45, 0.9, 6.0, half, 3.5)
	if f.is_empty():
		return
	var i: int = f[0]
	var s: float = f[1]
	var d := _wall(i, s) + 6.0 + half.y
	var barn: Vector3 = f[2]
	sc.keep_out(barn, 23.0)
	var fxf := ProcScenery._upright(barn - Vector3(0, 0.4, 0), lay.fwd[i])
	sc._put("barn", fxf, Color(0.72, 0.22, 0.16))
	# Painted on the long wall facing the road.
	var name: String = nm.farm.to_upper() + " FARM"
	var hb := _holder(fxf)
	_text(hb, name, Vector3(s * 9.06, 3.3, 0), 0.9, CREAM, road_font, false, 500.0, s * PI * 0.5)
	_text(hb, "EST. %d" % rng.randi_range(1880, 1935), Vector3(s * 9.06, 2.1, 0), 0.42, CREAM, road_font, false,
		400.0, s * PI * 0.5)
	var house := sc._beside(i, s, d - 3.0, 26.0)
	sc._put("house", ProcScenery._upright(house - Vector3(0, 0.3, 0), -lay.flat_right[i] * s), Color(0.97, 0.95, 0.88))
	var silo := sc._beside(i, s, d + 6.0, -15.0)
	sc._put("silo", ProcScenery._upright(silo - Vector3(0, 0.3, 0), lay.fwd[i]))
	# The stand, just ahead of the farm gate.
	var j := lay.idx(i - 4)
	var p := sc._beside(j, s, _wall(j, s) + 4.5)
	sc.keep_out(p, 4.0)
	_no_fence(j, s, 6)
	var sxf := ProcScenery._upright(p - Vector3(0, 0.1, 0), (-lay.flat_right[j] * s - lay.fwd[j] * 0.3).normalized())
	var h := _holder(sxf)
	var wood := Color(0.55, 0.4, 0.26)
	var parts := [_bx(Vector3(4.2, 0.9, 1.2), Vector3(0, 0.45, 0.2), wood),
		[ProcScenery._box(Vector3(4.8, 0.08, 2.6)), Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 2.55, 0)), Color(0.35, 0.36, 0.3)]]
	for x: float in [-2.1, 2.1]:
		for z: float in [-1.0, 1.0]:
			parts.append(_bx(Vector3(0.12, 2.6, 0.12), Vector3(x, 1.25, z), wood))
	for k in 4:
		var crop: Color = [Color(0.85, 0.75, 0.25), Color(0.95, 0.55, 0.25), Color(0.75, 0.15, 0.1), Color(0.5, 0.65, 0.2)][k]
		parts.append(_bx(Vector3(0.8, 0.3, 0.6), Vector3(-1.5 + k, 1.05, 0.3), crop))
	_parts(h, parts, 400.0)
	_solid(sxf, Vector3(4.4, 1.0, 1.4), Vector3(0, 0.5, 0.2))
	_panel(h, Vector3(0, 0.5, 0.86), Vector2(3.6, 0.7), PLYWOOD, Color(0.55, 0.08, 0.06), [["SWEET CORN · PEACHES", 0.36]],
		ad_font)
	var mb := _holder(ProcScenery._upright(sc._beside(i, s, _wall(i, s) + 1.6), -lay.flat_right[i] * s))
	_parts(mb, [_bx(Vector3(0.1, 1.1, 0.1), Vector3(0, 0.55, 0), wood), _bx(Vector3(0.3, 0.3, 0.55), Vector3(0, 1.2, 0), Color(0.2, 0.2, 0.22))], 200.0, false)
	_text(mb, nm.farm.to_upper(), Vector3(0.16, 1.2, 0), 0.09, CREAM, road_font, false, 60.0, PI * 0.5)
	_text(mb, nm.farm.to_upper(), Vector3(-0.16, 1.2, 0), 0.09, CREAM, road_font, false, 60.0, -PI * 0.5)
	for back: float in [0.25 * MILE, 0.08 * MILE]:
		var k := lay.idx(j - int(back / STEP))
		_hand_sign(k, s, [["FRESH SWEET CORN", 0.3], [_how_far(k, j, s), 0.24]])
	at["farm"] = [j, s]


## The state forest's sign as it starts, a deer crossing, and a campground of cabins.
func _forest() -> void:
	var forest := _stretch(Zone.FOREST)
	if forest.is_empty():
		return
	_road_sign(forest[1], 1.0, Vector2(5.6, 1.5), BROWN, CREAM, [[nm.forest.to_upper(), 0.5]])
	_warning(forest[int(forest.size() * 0.2)], [["DEER", 0.22], ["XING", 0.22]])
	# The campground: cabins round a clearing at the end of its road.
	var camp: ProceduralTrack.Branch = null
	for b in lay.branches:
		if b.kind == "camp":
			camp = b
	if camp == null:
		return
	var i := camp.from
	var s := camp.side
	var end := camp.pts[camp.pts.size() - 1]
	var t := (end - camp.pts[camp.pts.size() - 3]).normalized()
	t.y = 0.0
	var r := t.cross(Vector3.UP).normalized()
	for o: Vector2 in [Vector2(-12.0, -2.0), Vector2(12.0, 2.0), Vector2(-9.0, 12.0), Vector2(9.0, 13.0), Vector2(0.0, 20.0)]:
		var p := end + r * o.x + t * o.y
		p.y = ProcGround.surface_y(lay, p.x, p.z)
		if sc._clear(p, 3.5, 0.5):
			sc._put("cabin", ProcScenery._upright(p - Vector3(0, 0.5, 0), (end - p).normalized()), Color(0.6, 0.42, 0.27))
			sc.keep_out(p, 4.0)
	sc.keep_out(end + t * 6.0, 9.0)
	var gate := _road_sign(lay.idx(i - 3), s, Vector2(4.6, 1.5), BROWN, CREAM,
		[[nm.camp.to_upper(), 0.42], ["TENTS  ·  CABINS  ·  RV", 0.26]], 1.0, -1)
	var ahead := lay.idx(i - int(0.4 * MILE / STEP))
	_road_sign(ahead, 1.0, Vector2(3.8, 1.3), BROWN, CREAM, [["CAMPGROUND", 0.4], [_how_far(ahead, i, s), 0.26]])
	at["camp"] = [gate if gate >= 0 else i, s]


## Falling rock on the way up, the pass's name and height at its summit, and the tunnel's name
## over its mouth, with a sign to put the lights on before it.
func _pass() -> void:
	var mtn := _stretch(Zone.MOUNTAIN)
	if mtn.is_empty():
		return
	_warning(mtn[3], [["FALLING", 0.2], ["ROCK", 0.2]])
	var top := -1
	for i in mtn:
		if lay.kind[i] == Kind.OPEN and (top < 0 or lay.pts[i].y > lay.pts[top].y):
			top = i
	var feet := roundi((2600.0 + lay.pts[top].y * 3.28) / 10.0) * 10
	_road_sign(top, 1.0, Vector2(4.4, 1.9), GREEN, CREAM, [[nm.pass.to_upper(), 0.52], ["ELEV %s FT" % _thousands(feet), 0.34]])
	for run: Array in ProceduralTrack._runs(lay.kind, Kind.TUNNEL):
		var a: int = run[0]
		_road_sign(lay.idx(a - 40), 1.0, Vector2(3.8, 1.5), GREEN, CREAM, [[nm.tunnel.to_upper(), 0.4],
			["TURN ON HEADLIGHTS", 0.26]])
		# Cut into the portal's face over the arch (see ProcGround._portal).
		var p := lay.pts[a] - lay.fwd[a] * 20.12 + lay.up[a] * (ProcGround.TUNNEL_WALL + ProcGround.TUNNEL_ROOF + 1.2)
		var h := _holder(ProcScenery._upright(p, -lay.fwd[a]))
		_text(h, nm.tunnel.to_upper(), Vector3(0, 0.3, 0), 0.6, Color(0.2, 0.2, 0.2), road_font, false, 500.0)
		_text(h, str(nm.bored), Vector3(0, -0.5, 0), 0.3, Color(0.2, 0.2, 0.2), road_font, false, 300.0)


## Each bridge's name before it: the river where it's the river, creeks otherwise.
func _bridges() -> void:
	var creek := 0
	for run: Array in ProceduralTrack._runs(lay.kind, Kind.BRIDGE):
		var mid := lay.idx(run[0] + run[1] / 2)
		var q := Vector2(lay.pts[mid].x, lay.pts[mid].z)
		var name: String
		if lay.river_on and q.distance_to(lay.river_p) < 150.0:
			name = nm.river
		else:
			name = nm.creeks[creek % 2]
			creek += 1
		_road_sign(lay.idx(run[0] - 4), 1.0, Vector2(3.6, 0.9), GREEN, CREAM, [[name.to_upper(), 0.44]], 1.4, -1)


## A motel by the lake: a row of rooms behind its lot and a neon sign on a pole.
func _motel() -> void:
	var lake := _stretch(Zone.LAKE)
	if lake.is_empty():
		return
	var half := Vector2(15.0, 10.0)
	var f := _find(lake, 0.66, 0.97, 4.0, half, 2.5)
	if f.is_empty() or f[4] - f[3] > 2.5:
		var g := _find(lake, 0.03, 0.66, 4.0, half, 2.5)
		if not g.is_empty() and (f.is_empty() or g[4] - g[3] < f[4] - f[3]):
			f = g
	if f.is_empty():
		return
	var i: int = f[0]
	var s: float = f[1]
	var c: Vector3 = f[2]
	sc.keep_out(c, 23.0)
	_no_fence(i, s, 4)
	var xf := ProcScenery._upright(Vector3(c.x, f[4] + 0.04, c.z), -lay.flat_right[i] * s)
	var h := _holder(xf)
	var drop: float = f[4] - f[3] + 0.5
	sc._put("motel", xf.translated_local(Vector3(0, -0.3, -6.0)), Color(0.98, 0.9, 0.78))
	var pole := Transform3D(Basis(Vector3.UP, s * PI * 0.25), Vector3(s * 13.5, 0, 8.5))
	_pad(h, half, drop, Color(0.3, 0.3, 0.32))
	_parts(h, [_bx(Vector3(0.35, 10.0, 0.35), pole * Vector3(0, 4.8, -0.25), STEEL)], 700.0)
	_solid(xf, Vector3(0.4, 9.5, 0.4), pole * Vector3(0, 4.8, -0.25))
	var sign := Node3D.new()
	sign.transform = pole
	h.add_child(sign)
	var teal := Color(0.08, 0.42, 0.45)
	var dark := Color(0.06, 0.06, 0.08)
	_panel(sign, Vector3(0, 8.7, 0), Vector2(5.0, 1.4), teal, CREAM, [[nm.lake.to_upper(), 0.7]], ad_font, false, CREAM, 600.0)
	_panel(sign, Vector3(0, 7.2, 0), Vector2(4.2, 1.3), dark, Color(1.0, 0.35, 0.55), [["MOTEL", 0.9]], ad_font, true,
		Color(0, 0, 0, 0), 600.0)
	_panel(sign, Vector3(0, 6.1, 0), Vector2(2.6, 0.6), dark, Color(1.0, 0.2, 0.15), [["VACANCY", 0.36]], road_font, true,
		Color(0, 0, 0, 0), 400.0)
	_panel(h, Vector3(-9.0, 2.75, -1.95), Vector2(2.4, 0.5), teal, CREAM, [["OFFICE", 0.3]], road_font)
	at["motel"] = [i, s]


# --- Along the side roads -------------------------------------------------------------------

## What the side roads lead to: houses along the town streets (a church on Church Street) and
## cars parked at the kerb, a farm at the end of each farm lane, the forest closing over the
## end of each forest road, a walled car park at the lookout.
func _side_roads() -> void:
	for bi in lay.branches.size():
		var b := lay.branches[bi]
		match b.kind:
			"street":
				_street(b, branch_name(bi) == nm.church_st)
			"lane":
				_lane_end(b)
			"forest":
				_road_end_trees(b)
			"lookout":
				_lookout(b)


## Point, direction on and to the right, `along` m along branch `b`.
func _frame(b: ProceduralTrack.Branch, along: float) -> Array:
	var a := ProcSigns._along(b, along)
	var t: Vector3 = a[1]
	return [a[0], t, t.cross(Vector3.UP).normalized()]


func _street(b: ProceduralTrack.Branch, church: bool) -> void:
	var total := (b.pts.size() - 1) * ProceduralTrack.BSTEP
	var church_side := 1.0 if rng.randf() < 0.5 else -1.0
	for side: float in [-1.0, 1.0]:
		var along := 26.0 + rng.randf_range(0.0, 6.0)
		while along < total - 12.0:
			var f := _frame(b, along)
			var p: Vector3 = f[0] + f[2] * side * (b.half + 11.0)
			p.y = ProcGround.surface_y(lay, p.x, p.z)
			if church and side == church_side and along > 30.0 and along < 70.0:
				var cp: Vector3 = f[0] + f[2] * side * (b.half + 17.0)
				cp.y = ProcGround.surface_y(lay, cp.x, cp.z)
				if sc._clear(cp, 10.0, 10.0):
					_church(cp, -f[2] * side, f[1])
					church = false
					along += 30.0
					continue
			if sc._clear(p, 4.5, 10.0):
				var tints := [Color(0.97, 0.95, 0.88), Color(0.85, 0.9, 0.95), Color(0.95, 0.88, 0.75), Color(0.88, 0.95, 0.85)]
				sc._put("house", ProcScenery._upright(p - Vector3(0, 0.3, 0), -f[2] * side), tints[rng.randi() % tints.size()])
				sc.keep_out(p, 5.0)
			along += rng.randf_range(13.0, 17.0)
	# A house closing the far end.
	var e := _frame(b, total)
	var q: Vector3 = e[0] + e[1] * 10.0
	q.y = ProcGround.surface_y(lay, q.x, q.z)
	if sc._clear(q, 4.5, 10.0):
		sc._put("house", ProcScenery._upright(q - Vector3(0, 0.3, 0), -e[1]), Color(0.95, 0.93, 0.85))
	# Cars at the kerb, mostly past the barricade.
	for k in rng.randi_range(2, 4):
		var along := rng.randf_range(b.closed + 8.0, total - 8.0) if k > 0 else rng.randf_range(18.0, b.closed - 8.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var f := _frame(b, along)
		var p: Vector3 = f[0] + f[2] * side * (b.half - 1.1)
		_park(p, f[1] * side)


## A parked car at `p` (its surface height is found), nose along `dir`.
func _park(p: Vector3, dir: Vector3) -> void:
	var colours := [Color(0.6, 0.1, 0.08), Color(0.1, 0.2, 0.45), Color(0.85, 0.85, 0.82), Color(0.15, 0.15, 0.16),
		Color(0.35, 0.4, 0.3), Color(0.7, 0.6, 0.35), Color(0.5, 0.52, 0.55)]
	var b := lay.branch_at(p.x, p.z)
	p.y = maxf(ProcGround.surface_y(lay, p.x, p.z), b.y if b.x < 20.0 else -INF)
	sc._put("parked_car", ProcScenery._upright(p, dir.rotated(Vector3.UP, rng.randf_range(-0.04, 0.04))),
		colours[rng.randi() % colours.size()])


## A white clapboard church with its steeple over the door, facing the street, and its board
## on the lawn.
func _church(p: Vector3, face: Vector3, along: Vector3) -> void:
	sc.keep_out(p, 12.0)
	var h := _holder(ProcScenery._upright(p - Vector3(0, 0.3, 0), face))
	var mesh := ProcScenery._house(Vector3(18, 6.0, 10), 4.5, sc.plain_mat, sc.plain_mat, Color(0.3, 0.32, 0.35), false)
	# The nave's ridge runs back from the street.
	var nave := MeshInstance3D.new()
	nave.mesh = mesh
	nave.rotation.y = PI * 0.5
	nave.visibility_range_end = 900.0
	h.add_child(nave)
	var white := Color(0.96, 0.95, 0.92)
	_parts(h, [_bx(Vector3(3.6, 11.0, 3.6), Vector3(0, 5.5, 9.6), white),
		_bx(Vector3(3.8, 0.3, 3.8), Vector3(0, 11.1, 9.6), Color(0.3, 0.32, 0.35)),
		[ProcScenery._cyl(0.0, 2.3, 7.0, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 14.7, 9.6)), Color(0.3, 0.32, 0.35)],
		_bx(Vector3(0.12, 1.4, 0.12), Vector3(0, 18.8, 9.6), Color(0.85, 0.75, 0.4)),
		_bx(Vector3(0.8, 0.12, 0.12), Vector3(0, 19.1, 9.6), Color(0.85, 0.75, 0.4)),
		_bx(Vector3(1.6, 2.6, 0.1), Vector3(0, 1.3, 11.42), Color(0.45, 0.28, 0.18)),
		_bx(Vector3(1.1, 1.6, 0.1), Vector3(0, 7.5, 11.42), Color(0.2, 0.25, 0.35))], 1200.0)
	for x: float in [-2.0, 2.0]:
		for z: float in [-5.0, 0.0, 5.0]:
			_parts(h, [_bx(Vector3(0.1, 2.4, 1.0), Vector3(x * 2.52, 3.0, z), Color(0.25, 0.3, 0.4))], 400.0, false)
	_solid(h.transform, Vector3(10, 6, 18), Vector3(0, 3, 0))
	_solid(h.transform, Vector3(3.6, 11, 3.6), Vector3(0, 5.5, 9.6))
	var bh := Node3D.new()
	bh.position = Vector3(4.5, 0, 14.5)
	h.add_child(bh)
	_parts(bh, [_bx(Vector3(0.12, 1.6, 0.12), Vector3(-1.1, 0.8, -0.1), Color(0.4, 0.3, 0.2)),
		_bx(Vector3(0.12, 1.6, 0.12), Vector3(1.1, 0.8, -0.1), Color(0.4, 0.3, 0.2))], 300.0, false)
	_panel(bh, Vector3(0, 1.45, 0), Vector2(2.6, 1.0), CREAM, Color(0.1, 0.1, 0.12),
		[[nm.church.to_upper(), 0.2], ["SUNDAY SERVICE 10 AM", 0.13], ["ALL WELCOME", 0.13]], road_font, false,
		Color(0.2, 0.2, 0.22), 200.0)


## A farm where a lane ends: the barn across its end, the farmhouse and a pickup by it.
func _lane_end(b: ProceduralTrack.Branch) -> void:
	var total := (b.pts.size() - 1) * ProceduralTrack.BSTEP
	var e := _frame(b, total)
	var end: Vector3 = e[0]
	var t: Vector3 = e[1]
	var r: Vector3 = e[2]
	var barn := end + t * 12.0
	barn.y = ProcGround.surface_y(lay, barn.x, barn.z)
	if sc._clear(barn, 9.0, 0.5):
		sc._put("barn", ProcScenery._upright(barn - Vector3(0, 0.4, 0), r), Color(0.72, 0.22, 0.16) if rng.randf() < 0.6
			else Color(0.85, 0.82, 0.76))
		sc.keep_out(barn, 11.0)
	var house := end + r * 14.0 - t * 2.0
	house.y = ProcGround.surface_y(lay, house.x, house.z)
	if sc._clear(house, 5.5, 0.5):
		sc._put("house", ProcScenery._upright(house - Vector3(0, 0.3, 0), -r), Color(0.97, 0.95, 0.88))
		sc.keep_out(house, 6.0)
	var silo := end - r * 12.0 + t * 8.0
	silo.y = ProcGround.surface_y(lay, silo.x, silo.z)
	if sc._clear(silo, 3.0, 10.0):
		sc._put("silo", ProcScenery._upright(silo - Vector3(0, 0.3, 0), t))
		sc.keep_out(silo, 3.5)
	_park(end - t * 3.0 + r * 1.0, t.rotated(Vector3.UP, 0.4))


## Trees closing over the end of a forest road, so it runs on out of sight.
func _road_end_trees(b: ProceduralTrack.Branch) -> void:
	var total := (b.pts.size() - 1) * ProceduralTrack.BSTEP
	var e := _frame(b, total)
	for k in 7:
		var p: Vector3 = e[0] + e[1] * rng.randf_range(2.0, 12.0) + e[2] * rng.randf_range(-6.0, 6.0)
		p.y = ProcGround.surface_y(lay, p.x, p.z) - 0.2
		sc._put("conifer", ProcScenery._upright(p, Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU),
			Vector3.ONE * rng.randf_range(0.9, 1.4)), Color(1, 1, 1) * rng.randf_range(0.85, 1.1))


## The lookout's car park: a stone wall along its edge over the view, coin telescopes, its sign
## and a couple of cars stopped to look.
func _lookout(b: ProceduralTrack.Branch) -> void:
	var total := (b.pts.size() - 1) * ProceduralTrack.BSTEP
	var e := _frame(b, total)
	var end: Vector3 = e[0]
	var t: Vector3 = e[1]
	var r: Vector3 = e[2]
	var w := b.half_at(total) + 1.0
	var h := _holder(ProcScenery._upright(end + t * 1.2, t))
	var stone := Color(0.55, 0.53, 0.5)
	_parts(h, [_bx(Vector3(w * 2.0, 1.2, 0.6), Vector3(0, 0.2, 0), stone),
		_bx(Vector3(0.6, 1.2, 6.0), Vector3(-w, 0.2, -3.0), stone), _bx(Vector3(0.6, 1.2, 6.0), Vector3(w, 0.2, -3.0), stone)],
		600.0)
	_solid(h.transform, Vector3(w * 2.0, 1.4, 0.6), Vector3(0, 0.2, 0))
	for x: float in [-2.5, 2.5]:
		_parts(h, [_bx(Vector3(0.12, 1.2, 0.12), Vector3(x, 0.6, -0.8), STEEL),
			[ProcScenery._cyl(0.14, 0.2, 0.6, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 1.35, -0.8)),
			Color(0.2, 0.35, 0.3)]], 200.0, false)
	for k in 2:
		_park(end - t * rng.randf_range(4.0, 7.0) + r * (k * 5.0 - 2.5), t)
	sc.keep_out(end, w + 4.0)
	_road_sign(lay.idx(b.from - 2), b.side, Vector2(3.2, 0.9), BROWN, CREAM, [["SCENIC VIEW", 0.42]], 1.4, -1)


# --- Billboards ------------------------------------------------------------------------------

## Billboards out in the country, each for a place further on, saying how far and which side.
func billboards() -> void:
	var ads := [
		["diner", nm.diner.to_upper(), "HOME COOKING  ·  PIE  ·  COFFEE", Color(0.72, 0.1, 0.1)],
		["motel", nm.motel.to_upper(), "VACANCY  ·  COLOR TV  ·  LAKE VIEWS", Color(0.08, 0.38, 0.42)],
		["gas", nm.brand + " GAS", "FOOD MART  ·  OPEN 24 HOURS", nm.brand_c],
		["hotel", nm.hotel.to_upper(), "IN THE HEART OF DOWNTOWN", Color(0.3, 0.08, 0.1)],
		["farm", "FRESH SWEET CORN", nm.farm.to_upper() + " FARM STAND", Color(0.2, 0.42, 0.15)],
	]
	var used: Array[int] = []
	for ad: Array in ads:
		if not at.has(ad[0]):
			continue
		var to: int = at[ad[0]][0]
		var side: float = at[ad[0]][1]
		var back := int(rng.randf_range(0.45, 1.4) * MILE / STEP)
		# From there on towards the place, the first good straight.
		for k in range(back, 50, -1):
			var i := lay.idx(to - k)
			var s := 1.0 if rng.randf() < 0.5 else -1.0
			if not _ad_spot(i, used):
				continue
			var p := sc._beside(i, s, _wall(i, s) + 9.0)
			if not sc._clear(p, 4.0, 0.6):
				continue
			used.append(i)
			_billboard(i, s, p, ad[1], ad[2], _how_far(i, to, side), ad[3])
			break


func _ad_spot(i: int, used: Array[int]) -> bool:
	if lay.zone[i] == Zone.TOWN or lay.kind[i] != Kind.OPEN or not sc._straight(i, 6):
		return false
	for u in used:
		if mini(lay.idx(u - i), lay.idx(i - u)) < 50:
			return false
	return true


func _billboard(i: int, s: float, p: Vector3, title: String, sub: String, how_far: String, bg: Color) -> void:
	var face := (-lay.fwd[i] - lay.flat_right[i] * s * 0.6).normalized()
	var xf := ProcScenery._upright(p, face)
	var h := _holder(xf)
	var wood := Color(0.35, 0.27, 0.2)
	var parts := []
	for x: float in [-3.0, 3.0]:
		parts.append(_bx(Vector3(0.3, 6.5, 0.3), Vector3(x, 3.0, -0.25), wood))
		_solid(xf, Vector3(0.3, 6.0, 0.3), Vector3(x, 3.0, -0.25))
	_parts(h, parts, 600.0)
	_panel(h, Vector3(0, 5.0, 0), Vector2(9.0, 3.6), bg, Color(1.0, 0.97, 0.88),
		[[title, 0.95], [sub, 0.4], [how_far, 0.55]], ad_font, false, Color(0.92, 0.9, 0.86), 450.0)

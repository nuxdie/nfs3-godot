class_name ProcSigns
extends RefCounted
## The procedural lap's traffic signs and road furniture, painted into one atlas (SignArt):
## speed limits for each stretch, warnings of side roads, hills, blind crests and bridges
## ahead, no-passing pennants where the double yellow starts, route shields, green guide
## signs giving the real distance to the places ahead, mile markers; and at each side road
## a stop sign, a street-name blade in town, and where it's closed, a barricade (a forest
## road's gate) with a ROAD CLOSED sign and cones.

const Zone := ProceduralTrack.Zone
const Kind := ProceduralTrack.Kind
const STEP := ProceduralTrack.STEP
const MILE := 1609.0
## The faces below are laid out in pixels at 80 per metre; K scales them to the atlas's.
const K := SignArt.PPM / 80.0
const LIMITS := {Zone.TOWN: 35, Zone.FARM: 55, Zone.FOREST: 45, Zone.MOUNTAIN: 40, Zone.LAKE: 50}

var sc: ProcScenery
var pl: ProcPlaces
var lay: ProceduralTrack.Layout
var art: SignArt
var rng := RandomNumberGenerator.new()


static func build(p_sc: ProcScenery, p_pl: ProcPlaces, seed_value: int) -> ProcSigns:
	var g := ProcSigns.new()
	g.sc = p_sc
	g.pl = p_pl
	g.lay = p_sc.lay
	g.art = SignArt.new(p_sc._body)
	g.rng.seed = seed_value * 41 + 3
	g._branch_furniture()
	g._speed_limits()
	g._junction_warnings()
	g._hills()
	g._no_passing()
	g._bridges()
	g._route_and_guides()
	g._mile_markers()
	return g


# --- Faces -----------------------------------------------------------------------------------

func _speed(v: int) -> Rect2:
	return art.face("speed%d" % v, Vector2(0.75, 0.95), func(img: Image) -> void:
		img.fill(SignArt.BLACK)
		SignArt.shape(img, "rect", 3.0 * K, SignArt.WHITE)
		art.text(img, "SPEED", Vector2(30, 15) * K, 9.0 * K, SignArt.BLACK)
		art.text(img, "LIMIT", Vector2(30, 28) * K, 9.0 * K, SignArt.BLACK)
		art.text(img, str(v), Vector2(30, 52) * K, 22.0 * K, SignArt.BLACK))


## A yellow diamond with lines of black lettering.
func _diamond(key: String, lines: Array) -> Rect2:
	return art.face("dia:" + key, Vector2(0.9, 0.9), func(img: Image) -> void:
		img.fill(Color(0, 0, 0, 0))
		SignArt.shape(img, "diamond", 0.0, SignArt.BLACK)
		SignArt.shape(img, "diamond", 3.0 * K, SignArt.YELLOW)
		var y := 36.0 - (lines.size() - 1) * 5.5
		for t: String in lines:
			art.text(img, t, Vector2(36, y) * K, (7.5 if lines.size() > 2 else 9.0) * K, SignArt.BLACK, 40.0 * K)
			y += 11.0)


## A side road ahead: a diamond with the road going up it and a branch off to `side`
## (-1 left, 1 right, 0 both).
func _junction(side: int) -> Rect2:
	return art.face("junction%d" % side, Vector2(0.9, 0.9), func(img: Image) -> void:
		img.fill(Color(0, 0, 0, 0))
		SignArt.shape(img, "diamond", 0.0, SignArt.BLACK)
		SignArt.shape(img, "diamond", 3.0 * K, SignArt.YELLOW)
		img.fill_rect(Rect2i(Vector2i(Vector2(32, 14) * K), Vector2i(Vector2(8, 44) * K)), SignArt.BLACK)
		if side >= 0:
			img.fill_rect(Rect2i(Vector2i(Vector2(36, 30) * K), Vector2i(Vector2(20, 8) * K)), SignArt.BLACK)
		if side <= 0:
			img.fill_rect(Rect2i(Vector2i(Vector2(16, 30) * K), Vector2i(Vector2(20, 8) * K)), SignArt.BLACK))


## A rectangular plate, `bg` bordered in `fg`, lines of `fg` lettering.
func _plate(key: String, size: Vector2, bg: Color, fg: Color, lines: Array, border := true) -> Rect2:
	return art.face("plate:" + key, size, func(img: Image) -> void:
		img.fill(fg if border else bg)
		SignArt.shape(img, "rect", 2.5 * K if border else 0.0, bg)
		var w := size.x * SignArt.PPM
		var h := size.y * SignArt.PPM
		var total := 0.0
		for l: Array in lines:
			total += l[1] * K * 1.5
		var y := (h - total) * 0.5
		for l: Array in lines:
			y += l[1] * K * 0.75
			art.text(img, l[0], Vector2(w * 0.5, y), l[1] * K, fg, w - 10.0 * K)
			y += l[1] * K * 0.75)


func _stop() -> Rect2:
	return art.face("stop", Vector2(0.75, 0.75), func(img: Image) -> void:
		img.fill(Color(0, 0, 0, 0))
		SignArt.shape(img, "octagon", 0.0, SignArt.WHITE)
		SignArt.shape(img, "octagon", 3.0 * K, SignArt.RED)
		art.text(img, "STOP", Vector2(30, 30) * K, 13.0 * K, SignArt.WHITE, 50.0 * K))


func _stop_back() -> Rect2:
	return art.face("stop_back", Vector2(0.75, 0.75), func(img: Image) -> void:
		img.fill(Color(0, 0, 0, 0))
		SignArt.shape(img, "octagon", 0.0, SignArt.METAL))


func _pennant() -> Rect2:
	return art.face("nopass", Vector2(1.2, 0.9), func(img: Image) -> void:
		img.fill(Color(0, 0, 0, 0))
		SignArt.shape(img, "pennant", 0.0, SignArt.BLACK)
		SignArt.shape(img, "pennant", 3.5 * K, SignArt.YELLOW)
		art.text(img, "NO", Vector2(28, 24) * K, 7.0 * K, SignArt.BLACK)
		art.text(img, "PASSING", Vector2(30, 36) * K, 7.0 * K, SignArt.BLACK, 40.0 * K)
		art.text(img, "ZONE", Vector2(28, 48) * K, 7.0 * K, SignArt.BLACK))


func _shield(num: int) -> Rect2:
	return art.face("route%d" % num, Vector2(0.75, 0.75), func(img: Image) -> void:
		img.fill(SignArt.BLACK)
		SignArt.shape(img, "shield", 4.0 * K, SignArt.WHITE)
		art.text(img, "STATE", Vector2(30, 15) * K, 6.0 * K, SignArt.BLACK)
		art.text(img, str(num), Vector2(30, 33) * K, 17.0 * K, SignArt.BLACK, 44.0 * K))


## A green guide sign: [place, distance] rows, names left, miles right.
func _guide(key: String, rows: Array) -> Rect2:
	var size := Vector2(4.4, 0.45 + rows.size() * 0.5)
	return art.face("guide:" + key, size, func(img: Image) -> void:
		img.fill(SignArt.WHITE)
		SignArt.shape(img, "rect", 3.0 * K, SignArt.GREEN)
		var w := size.x * SignArt.PPM
		var y := 0.45 * SignArt.PPM
		for r: Array in rows:
			var name: String = r[0]
			var dist: String = r[1]
			var cap := 20.0 * K
			var nw := minf(art._measure(name, int(cap / 0.7)), w * 0.7)
			art.text(img, name, Vector2(14.0 * K + nw * 0.5, y), cap, SignArt.WHITE, w * 0.7)
			var dw := art._measure(dist, int(cap / 0.7))
			art.text(img, dist, Vector2(w - 14.0 * K - dw * 0.5, y), cap, SignArt.WHITE)
			y += 0.5 * SignArt.PPM)


func _stripes() -> Rect2:
	return art.face("stripes", Vector2(1.8, 0.2), func(img: Image) -> void:
		img.fill(SignArt.WHITE)
		for x in img.get_width():
			for y in img.get_height():
				if posmod(x + y, int(24 * K)) < int(12 * K):
					img.set_pixel(x, y, SignArt.ORANGE))


func _colour(key: String, c: Color) -> Rect2:
	return art.face("c:" + key, Vector2(0.1, 0.1), func(img: Image) -> void: img.fill(c))


## Miles as a road sign puts them: 1/4, 1/2, 1, 1 1/2...
static func miles(m: float) -> String:
	var q := roundi(m / MILE * 4.0)
	if q < 4:
		return ["1/4", "1/4", "1/2", "3/4"][q]
	var halves := roundi(m / MILE * 2.0)
	return "%d%s" % [halves / 2, " 1/2" if halves % 2 == 1 else ""]


# --- Standing them up ------------------------------------------------------------------------

## Where a sign by the road goes, from node `i` on (or back, `dir` -1): the first open node
## with room for it: [node, ground point], or [].
func _spot(i: int, s0: float, dir := 1, room := 0.4) -> Array:
	# Near the road's level on its own side if it can be (not up a cutting or down a bank),
	# else on the other side, else on its own side whatever the ground.
	for pass_ in 3:
		var s := -s0 if pass_ == 1 else s0
		for k in 16:
			var j := lay.idx(i + k * dir)
			if lay.kind[j] != Kind.OPEN or (lay.gap_r if s > 0.0 else lay.gap_l)[j]:
				continue
			# Past the wall the AI keeps inside (TrackPath's widths), so no racer runs into it.
			var p := sc._beside(j, s, (lay.wall_r[j] if s > 0.0 else lay.wall_l[j]) + 0.6)
			if sc.kept(p, room) or lay.on_branch(p.x, p.z, room):
				continue
			if pass_ < 2 and absf(p.y - lay.pts[j].y) > 1.5:
				continue
			return [j, p, s]
	return []


## A post a car touching it within this of its foot knocks over (in its frame).
const POST_REACH := AABB(Vector3(-0.2, 0.0, -0.25), Vector3(0.4, 1.5, 0.5))


## A sign on a post beside the road at node `i`, facing the traffic: `boards` [uv, size]
## stacked down from `top` m. A car knocks it over.
func _post_sign(i: int, s: float, boards: Array, top := 2.6, dir := 1) -> int:
	var f := _spot(i, s, dir)
	if f.is_empty():
		return -1
	var j: int = f[0]
	s = f[2]
	var xf := ProcScenery._upright(f[1], (-lay.fwd[j] - lay.flat_right[j] * s * 0.12).normalized())
	var m := art.mark(xf.origin)
	art.post(xf, Vector3(0, 0, -0.06), top, 0.08, false)
	var y := top
	for b: Array in boards:
		var size: Vector2 = b[1]
		art.board(xf, Vector3(0, y - size.y * 0.5, 0), size, b[0])
		y -= size.y + 0.06
	art.knockable(m, xf, POST_REACH)
	return j


# --- Along the lap ---------------------------------------------------------------------------

## Speed limits as each stretch starts and again part way through a long one.
func _speed_limits() -> void:
	for z: int in LIMITS:
		var nodes := pl._stretch(z)
		if nodes.is_empty():
			continue
		for at: float in [0.0, 0.55]:
			if at > 0.0 and nodes.size() < 100:
				continue
			var i := nodes[mini(int(at * nodes.size()) + 3, nodes.size() - 1)]
			_post_sign(i, 1.0, [[_speed(LIMITS[z]), Vector2(0.75, 0.95)]])


## A diamond some way before each side road out of town (not the shortcuts, which are
## there to be found), showing which side(s) it leaves on.
func _junction_warnings() -> void:
	var done := {}
	for b in lay.branches:
		if b.kind == "street" or b.kind == "shortcut" or done.has(b.from):
			continue
		var side := int(b.side)
		for o in lay.branches:
			if o != b and o.from == b.from:
				side = 0
		done[b.from] = true
		var ahead := 16
		if b.kind == "lookout":
			_post_sign(lay.idx(b.from - 40), 1.0, [[_plate("overlook", Vector2(1.6, 0.9), SignArt.BROWN, SignArt.WHITE,
				[["SCENIC", 12.0], ["OVERLOOK", 12.0], ["1/4 MILE", 10.0]]), Vector2(1.6, 0.9)]], 2.6)
			ahead = 3
		_post_sign(lay.idx(b.from - ahead), 1.0, [[_junction(side), Vector2(0.9, 0.9)]], 2.7, -1)


## Hills: a warning with the grade at the top of each long steep descent, and a HILL BLOCKS
## VIEW before the sharpest crests over the farmland.
func _hills() -> void:
	var n := lay.n
	var last := -999
	for i in n:
		if i - last < 60 or lay.zone[i] == Zone.TOWN:
			continue
		var drop := lay.pts[i].y - lay.pts[lay.idx(i + 25)].y
		if drop / (25.0 * STEP) > 0.055:
			var pct := roundi(drop / (25.0 * STEP) * 100.0)
			_post_sign(lay.idx(i - 3), 1.0, [[_diamond("hill", ["HILL"]), Vector2(0.9, 0.9)],
				[_plate("grade%d" % pct, Vector2(0.8, 0.4), SignArt.YELLOW, SignArt.BLACK, [["%d%% GRADE" % pct, 11.0]]),
				Vector2(0.8, 0.4)]], 2.9)
			last = i
	last = -999
	for i in n:
		if i - last < 40 or lay.zone[i] != Zone.FARM:
			continue
		var y := lay.pts[i].y
		var crest := y - (lay.pts[lay.idx(i - 10)].y + lay.pts[lay.idx(i + 10)].y) * 0.5
		if crest > 2.2 and y >= lay.pts[lay.idx(i - 1)].y and y >= lay.pts[lay.idx(i + 1)].y:
			_post_sign(lay.idx(i - 14), 1.0, [[_diamond("blind", ["HILL", "BLOCKS", "VIEW"]), Vector2(0.9, 0.9)]], 2.7, -1)
			last = i


## A pennant on the left where the double yellow starts.
func _no_passing() -> void:
	var style := ProcGround.centre_style(lay)
	for i in lay.n:
		if style[i] > 0.5 and style[lay.idx(i - 1)] < 0.5 and lay.zone[i] != Zone.TOWN:
			var f := _spot(lay.idx(i - 2), -1.0, -1)
			if f.is_empty():
				continue
			var j: int = f[0]
			var xf := ProcScenery._upright(f[1], -lay.fwd[j])
			var m := art.mark(xf.origin)
			art.post(xf, Vector3(0, 0, -0.06), 2.5, 0.08, false)
			# Pointing along the road, over it.
			art.board(xf, Vector3(0.5, 2.1, 0), Vector2(1.2, 0.9), _pennant())
			art.knockable(m, xf, POST_REACH)


func _bridges() -> void:
	for run: Array in ProceduralTrack._runs(lay.kind, Kind.BRIDGE):
		_post_sign(lay.idx(run[0] - 16), 1.0, [[_diamond("ices", ["BRIDGE", "ICES BEFORE", "ROAD"]), Vector2(0.9, 0.9)]],
			2.7, -1)


## The route's shield out of town and out of the tunnel, and green signs for what's ahead.
func _route_and_guides() -> void:
	var nm := pl.nm
	var town := pl._stretch(Zone.TOWN)
	var shield := [[_shield(nm.route), Vector2(0.75, 0.75)]]
	if not town.is_empty():
		var out := town[town.size() - 1]
		_post_sign(lay.idx(out + 6), 1.0, shield, 2.5)
		var rows := []
		for d: Array in [[Zone.FOREST, nm.forest], [Zone.MOUNTAIN, nm.pass], [Zone.LAKE, nm.lake]]:
			var st := pl._stretch(d[0])
			if not st.is_empty():
				rows.append([String(d[1]).to_upper(), miles(lay.idx(st[0] - out) * STEP)])
		_guide_sign(lay.idx(out + 22), "out", rows)
	for run: Array in ProceduralTrack._runs(lay.kind, Kind.TUNNEL):
		var end: int = lay.idx(run[0] + run[1])
		_post_sign(lay.idx(end + 6), 1.0, shield, 2.5)
		var rows := []
		var lake := pl._stretch(Zone.LAKE)
		if not lake.is_empty():
			rows.append([String(nm.lake).to_upper(), miles(lay.idx(lake[0] - end) * STEP)])
		if not town.is_empty():
			rows.append([String(nm.town).to_upper(), miles(lay.idx(town[0] - end) * STEP)])
		_guide_sign(lay.idx(end + 26), "tunnel", rows)


## A big green sign on two posts well off the road.
func _guide_sign(i: int, key: String, rows: Array) -> void:
	if rows.is_empty():
		return
	var uv := _guide(key, rows)
	var size := Vector2(4.4, 0.45 + rows.size() * 0.5)
	for k in 16:
		var j := lay.idx(i + k)
		var p := sc._beside(j, 1.0, lay.wall_r[j] + 1.0 + size.x * 0.5)
		if lay.kind[j] != Kind.OPEN or lay.gap_r[j] or not sc._clear(p, 0.5, 10.0):
			continue
		var xf := ProcScenery._upright(p, (-lay.fwd[j] - lay.flat_right[j] * 0.15).normalized())
		for x: float in [-size.x * 0.32, size.x * 0.32]:
			art.post(xf, Vector3(x, 0, -0.08), 2.2 + size.y, 0.12)
		art.board(xf, Vector3(0, 2.2 + size.y * 0.5, 0), size, uv)
		return


## Green mile markers every half mile, counting up from wherever the route's miles got to.
func _mile_markers() -> void:
	var every := int(MILE * 0.5 / STEP)
	for i in range(every / 2, lay.n, every):
		if lay.zone[i] == Zone.TOWN:
			continue
		var tenths := int(pl.nm.mile0) * 10 + roundi(i * STEP / MILE * 10.0)
		var label := "%d.%d" % [tenths / 10, tenths % 10]
		var uv := _plate("mile" + label, Vector2(0.3, 0.7), SignArt.GREEN, SignArt.WHITE,
			[["MILE", 7.0], [label.get_slice(".", 0), 11.0], ["." + label.get_slice(".", 1), 9.0]])
		var f := _spot(i, 1.0)
		if f.is_empty():
			continue
		var xf := ProcScenery._upright(f[1], -lay.fwd[f[0]])
		var m := art.mark(xf.origin)
		art.post(xf, Vector3(0, 0, -0.04), 1.3, 0.05, false)
		art.board(xf, Vector3(0, 1.0, 0), Vector2(0.3, 0.7), uv)
		art.knockable(m, xf, POST_REACH)


## An advisory speed under a bend's warning sign, from how tight it is (knocked off with it).
func advisory(xf: Transform3D, radius: float) -> void:
	var mph := clampi(roundi(sqrt(0.3 * 9.81 * radius) * 2.237 / 5.0) * 5, 15, 50)
	var i := lay.closest(xf.origin.x, xf.origin.z)
	if i >= 0 and mph >= LIMITS[lay.zone[i]]:
		return
	var m := art.mark(xf.origin)
	art.board(xf, Vector3(0, 1.45, 0.02), Vector2(0.55, 0.55),
		_plate("mph%d" % mph, Vector2(0.55, 0.55), SignArt.YELLOW, SignArt.BLACK, [[str(mph), 13.0], ["MPH", 8.0]]))
	art.knockable(m, xf, POST_REACH)


# --- At the side roads -----------------------------------------------------------------------

func _branch_furniture() -> void:
	for bi in lay.branches.size():
		var b := lay.branches[bi]
		if b.kind == "shortcut":
			continue
		var name := pl.branch_name(bi)
		var t0 := b.pts[2] - b.pts[0]
		t0.y = 0.0
		t0 = t0.normalized()
		var r0 := t0.cross(Vector3.UP).normalized()
		var h := b.half_at(4.0)
		var kerb := 2.8 if b.paved and b.kind == "street" else 0.9
		# Out of town, far enough up the side road to be clear of the racing.
		var k0 := 1 if b.kind == "street" else 3
		h = b.half_at(k0 * ProceduralTrack.BSTEP)
		# A stop sign for traffic coming out, on its right: its back to the main road.
		if b.kind != "lookout":
			var sp := _ground(b.pts[k0] - r0 * (h + kerb))
			var xf := ProcScenery._upright(sp, t0)
			var m := art.mark(xf.origin)
			art.post(xf, Vector3(0, 0, -0.05), 2.5, 0.08, false)
			art.board(xf, Vector3(0, 2.1, 0), Vector2(0.75, 0.75), _stop(), false)
			art.board(Transform3D(xf.basis.rotated(Vector3.UP, PI), xf.origin), Vector3(0, 2.1, 0.02), Vector2(0.75, 0.75),
				_stop_back(), false)
			art.knockable(m, xf, POST_REACH)
		# Its name on the corner opposite, readable from the main road.
		if name != "":
			var bp := _ground(b.pts[k0] + r0 * (h + kerb))
			var xf := ProcScenery._upright(bp, t0)
			var green := SignArt.BROWN if b.kind != "street" and b.kind != "lane" else SignArt.GREEN
			var m := art.mark(xf.origin)
			art.post(xf, Vector3.ZERO, 3.0, 0.06, false)
			var blade := _plate("blade:" + name, Vector2(1.1, 0.24), green, SignArt.WHITE, [[name.to_upper(), 11.0]], false)
			for turn: float in [PI * 0.5, -PI * 0.5]:
				art.board(Transform3D(xf.basis.rotated(Vector3.UP, turn), xf.origin), Vector3(0, 2.85, 0.05),
					Vector2(1.1, 0.24), blade, false)
			if b.kind == "street":
				var main := _plate("blade:main", Vector2(1.1, 0.24), SignArt.GREEN, SignArt.WHITE, [["MAIN ST", 11.0]], false)
				for turn: float in [0.0, PI]:
					art.board(Transform3D(xf.basis.rotated(Vector3.UP, turn), xf.origin), Vector3(0, 2.55, 0.05),
						Vector2(1.1, 0.24), main, false)
			art.knockable(m, xf, POST_REACH)
		if b.closed > 0.0:
			if b.kind == "forest":
				_gate(b)
			else:
				_barricade(b)


func _ground(p: Vector3) -> Vector3:
	var d := lay.deck_y(p.x, p.z)
	var b := lay.branch_at(p.x, p.z)
	return Vector3(p.x, maxf(ProcGround.surface_y(lay, p.x, p.z), d if not is_nan(d) else -INF) if b.x > 99.0 else
		maxf(ProcGround.surface_y(lay, p.x, p.z), b.y + 0.1), p.z)


## Where branch `b` is `along` m from its start: [point, level direction on].
static func _along(b: ProceduralTrack.Branch, along: float) -> Array:
	var k := clampi(int(along / ProceduralTrack.BSTEP), 0, b.pts.size() - 2)
	var t := clampf(along / ProceduralTrack.BSTEP - k, 0.0, 1.0)
	var dir := b.pts[k + 1] - b.pts[k]
	dir.y = 0.0
	return [b.pts[k].lerp(b.pts[k + 1], t), dir.normalized()]


## Sawhorses across a closed road with a ROAD CLOSED sign on the middle one and cones: all
## knocked flying by a car that runs the roadblock.
func _barricade(b: ProceduralTrack.Branch) -> void:
	var a := _along(b, b.closed)
	var p: Vector3 = a[0]
	var t: Vector3 = a[1]
	var h := b.half_at(b.closed) + (2.0 if b.kind == "street" else 0.6)
	var xf := ProcScenery._upright(p, -t)   # facing back the way cars come
	var stripes := _stripes()
	var legs := _colour("wood", Color(0.85, 0.83, 0.78))
	var count := maxi(roundi(h * 2.0 / 2.0), 2)
	for k in count:
		var x := -h + (k + 0.5) * h * 2.0 / count
		var m := art.mark(xf.origin)
		for y: float in [0.62, 0.95]:
			art.board(xf, Vector3(x, y, 0.0), Vector2(1.8, 0.2), stripes, false)
			art.board(Transform3D(xf.basis.rotated(Vector3.UP, PI), xf.origin), Vector3(-x, y, 0.03), Vector2(1.8, 0.2),
				stripes, false)
		for lx: float in [-0.75, 0.75]:
			for lz: float in [-0.25, 0.25]:
				art.box(xf, Vector3(x + lx, 0.5, lz * 0.6), Vector3(0.06, 1.05, 0.06), legs)
		# An amber lamp on every other one.
		if k % 2 == 0:
			art.box(xf, Vector3(x, 1.18, 0.0), Vector3(0.16, 0.2, 0.1), _colour("amber", Color(1.0, 0.7, 0.1)))
		art.knockable(m, xf.translated_local(Vector3(x, 0, 0)), AABB(Vector3(-0.9, 0, -0.3), Vector3(1.8, 1.1, 0.6)))
	var closed := _plate("closed", Vector2(1.2, 0.6), SignArt.WHITE, SignArt.BLACK, [["ROAD", 15.0], ["CLOSED", 15.0]])
	var m := art.mark(xf.origin)
	for x: float in [-0.35, 0.35]:
		art.box(xf, Vector3(x, 1.3, -0.05), Vector3(0.05, 0.9, 0.05), legs)
	art.board(xf, Vector3(0, 1.45, 0.02), Vector2(1.2, 0.6), closed)
	art.knockable(m, xf.translated_local(Vector3(0, 0, -0.05)), AABB(Vector3(-0.6, 0.8, -0.2), Vector3(1.2, 1.0, 0.4)))
	# Cones fanned out in front.
	for k in rng.randi_range(3, 5):
		var q := xf * Vector3(rng.randf_range(-h, h), 0, rng.randf_range(1.5, 5.0))
		q.y = _ground(q).y
		var cxf := ProcScenery._upright(q, t)
		sc.knockable(cxf, AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 0.7, 0.5)), [sc._put("cone", cxf)])


## A forest road's gate: a yellow pipe between two posts, closed.
func _gate(b: ProceduralTrack.Branch) -> void:
	var a := _along(b, b.closed)
	var p: Vector3 = a[0]
	var t: Vector3 = a[1]
	var h := b.half_at(b.closed) + 0.4
	var xf := ProcScenery._upright(p, -t)
	var yellow := _colour("gate", Color(0.95, 0.75, 0.1))
	for x: float in [-h, h]:
		art.box(xf, Vector3(x, 0.45, 0), Vector3(0.2, 1.3, 0.2), yellow, true)
	art.box(xf, Vector3(0, 0.95, 0), Vector3(h * 2.0, 0.1, 0.1), yellow, true)
	var closed := _plate("closed_small", Vector2(0.7, 0.35), SignArt.WHITE, SignArt.BLACK, [["ROAD CLOSED", 9.0]])
	art.board(xf, Vector3(0, 0.72, 0.06), Vector2(0.7, 0.35), closed)


func flush(root: Node3D) -> void:
	art.flush(root, sc.breakables)

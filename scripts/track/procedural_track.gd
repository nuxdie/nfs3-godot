class_name ProceduralTrack
## A generated closed circuit, used when no NFS3 data is installed. Built the way an NFS3
## course feels: a lap that runs out of a small town, through farmland and forest, up
## through a rock-cut mountain pass and a tunnel, and back over a river valley, with the
## terrain shaped around the road (cuttings, embankments, bridges) and the scenery to
## match each stretch.
##
##   Layout     the centre line (a jittered loop checked for tight bends and near misses),
##              the natural terrain under it, the road's heights (smoothed, grade-limited,
##              carried level through the ridge and over the river), banking, and which
##              nodes are open road, tunnel or bridge
##   ProcGround the road, verges, terrain, far mountains, water, tunnel and bridges
##   ProcScenery trees, rails, fences, poles, signs, buildings, lamps, the start gantry

## Bump when the look changes, so the menu re-renders its postcard.
const VERSION := 2

const STEP := 6.0            # m between path nodes
const ROAD_HALF := 7.0       # two lanes
const SHOULDER := 2.5        # gravel verge (a raised pavement in town)
const LOST_MARGIN := 120.0   # m out past the road's edge before the race resets a car

enum Kind { OPEN, TUNNEL, BRIDGE }
enum Zone { TOWN, FARM, FOREST, MOUNTAIN, LAKE }

## Where along the lap (0..1) each stretch starts; the lap starts in town.
const ZONES := [[0.0, Zone.TOWN], [0.08, Zone.FARM], [0.33, Zone.FOREST], [0.52, Zone.MOUNTAIN],
	[0.75, Zone.LAKE], [0.95, Zone.TOWN]]
const TUNNEL_AT := 0.635     # the ridge the tunnel goes through
const RIVER_AT := 0.84       # the river the bridge crosses


class Layout:
	var n := 0
	var pts := PackedVector3Array()     # road centre, on the surface
	var fwd := PackedVector3Array()     # level (y = 0), unit
	var flat_right := PackedVector3Array()  # level, unit, to the driver's right
	var right := PackedVector3Array()   # across the (banked) road
	var up := PackedVector3Array()
	var curv := PackedFloat32Array()    # 1 / radius, + turning right
	var kind := PackedByteArray()
	var zone := PackedByteArray()
	var edge := PackedFloat32Array()    # centre to the verge's outer edge
	var wall_l := PackedFloat32Array()
	var wall_r := PackedFloat32Array()
	var rail_l := PackedByteArray()     # 1 where a guardrail runs along that side
	var rail_r := PackedByteArray()
	var length := 0.0
	var centre := Vector2.ZERO          # of the course, on the ground plane
	var extent := 1.0                   # half its larger dimension

	var water := -INF                   # the river and lakes' surface
	var river_bed := 0.0
	var river_on := false
	var river_p := Vector2.ZERO         # where the river crosses the road...
	var river_dir := Vector2.RIGHT      # ...and which way it runs
	const RIVER_HALF := 520.0           # m either side of the crossing it runs
	var ridge_p := Vector2.ZERO
	var ridge_dir := Vector2.RIGHT      # along the path through it
	var lake_p := Vector2.ZERO
	var lake_depth := 0.0

	var _lo := FastNoiseLite.new()
	var _mid := FastNoiseLite.new()
	var _hi := FastNoiseLite.new()
	var _peaks := FastNoiseLite.new()
	var _grid := {}                     # Vector2i cell -> PackedInt32Array of nodes
	const GRID := 60.0

	func _init(seed_value: int) -> void:
		for k in 4:
			var fn: FastNoiseLite = [_lo, _mid, _hi, _peaks][k]
			fn.seed = seed_value * 7 + k
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		_lo.frequency = 1.0 / 900.0
		_lo.fractal_octaves = 2
		_mid.frequency = 1.0 / 260.0
		_mid.fractal_octaves = 3
		_hi.frequency = 1.0 / 45.0
		_hi.fractal_octaves = 2
		_peaks.frequency = 1.0 / 700.0
		_peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		_peaks.fractal_octaves = 4

	## The land as it would be without the road.
	func natural(x: float, z: float) -> float:
		var h := _lo.get_noise_2d(x, z) * 55.0 + _mid.get_noise_2d(x, z) * 14.0 + _hi.get_noise_2d(x, z) * 1.2
		# A ring of mountains beyond the course.
		var r := Vector2(x - centre.x, z - centre.y).length() / extent
		var rise := smoothstep(1.15, 2.4, r)
		if rise > 0.0:
			h += rise * (140.0 + 260.0 * (_peaks.get_noise_2d(x, z) * 0.5 + 0.5))
		# The ridge across the road, long and narrow.
		var q := Vector2(x, z) - ridge_p
		var along := q.dot(ridge_dir)
		var across := q.dot(ridge_dir.orthogonal())
		h += 46.0 * exp(-(along * along) / (85.0 * 85.0) - (across * across) / (320.0 * 320.0))
		if lake_depth > 0.0:
			var dl := Vector2(x, z).distance_squared_to(lake_p)
			h -= lake_depth * exp(-dl / (150.0 * 150.0))
		if river_on:
			h = minf(h, lerpf(river_bed, h, river_t(x, z)))
		return h

	## 0 in the river's channel, rising to 1 up its banks and towards its ends.
	func river_t(x: float, z: float) -> float:
		var q := Vector2(x, z) - river_p
		var along := q.dot(river_dir)
		# Meanders a little.
		var dr := absf(q.dot(river_dir.orthogonal()) + _mid.get_noise_2d(along * 0.8, 17.0) * 30.0)
		var over := maxf(absf(along) - RIVER_HALF, 0.0)
		return maxf(smoothstep(8.0, 75.0, dr), smoothstep(0.0, 160.0, over))

	func idx(i: int) -> int:
		return ((i % n) + n) % n

	## Height of the road's (banked) surface `d` m to side `s` (+1 right) of node `i`.
	func road_y(i: int, s: float, d: float) -> float:
		return pts[i].y + right[i].y * s * d

	## Height of the ground `d` m out to side `s` of node `i`, beyond the verge: the natural
	## land where it's near the road's level, otherwise cut down or built up to it with
	## slopes (steep rock cuttings, gentler grass banks). Town keeps a level strip for its
	## buildings. Inside the verge it is the road's level.
	func side_y(i: int, s: float, d: float) -> float:
		var e := edge[i]
		var edge_y := road_y(i, s, minf(d, e)) - 0.12
		if d <= e:
			return edge_y
		var dd := d - e
		var p := pts[i]
		var fr := flat_right[i] * s
		var nat := natural(p.x + fr.x * d, p.z + fr.z * d)
		if zone[i] == Zone.TOWN:
			var t := maxf(dd - 14.0, 0.0)
			return clampf(nat, edge_y - t * 0.5, edge_y + t * 0.6)
		return clampf(nat, edge_y - dd * 0.62, edge_y + maxf(dd - 1.5, 0.0) * 1.5)

	func lap_frac(i: int) -> float:
		return float(i) / n

	## Nodes near (x, z), for the terrain and scenery to find the road.
	func nearby(x: float, z: float) -> PackedInt32Array:
		var c := Vector2i(floori(x / GRID), floori(z / GRID))
		var out := PackedInt32Array()
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				out.append_array(_grid.get(c + Vector2i(dx, dz), PackedInt32Array()))
		return out

	## The closest node to (x, z) within ~GRID m, or -1.
	func closest(x: float, z: float) -> int:
		var best := -1
		var best_d := INF
		for i in nearby(x, z):
			var d := Vector2(pts[i].x - x, pts[i].z - z).length_squared()
			if d < best_d:
				best_d = d
				best = i
		return best

	func build_grid() -> void:
		_grid.clear()
		for i in n:
			var c := Vector2i(floori(pts[i].x / GRID), floori(pts[i].z / GRID))
			if not _grid.has(c):
				_grid[c] = PackedInt32Array()
			_grid[c].append(i)


static func build(root: Node3D, seed_value := 1998) -> TrackPath:
	var lay := make_layout(seed_value)
	var path := TrackPath.new()
	for i in lay.n:
		path.points.append(lay.pts[i])
		path.rights.append(lay.right[i])
		path.ups.append(lay.up[i])
		path.left_width.append(lay.wall_l[i])
		path.right_width.append(lay.wall_r[i])
	path.finalize()
	# No invisible walls: the land, rails, parapets and tunnel are solid instead, and a car
	# can run wide onto the grass. The widths still keep the AI to the road.
	path.lost_margin = LOST_MARGIN
	ProcGround.build(root, lay)
	ProcScenery.build(root, lay, seed_value)
	return path


## The lap's centreline, without building the track (for the menu's map).
static func outline(seed_value := 1998) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := _centreline(rng)
	var out := PackedVector3Array()
	for p in pts:
		out.append(Vector3(p.x, 0.0, p.y))
	return out


static func make_layout(seed_value: int) -> Layout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var line := _centreline(rng)
	var lay := Layout.new(seed_value)
	lay.n = line.size()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in line:
		lo = lo.min(p)
		hi = hi.max(p)
	lay.centre = (lo + hi) * 0.5
	lay.extent = maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
	for i in lay.n:
		lay.pts.append(Vector3(line[i].x, 0.0, line[i].y))
		lay.zone.append(_zone_at(float(i) / lay.n))
	for i in lay.n:
		var d := line[(i + 1) % lay.n] - line[(i - 1 + lay.n) % lay.n]
		var f := Vector3(d.x, 0.0, d.y).normalized()
		lay.fwd.append(f)
		lay.flat_right.append(f.cross(Vector3.UP).normalized())
	for i in lay.n:
		var a := lay.fwd[lay.idx(i - 2)]
		var b := lay.fwd[lay.idx(i + 2)]
		lay.curv.append((b - a).dot(lay.flat_right[i]) / (4.0 * STEP))
	_terrain_features(lay, rng)
	_heights(lay)
	_classify(lay)
	_bank(lay)
	_widths(lay)
	lay.build_grid()
	return lay


static func _zone_at(f: float) -> int:
	var z: int = ZONES[0][1]
	for e in ZONES:
		if f >= e[0]:
			z = e[1]
	return z


# --- The centre line -----------------------------------------------------------------------

## Evenly spaced points (STEP apart) round a closed lap on the ground plane. Loops of
## jittered control points are tried until one has no bend tighter than a hairpin and no
## two stretches of road running too close to each other.
static func _centreline(rng: RandomNumberGenerator) -> PackedVector2Array:
	var best := PackedVector2Array()
	for attempt in 60:
		var pts := _control_points(rng)
		var line := _sample(pts)
		if _valid(line):
			return line
		if best.is_empty():
			best = line
	return best


static func _control_points(rng: RandomNumberGenerator) -> PackedVector2Array:
	var n := rng.randi_range(10, 13)
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	for i in n:
		var a := phase + TAU * (i + rng.randf_range(-0.28, 0.28)) / n
		var r := rng.randf_range(430.0, 760.0)
		pts.append(Vector2(cos(a) * r * 1.3, sin(a) * r))
	# A couple of points pulled in towards the middle make the lap double back: hairpins
	# and S-bends rather than one big bumpy oval.
	for k in rng.randi_range(1, 2):
		var i := rng.randi_range(2, n - 1)
		pts[i] *= rng.randf_range(0.35, 0.55)
	# The start/finish straight: the first leg, with points on the line between its ends.
	var a0 := pts[0]
	var a1 := pts[1]
	var out := PackedVector2Array([a0, a0.lerp(a1, 0.33), a0.lerp(a1, 0.66)])
	out.append_array(pts.slice(1))
	return out


static func _sample(ctrl: PackedVector2Array) -> PackedVector2Array:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	var n := ctrl.size()
	for i in n + 1:
		var p := ctrl[i % n]
		var t := (ctrl[(i + 1) % n] - ctrl[(i - 1 + n) % n]) / 6.0
		curve.add_point(Vector3(p.x, 0.0, p.y), Vector3(-t.x, 0.0, -t.y), Vector3(t.x, 0.0, t.y))
	var total := curve.get_baked_length()
	var count := int(total / STEP)
	var out := PackedVector2Array()
	for i in count:
		var p := curve.sample_baked(i * total / count)
		out.append(Vector2(p.x, p.z))
	return out


const MIN_RADIUS := 22.0
const MIN_GAP := 75.0        # m between stretches of road more than...
const GAP_NODES := 40        # ...this many nodes apart along the lap


static func _valid(line: PackedVector2Array) -> bool:
	var n := line.size()
	if n * STEP < 3200.0 or n * STEP > 6200.0:
		return false
	for i in n:
		var a := line[(i - 1 + n) % n] - line[(i - 3 + n) % n]
		var b := line[(i + 3) % n] - line[(i + 1) % n]
		if absf(a.angle_to(b)) > 4.0 * STEP / MIN_RADIUS:
			return false
	var grid := {}
	for i in n:
		var c := Vector2i(floori(line[i].x / MIN_GAP), floori(line[i].y / MIN_GAP))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for k: int in grid.get(c + Vector2i(dx, dz), []):
					var gap := absi(k - i)
					if mini(gap, n - gap) > GAP_NODES and line[k].distance_to(line[i]) < MIN_GAP:
						return false
		if not grid.has(c):
			grid[c] = []
		grid[c].append(i)
	return true


# --- Heights ---------------------------------------------------------------------------------

## Places the ridge, the river and the lake by the road.
static func _terrain_features(lay: Layout, rng: RandomNumberGenerator) -> void:
	var it := int(TUNNEL_AT * lay.n)
	lay.ridge_p = Vector2(lay.pts[it].x, lay.pts[it].z)
	lay.ridge_dir = Vector2(lay.fwd[it].x, lay.fwd[it].z).rotated(rng.randf_range(-0.3, 0.3))
	var lowest := INF
	for i in lay.n:
		lowest = minf(lowest, lay.natural(lay.pts[i].x, lay.pts[i].z))
	lay.river_bed = lowest - 9.0
	lay.water = lay.river_bed + 3.2
	var ir := int(RIVER_AT * lay.n)
	lay.river_p = Vector2(lay.pts[ir].x, lay.pts[ir].z)
	# Across the road at a slant, whichever way keeps it furthest from the rest of the lap.
	var across := Vector2(lay.fwd[ir].x, lay.fwd[ir].z).orthogonal()
	var best := -INF
	var jitter := rng.randf_range(-0.1, 0.1)
	for k in 11:
		var d := across.rotated(-0.55 + 0.11 * k + jitter)
		var clear := INF
		for i in lay.n:
			var gap := absi(i - ir)
			if mini(gap, lay.n - gap) < 35:
				continue
			var q := Vector2(lay.pts[i].x, lay.pts[i].z) - lay.river_p
			var t := clampf(q.dot(d), -Layout.RIVER_HALF, Layout.RIVER_HALF)
			clear = minf(clear, q.distance_to(d * t))
		if clear > best:
			best = clear
			lay.river_dir = d
	# A lake off to the side of the lakeside stretch.
	var il := int(0.78 * lay.n)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var fr := lay.flat_right[il]
	lay.lake_p = Vector2(lay.pts[il].x, lay.pts[il].z) + Vector2(fr.x, fr.z) * side * 170.0
	lay.lake_depth = lay.natural(lay.lake_p.x, lay.lake_p.y) - (lay.water - 7.0)
	lay.river_on = true


static func _heights(lay: Layout) -> void:
	var n := lay.n
	var raw := PackedFloat32Array()
	for i in n:
		raw.append(lay.natural(lay.pts[i].x, lay.pts[i].z))
	var y := _smooth(raw, 14.0)
	# Level through the ridge and over the river: straight between the ends of each window,
	# so the road goes under the one and over the other.
	var windows := [[int(TUNNEL_AT * n), 45], [int(RIVER_AT * n), 32]]
	for w in windows:
		var a: int = w[0] - w[1]
		var b: int = w[0] + w[1]
		var ya := y[lay.idx(a)]
		var yb := y[lay.idx(b)]
		for k in range(a, b + 1):
			y[lay.idx(k)] = lerpf(ya, yb, float(k - a) / (b - a))
	# Above the flood, and no steeper than a mountain road.
	for i in n:
		y[i] = maxf(y[i], lay.water + 4.5)
	const GRADE := 0.075 * STEP
	for _k in 3:
		for i in range(1, n + 1):
			var k := i % n
			y[k] = clampf(y[k], y[i - 1] - GRADE, y[i - 1] + GRADE)
		for i in range(n - 2, -2, -1):
			var k := lay.idx(i)
			var j := lay.idx(i + 1)
			y[k] = clampf(y[k], y[j] - GRADE, y[j] + GRADE)
	y = _smooth(y, 3.0)
	for i in n:
		lay.pts[i].y = y[i]


## Gaussian smoothing round the loop, `sigma` in nodes.
static func _smooth(v: PackedFloat32Array, sigma: float) -> PackedFloat32Array:
	var n := v.size()
	var r := int(sigma * 2.5)
	var w := PackedFloat32Array()
	var total := 0.0
	for k in range(-r, r + 1):
		w.append(exp(-float(k * k) / (2.0 * sigma * sigma)))
		total += w[-1]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		for k in range(-r, r + 1):
			s += v[((i + k) % n + n) % n] * w[k + r]
		out[i] = s / total
	return out


## Open road, or a tunnel where the land stands well over the road on both sides, or a
## bridge where it falls well below it. Short runs are dropped (a deep cutting, an
## embankment) and short gaps between runs filled in.
static func _classify(lay: Layout) -> void:
	var n := lay.n
	var k := PackedByteArray()
	k.resize(n)
	for i in n:
		var p := lay.pts[i]
		var r := lay.flat_right[i] * (ROAD_HALF + 3.0)
		var hs := [lay.natural(p.x, p.z), lay.natural(p.x + r.x, p.z + r.z), lay.natural(p.x - r.x, p.z - r.z)]
		var low: float = hs.min()
		var high: float = hs.max()
		if low - p.y > 10.0 and lay.zone[i] != Zone.TOWN:
			k[i] = Kind.TUNNEL
		elif p.y - high > 5.5 or p.y - lay.water < 5.0 and high < lay.water + 1.0:
			k[i] = Kind.BRIDGE
		else:
			k[i] = Kind.OPEN
	for kind_v in [Kind.TUNNEL, Kind.BRIDGE]:
		_close_gaps(k, kind_v, 6)
		_drop_short(k, kind_v, 10 if kind_v == Kind.TUNNEL else 9)
	# Never on the start line.
	if k[0] != Kind.OPEN:
		push_warning("Procedural track: the start is on a %s" % k[0])
	lay.kind = k


static func _runs(k: PackedByteArray, v: int) -> Array:
	var n := k.size()
	var runs := []
	# Start from a node that isn't `v`, so no run wraps past the end.
	var s0 := -1
	for i in n:
		if k[i] != v:
			s0 = i
			break
	if s0 < 0:
		return [[0, n]]
	var i := 0
	while i < n:
		var a := (s0 + i) % n
		if k[a] == v:
			var len := 0
			while len < n and k[(a + len) % n] == v:
				len += 1
			runs.append([a, len])
			i += len
		else:
			i += 1
	return runs


static func _drop_short(k: PackedByteArray, v: int, min_len: int) -> void:
	for r in _runs(k, v):
		if r[1] < min_len:
			for j in r[1]:
				k[(r[0] + j) % k.size()] = Kind.OPEN


static func _close_gaps(k: PackedByteArray, v: int, max_gap: int) -> void:
	var n := k.size()
	var runs := _runs(k, v)
	for ri in runs.size():
		var a: Array = runs[ri]
		var b: Array = runs[(ri + 1) % runs.size()]
		var end: int = a[0] + a[1]
		var gap := posmod(b[0] - end, n)
		if gap > 0 and gap <= max_gap:
			for j in gap:
				if k[(end + j) % n] == Kind.OPEN:
					k[(end + j) % n] = v


## Sweepers lean into the bend a little; the road's right and up follow.
static func _bank(lay: Layout) -> void:
	var a := PackedFloat32Array()
	for i in lay.n:
		var z := lay.zone[i]
		var limit := 0.0 if z == Zone.TOWN or lay.kind[i] != Kind.OPEN else 0.085
		a.append(clampf(lay.curv[i] * 4.5, -limit, limit))
	a = _smooth(a, 4.0)
	for i in lay.n:
		var f := lay.fwd[i]
		# Slope along the road, from the heights either side.
		var dy := (lay.pts[lay.idx(i + 1)].y - lay.pts[lay.idx(i - 1)].y) / (2.0 * STEP)
		var along := (f + Vector3.UP * dy).normalized()
		var up := (Vector3.UP * cos(a[i]) + lay.flat_right[i] * sin(a[i]))
		up = (up - along * up.dot(along)).normalized()
		lay.up.append(up)
		lay.right.append(along.cross(up).normalized())


## The verge's width and how far out each side the AI may drive (and the race tracks a car).
## Guardrails go along drops and round the outside of tight bends out of town.
static func _widths(lay: Layout) -> void:
	var n := lay.n
	for i in n:
		lay.edge.append(ROAD_HALF + 1.2 if lay.kind[i] != Kind.OPEN else ROAD_HALF + SHOULDER)
	for s: float in [-1.0, 1.0]:
		var rail := PackedByteArray()
		rail.resize(n)
		for i in n:
			if lay.kind[i] != Kind.OPEN or lay.zone[i] == Zone.TOWN:
				continue
			var e := lay.edge[i]
			var drop := lay.road_y(i, s, e) - lay.side_y(i, s, e + 7.0)
			var outside := lay.curv[i] * s < -1.0 / 130.0
			var near_bridge := false
			for k in range(-6, 7):
				near_bridge = near_bridge or lay.kind[lay.idx(i + k)] == Kind.BRIDGE
			if drop > 2.4 or near_bridge or outside and lay.zone[i] != Zone.FARM:
				rail[i] = 1
		_close_gaps(rail, 1, 5)
		_drop_short(rail, 1, 6)
		var walls := PackedFloat32Array()
		for i in n:
			var e := lay.edge[i]
			var wall := e + 4.0
			match lay.kind[i]:
				Kind.TUNNEL, Kind.BRIDGE:
					wall = e - 0.1
				_:
					if rail[i]:
						wall = e + 0.6
					elif lay.zone[i] == Zone.TOWN:
						wall = e + 0.4
					elif lay.side_y(i, s, e + 3.0) - lay.road_y(i, s, e) > 1.5:
						wall = e + 1.3   # the foot of a cutting
			walls.append(wall)
		# Walls close in gradually (a funnel onto a bridge, round the foot of a cutting): a
		# step inwards would stop a car dead.
		const TAPER := 0.3   # m per node
		for _k in 2:
			for i in range(1, n + 1):
				walls[i % n] = minf(walls[i % n], walls[i - 1] + TAPER)
			for i in range(n - 2, -2, -1):
				walls[lay.idx(i)] = minf(walls[lay.idx(i)], walls[lay.idx(i + 1)] + TAPER)
		if s < 0.0:
			lay.rail_l = rail
			lay.wall_l = walls
		else:
			lay.rail_r = rail
			lay.wall_r = walls

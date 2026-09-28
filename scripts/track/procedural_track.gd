class_name ProceduralTrack
## A generated closed circuit, used when no NFS3 data is installed. Built the way an NFS3
## course feels: a lap that runs out of a small town, through farmland and forest, up
## through a rock-cut mountain pass and a tunnel, and back over a river valley, with the
## terrain shaped around the road (cuttings, embankments, bridges) and the scenery to
## match each stretch.
##
##   Layout     the centre line (a jittered loop checked for tight bends and near misses),
##              the natural terrain under it, the road's heights (smoothed, grade-limited,
##              carried level through the ridge and over the river, rolling over the
##              farmland), banking, which nodes are open road, tunnel or bridge, and the
##              roads off it: side roads (mostly closed a little way along) and shortcuts
##   ProcGround the road, verges, terrain, far mountains, water, tunnel and bridges
##   ProcScenery trees, rails, fences, poles, signs, buildings, lamps, the start gantry
##   ProcPlaces  the named places (town, gas station, diner, farm, campground, motel) and
##              the signs and billboards that name and point to them

## Bump when the look changes, so the menu re-renders its postcard.
const VERSION := 4
## The seed the game builds the lap from.
const SEED := 1998

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


## A road off the lap: a town street, a farm lane, a forest road, the lookout's drive or the
## campground's, or a shortcut that leaves the lap and joins it again further on. The land
## under it is levelled to it (see Layout.natural).
class Branch:
	var kind := ""                        # street, lane, forest, lookout, camp, shortcut
	var pts := PackedVector3Array()       # centre line, every BSTEP m; y is its surface
	var half := 3.0                       # half its width
	var paved := false
	var from := 0                         # the node it leaves the lap at...
	var to := -1                          # ...and a shortcut's, where it joins it again
	var side := 1.0                       # of the lap, at `from`
	var closed := -1.0                    # m along it to the barricade; -1 open
	var widen := 0.0                      # m wider over its last 20 m (the lookout's car park)

	## Half its width `along` m from its start: flared into the mouth(s) it meets the lap at.
	func half_at(along: float) -> float:
		var total := (pts.size() - 1) * BSTEP
		var h := half + maxf(0.0, 7.0 - along) * 0.5
		if to >= 0:
			h = maxf(h, half + maxf(0.0, 7.0 - (total - along)) * 0.5)
		if widen > 0.0:
			h += widen * smoothstep(total - 26.0, total - 10.0, along)
		return h


const BSTEP := 4.0           # m between a branch's points


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
	var branches: Array[Branch] = []
	var gap_l := PackedByteArray()      # 1 where a branch leaves that side of the road
	var gap_r := PackedByteArray()
	var _bgrid := {}                    # Vector2i cell -> [[branch, segment], ...]
	const BGRID := 40.0
	const BREACH := 26.0                # m out from a branch that the land is shaped to it

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
		if not _bgrid.is_empty():
			# Levelled across the branches' corridors, easing back to the land either side.
			var b := branch_at(x, z)
			if b.x < BREACH:
				var band := branches[int(b.z)].half + 5.0
				h = lerpf(h, b.y - 0.15, 1.0 - smoothstep(band, BREACH, b.x))
		return h

	## The nearest branch within BREACH of (x, z): (distance, its surface height there,
	## index), distance INF if none.
	func branch_at(x: float, z: float) -> Vector3:
		var best := Vector3(INF, 0.0, -1.0)
		var q := Vector2(x, z)
		for e: Vector2i in _bgrid.get(Vector2i(floori(x / BGRID), floori(z / BGRID)), []):
			var pts := branches[e.x].pts
			var a := Vector2(pts[e.y].x, pts[e.y].z)
			var b := Vector2(pts[e.y + 1].x, pts[e.y + 1].z)
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := q.distance_to(a + ab * t)
			if d < best.x:
				best = Vector3(d, lerpf(pts[e.y].y, pts[e.y + 1].y, t), e.x)
		return best

	func add_branch(b: Branch) -> void:
		branches.append(b)
		var bi := branches.size() - 1
		for k in b.pts.size() - 1:
			var a := b.pts[k]
			var c := b.pts[k + 1]
			var pad := BREACH + 2.0
			for cx in range(floori((minf(a.x, c.x) - pad) / BGRID), floori((maxf(a.x, c.x) + pad) / BGRID) + 1):
				for cz in range(floori((minf(a.z, c.z) - pad) / BGRID), floori((maxf(a.z, c.z) + pad) / BGRID) + 1):
					var cell := Vector2i(cx, cz)
					if not _bgrid.has(cell):
						_bgrid[cell] = []
					_bgrid[cell].append(Vector2i(bi, k))

	## Whether something `r` m round (x, z) would stand on a branch or its shoulders.
	func on_branch(x: float, z: float, r: float) -> bool:
		var b := branch_at(x, z)
		return b.x < INF and b.x < branches[int(b.z)].half + r + 3.0

	## Height of the road's own surface (the carriageway and its verges) at (x, z), or NAN off it.
	func deck_y(x: float, z: float) -> float:
		var i := closest(x, z)
		if i < 0 or kind[i] != Kind.OPEN:
			return NAN
		var v := Vector3(x, 0.0, z) - Vector3(pts[i].x, 0.0, pts[i].z)
		var lat := v.dot(flat_right[i])
		var d := absf(lat)
		var s := signf(lat) if lat != 0.0 else 1.0
		if d > edge[i]:
			return NAN
		var y := road_y(i, s, minf(d, ROAD_HALF))
		# Along to the next node.
		var along := v.dot(fwd[i]) / STEP
		var j := idx(i + (1 if along > 0.0 else -1))
		y += (road_y(j, s, minf(d, ROAD_HALF)) - road_y(i, s, minf(d, ROAD_HALF))) * absf(along)
		if d > ROAD_HALF:
			if zone[i] == Zone.TOWN and not (gap_r if s > 0.0 else gap_l)[i]:
				y += 0.12 * clampf((d - ROAD_HALF) / 0.45, 0.0, 1.0)
			else:
				y -= 0.12 * (d - ROAD_HALF) / (edge[i] - ROAD_HALF)
		return y

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


static func build(root: Node3D, seed_value := SEED) -> TrackPath:
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
static func outline(seed_value := SEED) -> PackedVector3Array:
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
	_branches(lay, seed_value)
	# Again, now the land is shaped to the branches and the rails open for them.
	_widths(lay)
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
	# The farm road rides the land's swells instead of smoothing them out: blind crests and
	# dips a fast car gets light over.
	var detail := _smooth(raw, 6.0)
	var farm := PackedFloat32Array()
	for i in n:
		farm.append(1.0 if lay.zone[i] == Zone.FARM else 0.0)
	farm = _smooth(farm, 6.0)
	for i in n:
		y[i] += (detail[i] - y[i]) * 0.7 * farm[i]
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
	var grade := PackedFloat32Array()
	for i in n:
		grade.append((0.075 + 0.01 * farm[i]) * STEP)
	for _k in 3:
		for i in range(1, n + 1):
			var k := i % n
			y[k] = clampf(y[k], y[i - 1] - grade[k], y[i - 1] + grade[k])
		for i in range(n - 2, -2, -1):
			var k := lay.idx(i)
			var j := lay.idx(i + 1)
			y[k] = clampf(y[k], y[j] - grade[k], y[j] + grade[k])
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
	lay.edge = PackedFloat32Array()
	if lay.gap_l.is_empty():
		lay.gap_l.resize(n)
		lay.gap_r.resize(n)
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
		# Open where a branch leaves.
		var gap := lay.gap_r if s > 0.0 else lay.gap_l
		for i in n:
			if gap[i]:
				rail[i] = 0
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


# --- Roads off the lap -----------------------------------------------------------------------

## Streets off both sides of the town every block or so, lanes across the farmland and down
## to the lake, forest roads, the campground's road, a drive out to a lookout in the
## mountains, and gravel shortcuts across the inside of a couple of big bends.
static func _branches(lay: Layout, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 29 + 7
	_streets(lay, rng)
	_shortcuts(lay, rng)
	_country_roads(lay, rng)
	for b in lay.branches:
		var gap := lay.gap_r if b.side > 0.0 else lay.gap_l
		var span := int(ceilf((b.half + 5.0) / STEP))
		for c: int in [b.from, b.to]:
			if c < 0:
				continue
			for k in range(-span, span + 1):
				gap[lay.idx(c + k)] = 1


## Town streets: straight off the main street, both sides at a crossroads, closed a block in.
static func _streets(lay: Layout, rng: RandomNumberGenerator) -> void:
	var n := lay.n
	var start := 0
	while lay.zone[start] == Zone.TOWN or lay.zone[lay.idx(start + 1)] != Zone.TOWN:
		start = lay.idx(start + 1)
	var last := -99
	for k in n:
		var i := lay.idx(start + 1 + k)
		if lay.zone[i] != Zone.TOWN:
			break
		# Not by the start line and its grid.
		if posmod(i + 16, n) < 26 or k - last < 13 or not _level_run(lay, i, 3, 250.0):
			continue
		var made := false
		for s: float in [1.0, -1.0]:
			if rng.randf() > 0.85:
				continue
			var b := Branch.new()
			b.kind = "street"
			b.half = 4.0
			b.paved = true
			b.from = i
			b.side = s
			b.closed = rng.randf_range(40.0, 60.0)
			var dir := Vector2(lay.flat_right[i].x, lay.flat_right[i].z).rotated(rng.randf_range(-0.06, 0.06)) * s
			var p0 := Vector2(lay.pts[i].x, lay.pts[i].z) + Vector2(lay.flat_right[i].x, lay.flat_right[i].z) * s * ROAD_HALF
			var xz := PackedVector2Array()
			for m in 33:
				xz.append(p0 + dir * m * BSTEP)
			if _fit(lay, b, xz):
				lay.add_branch(b)
				made = true
		if made:
			last = k


## Whether the road around node `i` is open, not turning tighter than `radius`, `span` nodes
## either side.
static func _level_run(lay: Layout, i: int, span: int, radius: float) -> bool:
	for k in range(-span, span + 1):
		var j := lay.idx(i + k)
		if lay.kind[j] != Kind.OPEN or absf(lay.curv[j]) > 1.0 / radius:
			return false
	return true


## Lanes and forest roads off into the country, winding a little; most gated or barricaded.
static func _country_roads(lay: Layout, rng: RandomNumberGenerator) -> void:
	# kind, stretch, how many, half width, closed (m, or -1 open), length (m), max grade
	var specs := [["camp", Zone.FOREST, 1, 3.2, -1.0, 88.0, 0.08], ["lookout", Zone.MOUNTAIN, 1, 3.5, -1.0, 40.0, 0.03],
		["lane", Zone.FARM, 3, 2.8, 34.0, 150.0, 0.1], ["forest", Zone.FOREST, 2, 3.0, 28.0, 140.0, 0.1],
		["lane", Zone.LAKE, 1, 2.8, 30.0, 110.0, 0.1]]
	for spec: Array in specs:
		var nodes := PackedInt32Array()
		for i in lay.n:
			if lay.zone[i] == spec[1] and _level_run(lay, i, 4, 160.0) and not _near_mouth(lay, i, 14):
				nodes.append(i)
		var made := 0
		for _t in 60:
			if made >= spec[2] or nodes.is_empty():
				break
			var i := nodes[rng.randi() % nodes.size()]
			if _near_mouth(lay, i, 14):
				continue
			var s := 1.0 if rng.randf() < 0.5 else -1.0
			var fr := Vector2(lay.flat_right[i].x, lay.flat_right[i].z) * s
			if spec[0] == "lookout":
				# Out over the side the land falls away on, for the view.
				var lo := func(side: float) -> float:
					var q := Vector2(lay.pts[i].x, lay.pts[i].z) + Vector2(lay.flat_right[i].x, lay.flat_right[i].z) * side * 75.0
					return lay.natural(q.x, q.y)
				s = 1.0 if lo.call(1.0) < lo.call(-1.0) else -1.0
				fr = Vector2(lay.flat_right[i].x, lay.flat_right[i].z) * s
				if lay.pts[i].y - lo.call(s) < 14.0:
					continue
			var b := Branch.new()
			b.kind = spec[0]
			b.half = spec[3]
			b.paved = spec[0] == "lookout"
			b.from = i
			b.side = s
			b.closed = spec[4] * rng.randf_range(0.85, 1.25) if spec[4] > 0.0 else -1.0
			b.widen = 7.0 if spec[0] == "lookout" else 0.0
			var f := Vector2(lay.fwd[i].x, lay.fwd[i].z)
			var ang := rng.randf_range(1.15, 1.95) if spec[0] != "lookout" else PI * 0.5
			var h := f * cos(ang) + fr * sin(ang)
			var p := Vector2(lay.pts[i].x, lay.pts[i].z) + fr * ROAD_HALF
			var xz := PackedVector2Array([p])
			var turn := 0.0
			for m in int(spec[5] / BSTEP):
				if m * BSTEP > 16.0:
					turn = clampf(turn + rng.randf_range(-0.025, 0.025), -0.07, 0.07)
					h = h.rotated(turn)
				p += h * BSTEP
				xz.append(p)
			if _fit(lay, b, xz, NAN, spec[6]):
				lay.add_branch(b)
				made += 1


static func _near_mouth(lay: Layout, i: int, nodes: int) -> bool:
	for b in lay.branches:
		for c: int in [b.from, b.to]:
			if c >= 0 and mini(posmod(i - c, lay.n), posmod(c - i, lay.n)) < nodes:
				return true
	return false


## Gravel tracks cutting across the inside of the biggest bends out in the country, leaving
## and rejoining the road at a slant. Never so far out or so tangled that the nearest stretch
## of road jumps about (the race tracks a car by it).
static func _shortcuts(lay: Layout, rng: RandomNumberGenerator) -> void:
	var n := lay.n
	var cands := []
	for a in range(0, n, 2):
		if lay.zone[a] == Zone.TOWN:
			continue
		var turning := 0.0
		var sgn := 0.0
		for span in range(1, 48):
			var j := lay.idx(a + span)
			if lay.kind[j] != Kind.OPEN or lay.zone[j] == Zone.TOWN:
				break
			turning += lay.curv[j] * STEP
			if sgn == 0.0 and absf(turning) > 0.1:
				sgn = signf(turning)
			if sgn != 0.0 and lay.curv[j] * sgn < -1.0 / 400.0:
				break
			if span >= 18 and span % 2 == 0 and absf(turning) > 0.7 and absf(turning) < 2.6:
				var chord := Vector2(lay.pts[a].x - lay.pts[j].x, lay.pts[a].z - lay.pts[j].z).length()
				cands.append([span * STEP - chord, a, span, signf(turning)])
	cands.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	var made := 0
	for c: Array in cands:
		if made >= 2:
			break
		var a: int = c[1]
		var b_i := lay.idx(a + c[2])
		if _near_mouth(lay, a, 30) or _near_mouth(lay, b_i, 30) or not _level_run(lay, a, 4, 60.0) \
				or not _level_run(lay, b_i, 4, 60.0):
			continue
		var s: float = c[3]
		var pa := Vector2(lay.pts[a].x, lay.pts[a].z) + Vector2(lay.flat_right[a].x, lay.flat_right[a].z) * s * ROAD_HALF
		var pb := Vector2(lay.pts[b_i].x, lay.pts[b_i].z) + Vector2(lay.flat_right[b_i].x, lay.flat_right[b_i].z) * s * ROAD_HALF
		var da := Vector2(lay.fwd[a].x, lay.fwd[a].z) * cos(0.4) + Vector2(lay.flat_right[a].x, lay.flat_right[a].z) * s * sin(0.4)
		var db := Vector2(lay.fwd[b_i].x, lay.fwd[b_i].z) * cos(0.4) - Vector2(lay.flat_right[b_i].x, lay.flat_right[b_i].z) * s * sin(0.4)
		var l := pa.distance_to(pb)
		var xz := _bezier(pa, pa + da * l * 0.4, pb - db * l * 0.4, pb)
		if (xz.size() - 1) * BSTEP > c[2] * STEP * 0.97:
			continue
		# The nearest node creeps steadily from one end to the other.
		var prev := 0
		var steady := true
		for p in xz:
			var ci := lay.closest(p.x, p.y)
			var rel := posmod(ci - a, n)
			if ci < 0 or rel > c[2] + 3 or rel < prev - 2:
				steady = false
				break
			prev = maxi(prev, rel)
		if not steady:
			continue
		var br := Branch.new()
		br.kind = "shortcut"
		br.half = 3.2
		br.from = a
		br.to = b_i
		br.side = s
		if _fit(lay, br, xz, lay.road_y(b_i, s, ROAD_HALF) + 0.02, 0.1):
			lay.add_branch(br)
			made += 1


## Points every BSTEP m along a cubic Bezier.
static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedVector2Array:
	var dense := PackedVector2Array()
	for k in 401:
		var t := k / 400.0
		var u := 1.0 - t
		dense.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	var total := 0.0
	for k in 400:
		total += dense[k].distance_to(dense[k + 1])
	var m := maxi(int(roundf(total / BSTEP)), 2)
	var step := total / m
	var out := PackedVector2Array([p0])
	var acc := 0.0
	var want := step
	for k in 400:
		var seg := dense[k].distance_to(dense[k + 1])
		while acc + seg >= want and out.size() < m:
			out.append(dense[k].lerp(dense[k + 1], (want - acc) / seg))
			want += step
		acc += seg
	out.append(p3)
	return out


## Heights for a branch along `xz` (leaving the road at `b.from`): the land's, smoothed and
## no steeper than `grade`, level with the road for its first stretch (and its last, joining
## the road again at `end_y`). False, and nothing set, where it would need a deep cutting or
## a high bank, run into the water or come near the road or another branch.
static func _fit(lay: Layout, b: Branch, xz: PackedVector2Array, end_y := NAN, grade := 0.1) -> bool:
	var m := xz.size()
	for k in range(-4, 5):
		if lay.kind[lay.idx(b.from + k)] != Kind.OPEN or b.to >= 0 and lay.kind[lay.idx(b.to + k)] != Kind.OPEN:
			return false
	var raw := PackedFloat32Array()
	for p in xz:
		raw.append(lay.natural(p.x, p.y))
	var nat := PackedFloat32Array()
	for k in m:
		var sum := 0.0
		var wsum := 0.0
		for d in range(-4, 5):
			var w := exp(-float(d * d) / 8.0)
			sum += raw[clampi(k + d, 0, m - 1)] * w
			wsum += w
		nat.append(sum / wsum)
	var y0 := lay.road_y(b.from, b.side, ROAD_HALF) + 0.02
	var y := PackedFloat32Array()
	y.resize(m)
	y[0] = y0
	for k in range(1, m):
		var g := _mouth_grade(k * BSTEP, grade) * BSTEP
		y[k] = clampf(nat[k] + 0.15, y[k - 1] - g, y[k - 1] + g)
	if not is_nan(end_y):
		y[m - 1] = end_y
		for k in range(m - 2, -1, -1):
			var g := _mouth_grade((m - 1 - k) * BSTEP, grade) * BSTEP
			y[k] = clampf(y[k], y[k + 1] - g, y[k + 1] + g)
		if absf(y[0] - y0) > 0.05:
			return false
	var total := (m - 1) * BSTEP
	var out := PackedVector3Array()
	for k in m:
		var along := k * BSTEP
		var p := Vector3(xz[k].x, y[k], xz[k].y)
		if absf(y[k] - 0.15 - raw[k]) > 7.0 or y[k] < lay.water + 2.0:
			return false
		var skip: Array[int] = []
		if along < 30.0 or not is_nan(end_y) and total - along < 30.0:
			skip = [b.from, b.to]
		if not _clear_of_lap(lay, p, b.half + 1.5, skip):
			return false
		if along > 12.0 and (is_nan(end_y) or total - along > 12.0) and lay.branch_at(p.x, p.z).x < b.half + 12.0:
			return false
		out.append(p)
	b.pts = out
	return true


## The steepest a branch may climb or fall `along` m from where it meets the road: level
## across the verge, gently for a few metres more, then up to `grade`.
static func _mouth_grade(along: float, grade: float) -> float:
	return 0.002 if along <= 8.0 else (0.015 if along < 18.0 else grade)


## Whether `p` stands `r` m clear of the road's walls (nodes within 8 of those in `skip` aside).
static func _clear_of_lap(lay: Layout, p: Vector3, r: float, skip: Array[int]) -> bool:
	for i in lay.nearby(p.x, p.z):
		var near := false
		for c in skip:
			if c >= 0 and mini(posmod(i - c, lay.n), posmod(c - i, lay.n)) <= 8:
				near = true
		if near:
			continue
		var v := Vector3(p.x - lay.pts[i].x, 0.0, p.z - lay.pts[i].z)
		var lat := v.dot(lay.flat_right[i])
		var wall := lay.wall_r[i] if lat > 0.0 else lay.wall_l[i]
		if absf(v.dot(lay.fwd[i])) <= STEP and absf(lat) < wall + r:
			return false
	return true

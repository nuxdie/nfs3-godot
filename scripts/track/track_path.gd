class_name TrackPath
## Closed-loop centre line of a track ("virtual road"): used for AI steering,
## race progress, respawning and invisible side walls.

var points := PackedVector3Array()
var rights := PackedVector3Array()   # unit vector pointing to the driver's right
var ups := PackedVector3Array()
var left_width := PackedFloat32Array()  # distance from centre to left wall
var right_width := PackedFloat32Array()
var cumulative := PackedFloat32Array()  # distance along the path at each node
var radius := PackedFloat32Array()      # bend radius around each node (m), for AI speeds
var length := 0.0
## How far past a wall a car off the drivable surface may get before the race resets it
## (the procedural track has no walls, so its cars can roam out onto the land).
var lost_margin := 5.0
## Where solid scenery stands on the road (a pillar, a tree, a median): set by scan_obstacles().
## Per node, whether anything blocks any of the road there, and a bit per metre of offset
## (bit k = offset k - SPAN) for whether a car fits there: road underneath, nothing in the way.
var obstructed := PackedByteArray()
var clear_bits := PackedInt64Array()
const SPAN := 20


func size() -> int:
	return points.size()


func finalize() -> void:
	var n := points.size()
	cumulative.resize(n)
	var d := 0.0
	for i in n:
		cumulative[i] = d
		d += points[i].distance_to(points[(i + 1) % n])
	length = d
	# Bend radius from the change of heading across a few nodes either side (on the ground
	# plane, so crests and dips don't count as bends).
	radius.resize(n)
	for i in n:
		var a := points[idx(i - 2)] - points[idx(i - 3)]
		var b := points[idx(i + 3)] - points[idx(i + 2)]
		var ang := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		var arc := fposmod(cumulative[idx(i + 3)] - cumulative[idx(i - 3)], length)
		radius[i] = minf(arc / maxf(absf(ang), 0.001), 2000.0)


func idx(i: int) -> int:
	var n := points.size()
	return ((i % n) + n) % n


## The node at least `metres` further along the road from `n` in direction `dir`.
func ahead(n: int, dir: int, metres: float) -> int:
	var m := n
	for k in points.size():
		m = idx(m + dir)
		if fposmod((cumulative[m] - cumulative[n]) * dir, length) >= metres:
			break
	return m


func forward(i: int) -> Vector3:
	return (points[idx(i + 1)] - points[idx(i)]).normalized()


## Closest node to `pos`. Pass the previous result as `hint` for a cheap local search.
func closest(pos: Vector3, hint := -1, window := 24) -> int:
	var n := points.size()
	var best := 0
	var best_d := INF
	if hint < 0:
		for i in n:
			var dd := points[i].distance_squared_to(pos)
			if dd < best_d:
				best_d = dd
				best = i
		return best
	# Walk each way from the hint while it keeps getting closer, carrying on over a few nodes
	# that don't (the spacing is uneven) - a car moves under a node a tick, so this is a
	# handful of distances rather than the whole window's.
	hint = ((hint % n) + n) % n
	best = hint
	best_d = points[hint].distance_squared_to(pos)
	for dir in [1, -1]:
		var i := hint
		var misses := 0
		for k in window:
			i += dir
			if i >= n:
				i -= n
			elif i < 0:
				i += n
			var dd := points[i].distance_squared_to(pos)
			if dd < best_d:
				best_d = dd
				best = i
				misses = 0
			else:
				misses += 1
				if misses > 4:
					break
	return best


## Distance along the lap for a position near node `i` (projected between i and i+1).
func progress_at(pos: Vector3, i: int) -> float:
	var a := points[i]
	var seg := points[idx(i + 1)] - a
	var t := clampf((pos - a).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
	return cumulative[i] + seg.length() * t


## Signed lateral offset from the centre line (positive = right).
func lateral(pos: Vector3, i: int) -> float:
	return (pos - points[i]).dot(rights[i])


## Transform standing on the road at node `i`, shifted `offset` metres right.
## Cars face local +Z, so the basis' +Z points along the path.
func transform_at(i: int, offset := 0.0, height := 0.8) -> Transform3D:
	i = idx(i)
	var fwd := forward(i)
	var up := ups[i] if ups.size() > i else Vector3.UP
	var basis := Basis.looking_at(-fwd, up)
	return Transform3D(basis, points[i] + rights[i] * offset + up * height)


## Probes the road at every node for solid scenery standing on it, for free_offset().
## Needs the track's collision in the physics space.
func scan_obstacles(space: PhysicsDirectSpaceState3D) -> void:
	var n := points.size()
	obstructed.resize(n)
	obstructed.fill(0)
	clear_bits.resize(n)
	clear_bits.fill(-1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = 1 | Nfs3TrackBuilder.SCENERY_LAYER
	var box := BoxShape3D.new()
	q.shape = box
	for i in n:
		var seg := points[i].distance_to(points[idx(i + 1)])
		var lw := minf(left_width[i], SPAN)
		var rw := minf(right_width[i], SPAN)
		# One box across the whole road from knee to roof height first: most nodes have nothing.
		var xf := transform_at(i, (rw - lw) * 0.5, 1.2)
		box.size = Vector3(lw + rw, 1.6, maxf(seg, 1.0))
		q.transform = xf
		if not _solid_in(space, q):
			continue
		obstructed[i] = 1
		var bits := 0
		box.size = Vector3(1.0, 1.6, maxf(seg, 1.0))
		for k in 2 * SPAN + 1:
			var off := float(k - SPAN)
			if off < -lw or off > rw:
				continue
			q.transform = transform_at(i, off, 1.2)
			if not _solid_in(space, q) and _road_under(space, transform_at(i, off, 0.0).origin, ups[i] if ups.size() > i else Vector3.UP):
				bits |= 1 << k
		clear_bits[i] = bits


## Whether the query box overlaps anything a car would hit (not the road or the land it's on).
static func _solid_in(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D) -> bool:
	for hit in space.intersect_shape(q, 8):
		var body := hit.collider as Node
		if body and body.name != "Road" and body.name != "Terrain":
			return true
	return false


static func _road_under(space: PhysicsDirectSpaceState3D, p: Vector3, up: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + up * 2.0, p - up * 2.0, 1)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit.collider.name == "Road"


## Whether a car driving straight from `pos` (near node `from`) to `off` metres right of the
## line at node `to` (stepping by `dir`) keeps clear of the scenery scan_obstacles() found:
## on a bend the straight line cuts across the inside, where a row of pillars can stand.
func chord_clear(pos: Vector3, from: int, to: int, off: float, dir: int) -> bool:
	if obstructed.is_empty():
		return true
	var target := points[to] + rights[to] * off
	var span := fposmod((cumulative[to] - cumulative[from]) * dir, length)
	var i := idx(from + dir)
	while i != to:
		if obstructed[i] and clear_bits[i] != 0:
			var f := fposmod((cumulative[i] - cumulative[from]) * dir, length) / maxf(span, 0.1)
			# The car's width either side of where the line crosses this node.
			var k := roundi(lateral(pos.lerp(target, f), i)) + SPAN
			if k < 1 or k > 2 * SPAN - 1 or (clear_bits[i] >> (k - 1)) & 7 != 7:
				return false
		i = idx(i + dir)
	return true


## The lateral offset nearest `want` (and the car's own `current` one) where a car gets
## through clear of scenery on every node from `from` to `to` (stepping by `dir`), within
## `lo`..`hi`. `want` itself when nothing stands in the way, or nothing is clear.
func free_offset(from: int, to: int, dir: int, want: float, current: float, lo: float, hi: float) -> float:
	if obstructed.is_empty():
		return want
	var mask := -1
	var any := false
	var i := from
	while true:
		# Nowhere clear at all (the deck of a bridge isn't the road body): nothing to go by.
		if obstructed[i] and clear_bits[i] != 0:
			any = true
			mask &= clear_bits[i]
		if i == to:
			break
		i = idx(i + dir)
	if not any:
		return want
	# A car's width and a margin for steering either side: the metre it's on and two each side.
	var w := roundi(want) + SPAN
	if w >= 2 and w <= 2 * SPAN - 2 and (mask >> (w - 2)) & 31 == 31:
		return want
	var best := want
	var best_cost := INF
	for k in range(2, 2 * SPAN - 1):
		var off := float(k - SPAN)
		if off < lo or off > hi or (mask >> (k - 2)) & 31 != 31:
			continue
		# Prefer the side the car is already on, so it doesn't flip between two gaps.
		var cost := absf(off - want) + 0.7 * absf(off - current)
		if cost < best_cost:
			best_cost = cost
			best = off
	return best

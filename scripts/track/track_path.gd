class_name TrackPath
## Centre line of a track ("virtual road"): used for AI steering, race progress,
## respawning and invisible side walls. A closed loop, or (Porsche Unleashed's point-to-point
## runs) an open road whose start and finish lines are nodes along it (see set_open()).

var points := PackedVector3Array()
var rights := PackedVector3Array()   # unit vector pointing to the driver's right
var ups := PackedVector3Array()
var left_width := PackedFloat32Array()  # distance from centre to left wall
var right_width := PackedFloat32Array()
## Where the invisible walls stand where that's further out than the road's edges above
## (which the AI, the grid and respawns keep to): Porsche Unleashed's stand behind the verges.
## Empty: at the road's edges (see wall_width()).
var wall_left := PackedFloat32Array()
var wall_right := PackedFloat32Array()
var cumulative := PackedFloat32Array()  # distance along the path at each node
var radius := PackedFloat32Array()      # bend radius around each node (m), for AI speeds
## The original game's AI tables, [forward, reverse] (either may be empty): target speed
## at each node (m/s, for a top car), and High Stakes' racing line (m right of the centre).
var ai_speeds := [PackedFloat32Array(), PackedFloat32Array()]
var racing_line := [PackedFloat32Array(), PackedFloat32Array()]
## Traffic lanes per node (either may be empty, see lane_offset()): a byte per node, the
## lanes left of the centre line in the high nibble and right of it in the low one, and
## each side's lane width (m).
var lanes := PackedByteArray()
var lane_width_left := PackedFloat32Array()
var lane_width_right := PackedFloat32Array()
## The speed limit at each node (m/s), where the original game has one for the track.
var legal_speed := PackedFloat32Array()
var length := 0.0
## False for an open road: node indices stop at its ends instead of wrapping round.
var closed := true
## An open road's start and finish nodes, and the other way round's ([start, finish] each).
var start_node := 0
var finish_node := 0
var _other_way := Vector2i(-1, -1)
## How far past a wall a car off the drivable surface may get before the race resets it
## (the procedural track has no walls, so its cars can roam out onto the land).
var lost_margin := 5.0
## Where solid scenery stands on the road (a pillar, a tree, a median): set by scan_obstacles().
## Per node, whether anything blocks any of the road there, and a bit per metre of offset
## (bit k = offset k - SPAN) for whether a car fits there: road underneath, nothing in the way.
var obstructed := PackedByteArray()
var clear_bits := PackedInt64Array()
const SPAN := 20
## Other roads the walls leave open onto (Porsche Unleashed's shortcuts and side streets):
## their slices by XZ cell (SIDE_CELL), [position, right, left wall, right wall] each.
var side_roads := {}
const SIDE_CELL := 16.0
var _side_wall := 0.0   # the widest of their walls (m from a slice)


func size() -> int:
	return points.size()


## How far from the centre line the wall on that side (`side` > 0: the right) stands at node `i`.
func wall_width(i: int, side: float) -> float:
	if side > 0.0:
		return wall_right[i] if wall_right.size() == points.size() else right_width[i]
	return wall_left[i] if wall_left.size() == points.size() else left_width[i]


func add_side_slice(pos: Vector3, right: Vector3, left_wall: float, right_wall: float) -> void:
	side_roads.get_or_add(Vector2i(floori(pos.x / SIDE_CELL), floori(pos.z / SIDE_CELL)), []).append(
		[pos, right, left_wall, right_wall])
	_side_wall = maxf(_side_wall, maxf(left_wall, right_wall))


## Whether `pos` is on one of the side roads, between its walls near one of its slices, or
## off one by no more than `margin` m (past a wall or an end) and `height` m above or below it.
func on_side_road(pos: Vector3, margin := 1.0, height := 6.0) -> bool:
	if side_roads.is_empty():
		return false
	var c := Vector2i(floori(pos.x / SIDE_CELL), floori(pos.z / SIDE_CELL))
	# A slice whose band `pos` is in reach of is at most its wall and the margin away.
	var reach := ceili((_side_wall + margin) / SIDE_CELL)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for e: Array in side_roads.get(c + Vector2i(dx, dz), []):
				var d: Vector3 = pos - e[0]
				if absf(d.y) >= height:
					continue
				var flat := Vector2(d.x, d.z)
				var right := Vector2(e[1].x, e[1].z).normalized()
				var lat := flat.dot(right)
				var along := absf(flat.dot(right.orthogonal()))
				var out := Vector2(maxf(maxf(lat - e[3], -e[2] - lat), 0.0), maxf(along - SIDE_CELL * 0.5, 0.0))
				if out.length() <= margin:
					return true
	return false


## Where to put a car down that's on or by a side road (within `margin` m of its band): on
## the nearest of its slices, as far out as the car was but within a lane's reach of the
## middle, facing the way `heading` goes along it. Transform3D() (a zero basis) if there's none.
func side_road_spot(pos: Vector3, heading: Vector3, margin := 15.0) -> Transform3D:
	var best: Array = []
	var best_d := INF
	var c := Vector2i(floori(pos.x / SIDE_CELL), floori(pos.z / SIDE_CELL))
	var reach := ceili((_side_wall + margin) / SIDE_CELL)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for e: Array in side_roads.get(c + Vector2i(dx, dz), []):
				var d: float = pos.distance_to(e[0])
				if d < best_d and absf(pos.y - e[0].y) < 8.0:
					best_d = d
					best = e
	if best.is_empty() or not on_side_road(pos, margin, 8.0):
		return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	var right := Vector3(best[1].x, 0.0, best[1].z).normalized()
	var fwd := Vector3.UP.cross(right)
	if fwd.dot(heading) < 0.0:
		fwd = -fwd
	var lat := clampf((pos - best[0]).dot(right), -minf(best[2], 2.5), minf(best[3], 2.5))
	return Transform3D(Basis.looking_at(-fwd, Vector3.UP), best[0] + right * lat)


## Runs the lap the other way round (the "reverse" option): node 0, the start line, stays
## put and the rest come in the opposite order, their right to the other side. The AI
## tables swap too, each way's to the other.
func reverse() -> void:
	var n := points.size()
	# An open road runs from its far end; its lines swap for the other way's.
	var from := n - 1 if not closed else n
	var order := func(a: Variant) -> Variant:
		var out: Variant = a.duplicate()
		for i in n:
			out[i] = a[(from - i) % n]
		return out
	if not closed:
		var fwd := Vector2i(start_node, finish_node)
		start_node = n - 1 - _other_way.x
		finish_node = n - 1 - _other_way.y
		_other_way = Vector2i(n - 1 - fwd.x, n - 1 - fwd.y)
	points = order.call(points)
	ups = order.call(ups)
	var r: PackedVector3Array = order.call(rights)
	for i in n:
		r[i] = -r[i]
	rights = r
	var lw: PackedFloat32Array = order.call(right_width)
	right_width = order.call(left_width)
	left_width = lw
	if wall_left.size() == n:
		var wl: PackedFloat32Array = order.call(wall_right)
		wall_right = order.call(wall_left)
		wall_left = wl
	if lanes.size() == n:
		var ln: PackedByteArray = order.call(lanes)
		for i in n:
			ln[i] = (ln[i] >> 4) | ((ln[i] & 0xF) << 4)
		lanes = ln
		var llw: PackedFloat32Array = order.call(lane_width_right)
		lane_width_right = order.call(lane_width_left)
		lane_width_left = llw
	if legal_speed.size() == n:
		legal_speed = order.call(legal_speed)
	var speeds := []
	var lines := []
	for k in [1, 0]:
		speeds.append(order.call(ai_speeds[k]) if ai_speeds[k].size() == n else PackedFloat32Array())
		lines.append(order.call(racing_line[k]) if racing_line[k].size() == n else PackedFloat32Array())
	ai_speeds = speeds
	racing_line = lines
	finalize()


## Makes this an open road with these nodes as [start, finish, the other way's start, its
## finish] (Nfs5Track.sprint).
func set_open(lines: PackedInt32Array) -> void:
	closed = false
	start_node = lines[0]
	finish_node = lines[1]
	_other_way = Vector2i(lines[2], lines[3])
	finalize()


func finalize() -> void:
	var n := points.size()
	cumulative.resize(n)
	var d := 0.0
	for i in n:
		cumulative[i] = d
		if closed or i < n - 1:
			d += points[i].distance_to(points[(i + 1) % n])
	# An open road's length is to its far end; fposmod over it leaves its distances be.
	length = d if closed else d + 1.0
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
	if not closed:
		return clampi(i, 0, n - 1)
	return ((i % n) + n) % n


## The node at least `metres` further along the road from `n` in direction `dir`.
func ahead(n: int, dir: int, metres: float) -> int:
	var m := n
	for k in points.size():
		if not closed and m == idx(m + dir):
			break
		m = idx(m + dir)
		if fposmod((cumulative[m] - cumulative[n]) * dir, length) >= metres:
			break
	return m


## Traffic lanes at node `n` on `side` of the centre line (+1 right, -1 left).
func lane_count(n: int, side: int) -> int:
	if lanes.size() != points.size():
		return 1
	var c: int = lanes[n] & 0xF if side > 0 else lanes[n] >> 4
	return maxi(c, 1)


## Lateral offset (m, + right) of the middle of traffic lane `k` (1 the nearest the centre
## line; past the last lane there, the last) at node `n` on `side` of the centre line (+1
## right, -1 left). Without lane data, one lane a little way out from the centre.
func lane_offset(n: int, side: int, k: int) -> float:
	var wall: float = right_width[n] if side > 0 else left_width[n]
	var w := 0.0
	if lanes.size() == points.size():
		w = lane_width_right[n] if side > 0 else lane_width_left[n]
	if not (w > 1.5 and w < 12.0):
		return side * clampf(minf(left_width[n], right_width[n]) * 0.4, 2.5, 4.5)
	k = clampi(k, 1, lane_count(n, side))
	return side * minf(w * (k - 0.5), maxf(wall - 2.0, w * 0.5))


func forward(i: int) -> Vector3:
	i = idx(i)
	var j := idx(i + 1)
	# An open road's last node looks on from the one before it.
	if j == i:
		return (points[i] - points[idx(i - 1)]).normalized()
	return (points[j] - points[i]).normalized()


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


## The node nearest `pos` from `back` nodes behind `hint` to `ahead` in front of it, every
## one looked at: for a car away from the lap (on a shortcut), where closest()'s walk from
## the hint stops at the first hump in the distances.
func closest_along(pos: Vector3, hint: int, back: int, ahead: int) -> int:
	var n := points.size()
	var best := hint
	var best_d := INF
	for k in range(hint - back, hint + ahead + 1):
		if not closed and (k < 0 or k >= n):
			continue
		var i := posmod(k, n)
		var dd := points[i].distance_squared_to(pos)
		if dd < best_d:
			best_d = dd
			best = i
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

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
	for k in range(-window, window + 1):
		var i := idx(hint + k)
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

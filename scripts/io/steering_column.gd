class_name SteeringColumn
## The steering wheel's column for car.gdshader, from the triangles a model marks as turning.
## Some models mark more than the wheel: Porsche Unleashed's 356s and several Hot Pursuit 2
## cars (911 Turbo, Barchetta, Carrera GT, Elise, VX220...) put the column, or its shroud,
## running forward from the hub into the dash, in with it. That part turned too, swinging
## round under the dash, and it dragged the pivot forward and tilted the axis besides.
##
## The wheel is a flat ring: the column is the way its corners spread least (Nfs6Car's
## approach, in the plane they spread most), pointing forward. What reaches further forward
## than REACH from that plane stays put, the fit made again without it, closing in from
## further out (a fit dragged off by a long column has the rim's edges well off its plane).
## The rest turns about the middle of the rim.

const REACH: Array[float] = [0.15, 0.1, 0.07, 0.07]   # m ahead of the plane a turning triangle may reach


## `pos` a triangle soup, `turns` the first vertex of each triangle marked as turning.
## Returns {pivot, axis (pointing forward), dropped (the triangles of `turns` that don't
## turn after all)}, or {} without any.
static func fit(pos: PackedVector3Array, turns: PackedInt32Array) -> Dictionary:
	if turns.is_empty():
		return {}
	var kept := turns
	var plane := _plane(pos, kept)
	for reach in REACH:
		var next := PackedInt32Array()
		for i in turns:
			var ahead := maxf(pos[i].dot(plane.axis), maxf(pos[i + 1].dot(plane.axis), pos[i + 2].dot(plane.axis)))
			if ahead <= plane.at + reach:
				next.append(i)
		if next.is_empty():
			break
		kept = next
		plane = _plane(pos, kept)
	var dropped := PackedInt32Array()
	var box := AABB(pos[kept[0]], Vector3.ZERO)
	var j := 0
	for i in turns:
		if j < kept.size() and kept[j] == i:
			j += 1
			for k in 3:
				box = box.expand(pos[i + k])
		else:
			dropped.append(i)
	# (The rim's the outside of the wheel all round: its box's middle is the hub's, whichever
	# way the spokes go.)
	return {"pivot": box.get_center(), "axis": plane.axis, "dropped": dropped}


## {axis, at (where the plane is along it: its corners' median)} of the triangles `tris`,
## each corner once (a soup repeats them).
static func _plane(pos: PackedVector3Array, tris: PackedInt32Array) -> Dictionary:
	var seen := {}
	var pts := PackedVector3Array()
	for i in tris:
		for k in 3:
			var q := Vector3i((pos[i + k] * 1000.0).round())
			if not seen.has(q):
				seen[q] = true
				pts.append(pos[i + k])
	var mid := Vector3.ZERO
	for v in pts:
		mid += v
	mid /= pts.size()
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for v in pts:
		var d := v - mid
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	# The smallest eigenvector: power iteration on the inverse's stand-in (trace I - C).
	var tr := cov.x.x + cov.y.y + cov.z.z
	var m := Basis(Vector3(tr, 0, 0), Vector3(0, tr, 0), Vector3(0, 0, tr))
	m.x -= cov.x
	m.y -= cov.y
	m.z -= cov.z
	var axis := Vector3(0.1, 0.2, 1.0).normalized()
	for k in 64:
		axis = (m * axis).normalized()
	axis = axis if axis.z > 0.0 else -axis
	var at := PackedFloat32Array()
	for v in pts:
		at.append(v.dot(axis))
	at.sort()
	return {"axis": axis, "at": at[at.size() / 2]}

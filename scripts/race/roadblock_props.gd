class_name RoadblockProps
## What High Stakes lays out round a roadblock's cruisers (its GameArt models): a line of
## cones funnelling traffic toward the gap, concrete medians along both edges of the road
## short of it (no cutting past on the shoulder; the cruisers shuffle across, so the way
## through can open on either side and nothing solid stands across the road), hay bales by
## the cruisers, and flares burning on the tarmac in front, lighting it after dark.

const CONE_SPACING := 2.2   # m between cones
const FLARE_LIGHT := Color(1.0, 0.25, 0.1)


## Props for a roadblock at node `n` of `path`: the gap on side `gap_side` (+1 right),
## `w` the road's half width there, `gap_edge` and `far_edge` how far out the tarmac goes on
## either side.
## Returns the nodes it added under `parent` (to free with the roadblock).
static func build(parent: Node3D, path: TrackPath, n: int, gap_side: float, w: float, gap_edge: float,
		far_edge: float, night: bool) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var cone := Game.hs_prop("cone", "ConeH")
	var median := Game.hs_prop("median")
	var flare := Game.hs_prop("flare")
	if cone:
		# From the far edge, 16 m short of the cruisers, to the middle of the road 4 m short.
		var from := Vector2(-gap_side * (far_edge - 0.6), -16.0)
		var to := Vector2(gap_side * 0.1 * w, -4.0)
		var count := maxi(int(from.distance_to(to) / CONE_SPACING), 2)
		for i in count + 1:
			var at := from.lerp(to, float(i) / count)
			out.append(_knockable(parent, cone, _on_road(parent, path, n, at.x, at.y)))
	if median:
		# End to end along each edge, from 20 m short of the cruisers to 4 m short.
		var length := median.get_aabb().size.x
		for side in [gap_side, -gap_side]:
			var edge: float = gap_edge if side == gap_side else far_edge
			var z := -20.0
			while z + length <= -4.0:
				var xf := _on_road(parent, path, n, side * (edge - 0.4), z + length * 0.5)
				# Its length along the road.
				xf.basis = xf.basis * Basis(Vector3.UP, PI * 0.5)
				out.append(_solid(parent, median, xf))
				z += length
	var bale := Game.hs_prop("haybale")
	if bale:
		# Just beyond the outer cruiser's end (parked across the road, ~2.4 m each side), and
		# in front of the pair where they meet.
		for at in [Vector2(-gap_side * (0.55 * w + 3.4), -1.5), Vector2(-gap_side * 0.25 * w, -3.5)]:
			var xf := _on_road(parent, path, n, at.x, at.y)
			xf.basis = xf.basis * Basis(Vector3.UP, PI * 0.5)
			out.append(_knockable(parent, bale, xf))
	if flare:
		for i in 4:
			var at := Vector2(gap_side * lerpf(-0.7, 0.2, i / 3.0) * w, -22.0 - i * 1.5)
			var xf := _on_road(parent, path, n, at.x, at.y)
			var mi := MeshInstance3D.new()
			mi.mesh = flare
			parent.add_child(mi)
			mi.global_transform = xf
			out.append(mi)
			if night:
				var l := OmniLight3D.new()
				l.light_color = FLARE_LIGHT
				l.omni_range = 7.0
				l.light_energy = 2.5
				l.position = Vector3(0, 0.3, 0)
				mi.add_child(l)
	return out


static func _solid(parent: Node3D, mesh: ArrayMesh, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.get_aabb().size
	cs.shape = box
	cs.position = mesh.get_aabb().get_center()
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = xf
	return body


static func _knockable(parent: Node3D, mesh: ArrayMesh, xf: Transform3D) -> KnockableProp:
	var p := KnockableProp.new()
	p.setup(mesh, null, mesh.get_aabb(), Breakables._hull(mesh), 300.0)
	parent.add_child(p)
	p.global_transform = xf
	return p


## Standing on the road `x` m right of node `n`'s centre line and `z` m along it (the
## cruisers face across the road; props face along it), put down on whatever's below.
static func _on_road(parent: Node3D, path: TrackPath, n: int, x: float, z: float) -> Transform3D:
	var xf := path.transform_at(n, x, 0.0)
	xf.origin += xf.basis.z * z
	var space := parent.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			xf.origin + xf.basis.y * 3.0, xf.origin - xf.basis.y * 5.0, 1))
	if not hit.is_empty():
		xf.origin = hit.position
	return xf

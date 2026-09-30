class_name CarDebris
extends KnockableProp
## A piece torn off a car in a crash (Car.tear_off): a door, lid, skirt or spoiler, dents
## and all, flung off the way the car was going and left lying where it lands, for the
## other cars to bump. It's loose from the start (never standing, as a KnockableProp is),
## and like one it isn't a crash to the cars that hit it (CarDamage skips it).

## The most pieces left lying about at once: past it the oldest goes.
const MAX_PIECES := 40
## kg of a piece per metre across it (a door comes out around 25).
const MASS_PER_M := 16.0

static var _pieces: Array[CarDebris] = []


## `nodes` (the car's meshes) off `car`, as they are on it this moment, into a loose piece
## beside it. Null (and the nodes gone) if none of them is showing.
static func launch(car: Car, nodes: Array) -> CarDebris:
	var pts := PackedVector3Array()
	for n in nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	var parent := car.get_parent()
	if pts.is_empty() or parent == null:
		for n: Node in nodes:
			n.queue_free()
		return null
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var d := CarDebris.new()
	d.name = "Debris"
	parent.add_child(d)
	d.global_transform = Transform3D(car.global_basis, box.get_center())
	var to_local := d.global_transform.affine_inverse()
	for n: Node3D in nodes:
		n.reparent(d, true)
		# (Seen from inside the car its own bodywork is kept off the main view: not now.)
		var g := n as GeometryInstance3D
		if g:
			g.layers = Car.VISUAL_LAYER
			if g.has_meta("shadow"):
				g.cast_shadow = g.get_meta("shadow")
	var hull := PackedVector3Array()
	for p in pts:
		hull.append(to_local * p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	var cs := CollisionShape3D.new()
	cs.shape = shape
	d.add_child(cs)
	d._fling(car, box.size.length())
	_pieces.append(d)
	while _pieces.size() > MAX_PIECES:
		var old: CarDebris = _pieces.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


func _fling(car: Car, across: float) -> void:
	mass = clampf(across * MASS_PER_M, 3.0, 40.0)
	collision_layer = 2
	collision_mask = 1 | 2 | Nfs3TrackBuilder.SCENERY_LAYER
	continuous_cd = true   # (thin: a door would drop through the road)
	angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.15
	physics_material_override = pm
	# It starts inside the car's box: the car it came off doesn't feel it.
	add_collision_exception_with(car)
	# Off with the car's own speed there, a little behind it, out from its middle and up.
	var r := global_position - car.global_position
	var out := Vector3(r.x, 0.0, r.z).normalized()
	linear_velocity = (car.linear_velocity + car.angular_velocity.cross(r)) * randf_range(0.75, 0.9) \
			+ out * randf_range(1.5, 3.5) + Vector3.UP * randf_range(1.0, 3.0)
	angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0


func _exit_tree() -> void:
	_pieces.erase(self)

class_name CarDamage
extends Node
## Crash damage (NFS3 itself had none; this is in the spirit of High Stakes): a hard hit
## dents the body around the point of impact, takes some power off the engine and knocks
## the steering out of line. Nothing is repaired until the race is restarted. Add as a
## child of the Car after setup().

const MIN_HIT := 4.0        # m/s of velocity change into a contact before anything bends
const FULL_HIT := 22.0      # ... and the hit that does the most one crash can
const DENT_RADIUS := 0.6    # m around the impact point that gives (a full hit)
const DENT_DEPTH := 0.26    # m a full hit pushes in at the centre
const MAX_DENT := 0.4       # m any vertex can be pushed in over the race
const HIT_WEAR := 0.14      # overall damage from one full hit
const MAX_PULL := 0.05      # steering pull at its worst, as a fraction of the lock

var damage := 0.0           # 0..1 overall, mirrored into the car's handling

var _car: Car
var _parts: Array[Dictionary] = []   # {mi, mesh (own copy), surfaces: [{arrays, rest, material}]}
var _prev_vel := Vector3.ZERO
var _cooldown := 0.0
var _mid_y := 0.0           # middle of the body's collision box, car-local


func _ready() -> void:
	_car = get_parent() as Car
	damage = _car.damage   # what the car file starts it with
	_prev_vel = _car.linear_velocity
	_car.was_reset.connect(func() -> void: _prev_vel = Vector3.ZERO)
	for c in _car.get_children():
		if c is CollisionShape3D:
			_mid_y = c.position.y
	for mi in _car.body_meshes():
		var src := mi.mesh
		var surfaces: Array[Dictionary] = []
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			surfaces.append({"arrays": arrays, "rest": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
				"normals": arrays[Mesh.ARRAY_NORMAL], "material": src.surface_get_material(s)})
		if not surfaces.is_empty():
			# Loaded cars share their meshes between everyone driving that model: dent a copy.
			_parts.append({"mi": mi, "mesh": ArrayMesh.new(), "surfaces": surfaces})


func _physics_process(dt: float) -> void:
	# The body collides as a box, so the solver's change to the car's velocity across the
	# step is the crash: pushed back hard along a contact's normal means a hit there.
	var v := _car.linear_velocity
	var dv := v - _prev_vel
	_prev_vel = v
	_cooldown = maxf(_cooldown - dt, 0.0)
	if _cooldown > 0.0 or dv.length() < MIN_HIT:
		return
	var st := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	if st == null:
		return
	var best := MIN_HIT
	var at := Vector3.ZERO
	var inward := Vector3.ZERO
	for i in st.get_contact_count():
		if st.get_contact_collider_object(i) is KnockableProp:
			continue
		var pos := st.get_contact_local_position(i)   # global, despite the name
		var n := st.get_contact_local_normal(i)
		if n.dot(_car.global_position - pos) < 0.0:
			n = -n
		if dv.dot(n) > best:
			best = dv.dot(n)
			at = pos
			inward = n
	if inward != Vector3.ZERO:
		_cooldown = 0.12   # one crash reports over several steps and contact points
		hit(at, inward, best)


## A crash at world point `at`, pushing along `inward` (into the car) with `strength` m/s.
func hit(at: Vector3, inward: Vector3, strength: float) -> void:
	var s := clampf((strength - MIN_HIT) / (FULL_HIT - MIN_HIT), 0.0, 1.0)
	var p := _car.to_local(at)
	var dir := (_car.global_basis.inverse() * inward).normalized()
	# The body is a box, so a wall's contact comes in on the box's bottom edge, under most of
	# the bodywork: a hit from the side dents at the body's mid-height instead.
	if absf(dir.y) < 0.5:
		p.y = _mid_y
	p = _nearest_vertex(p)
	var radius := DENT_RADIUS * lerpf(0.6, 1.0, s)
	var depth := DENT_DEPTH * lerpf(0.25, 1.0, s)
	_dent(p, dir, radius, depth)
	for n in _car.fittings():
		var f := 1.0 - n.position.distance_to(p) / radius
		if f > 0.0:
			n.position += dir * depth * f * f * (3.0 - 2.0 * f)
	damage = minf(damage + HIT_WEAR * lerpf(0.2, 1.0, s), 1.0)
	_car.damage = damage
	# A knock to a front corner bends the steering toward that side (+X is the driver's left).
	if p.z > 0.0:
		_car.steer_pull = clampf(_car.steer_pull + signf(p.x) * MAX_PULL * 0.3 * s, -MAX_PULL, MAX_PULL)


## The box's corners stand clear of the rounded bodywork: move the hit onto the body itself.
func _nearest_vertex(p: Vector3) -> Vector3:
	var best := INF
	var out := p
	for part in _parts:
		var o: Vector3 = part.mi.position
		for sf in part.surfaces:
			for v: Vector3 in sf.arrays[Mesh.ARRAY_VERTEX]:
				var d := (v + o).distance_squared_to(p)
				if d < best:
					best = d
					out = v + o
	return out


func _dent(p: Vector3, dir: Vector3, radius: float, depth: float) -> void:
	for part in _parts:
		var mi: MeshInstance3D = part.mi
		var lp := p - mi.position
		var mesh: ArrayMesh = part.mesh
		var changed := false
		for sf in part.surfaces:
			var arrays: Array = sf.arrays
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedVector3Array = sf.rest
			var moved := false
			for i in verts.size():
				var d := verts[i].distance_to(lp)
				if d >= radius:
					continue
				var f := 1.0 - d / radius
				# Crumple rather than a smooth dimple: a fixed per-position jitter (the same for
				# every copy of a vertex, so the unindexed triangles stay joined).
				var r := rest[i]
				var jitter := 0.6 + 0.8 * absf(fmod(sin(r.dot(Vector3(12.99, 78.23, 37.72))) * 43758.55, 1.0))
				var off := verts[i] + dir * depth * f * f * (3.0 - 2.0 * f) * jitter - r
				verts[i] = r + off.limit_length(MAX_DENT)
				moved = true
			if moved:
				arrays[Mesh.ARRAY_VERTEX] = verts
				_crease_normals(arrays, sf)
				changed = true
		if changed:
			mesh.clear_surfaces()
			for sf in part.surfaces:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sf.arrays)
				mesh.surface_set_material(mesh.get_surface_count() - 1, sf.material)
			mi.mesh = mesh


## Bent panels catch the light as flat facets: turn the normals of moved triangles toward
## their face normal, the further the more they were pushed in.
static func _crease_normals(arrays: Array, sf: Dictionary) -> void:
	var orig = sf.normals
	if orig == null or arrays[Mesh.ARRAY_INDEX] != null:
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rest: PackedVector3Array = sf.rest
	var normals: PackedVector3Array = (orig as PackedVector3Array).duplicate()
	for t in range(0, verts.size() - 2, 3):
		var bend := 0.0
		for k in 3:
			bend = maxf(bend, verts[t + k].distance_to(rest[t + k]))
		if bend < 0.005:
			continue
		var fn := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		if fn.dot(orig[t]) < 0.0:
			fn = -fn
		var w := clampf(bend / 0.06, 0.0, 0.8)
		for k in 3:
			normals[t + k] = orig[t + k].lerp(fn, w).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals

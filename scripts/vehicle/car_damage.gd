class_name CarDamage
extends Node
## Crash damage (NFS3 itself had none; this is in the spirit of High Stakes): a hard hit
## dents the body around the point of impact, takes some power off the engine, knocks
## the steering out of line and puts out the lamps near it. High Stakes cars bend toward
## the damaged copy of the body their model carries instead of a made-up crumple, a whole
## panel (bonnet, door, roof...) at a time as that game does. Nothing is repaired until the
## race is restarted (in a tournament the damage stays with the car until it's paid for:
## see wear()). Add as a child of the Car after setup().

const MIN_HIT := 4.0        # m/s of velocity change into a contact before anything bends
const FULL_HIT := 22.0      # ... and the hit that does the most one crash can
const DENT_RADIUS := 0.6    # m around the impact point that gives (a full hit)
const DENT_DEPTH := 0.26    # m a full hit pushes in at the centre
const MAX_DENT := 0.4       # m any vertex can be pushed in over the race
const HIT_WEAR := 0.14      # overall damage from one full hit
const MAX_PULL := 0.05      # steering pull at its worst, as a fraction of the lock
const LAMP_BREAK := 0.25    # the share of a full hit that breaks the lamps near it
## A dent only visits the vertices near it: each surface's are filed in a grid of cells this
## big by where they sit at rest (a vertex is never more than MAX_DENT from there).
const CELL := 0.5

## The grid by model surface ("mesh id:surface"), shared by every car of that model:
## Vector3i cell -> PackedInt32Array of vertex indices.
static var _grid_cache := {}
## Dents waiting for their turn: [CarDamage, car-local point, direction, radius, depth].
static var _queue: Array = []
static var _queue_frame := -1

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
		var damaged: Variant = mi.get_meta("damaged") if mi.has_meta("damaged") else null
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var sf := {"arrays": arrays, "rest": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
				"normals": arrays[Mesh.ARRAY_NORMAL], "material": src.surface_get_material(s),
				"key": "%d:%d" % [src.get_instance_id(), s]}
			# The model's damaged copy, vertex for vertex (one surface): positions, normals and
			# which panels each vertex is on. Each panel's box, and how far it's bent.
			if damaged is Dictionary and s == 0 and (damaged.pos as PackedVector3Array).size() == (sf.rest as PackedVector3Array).size():
				sf.damaged = damaged
				var boxes := {}
				var rest: PackedVector3Array = sf.rest
				var panels: PackedInt32Array = damaged.panels
				for i in rest.size():
					var m := panels[i]
					var b := 0
					while m != 0:
						if m & 1:
							boxes[b] = AABB(rest[i], Vector3.ZERO) if not boxes.has(b) else (boxes[b] as AABB).expand(rest[i])
						m >>= 1
						b += 1
				sf.panel_boxes = boxes
				sf.panel_bent = {}
			surfaces.append(sf)
		if not surfaces.is_empty():
			# Loaded cars share their meshes between everyone driving that model: dent a copy.
			_parts.append({"mi": mi, "mesh": ArrayMesh.new(), "surfaces": surfaces})


func _process(_dt: float) -> void:
	# Whichever car's damage runs first this frame deals with the next dent in line.
	var frame := Engine.get_process_frames()
	if _queue_frame == frame or _queue.is_empty():
		return
	_queue_frame = frame
	var d: Array = _queue.pop_front()
	var who: CarDamage = d[0]
	if is_instance_valid(who):
		who._dent(who._nearest_vertex(d[1]), d[2], d[3], d[4])


func _exit_tree() -> void:
	_queue = _queue.filter(func(d: Array) -> bool: return d[0] != self)


func _physics_process(dt: float) -> void:
	# The body collides as a box, so the solver's change to the car's velocity across the
	# step is the crash: pushed back hard along a contact's normal means a hit there.
	var v := _car.linear_velocity
	if _car.freeze:
		# Parked asleep or moved by hand (far-off traffic): nothing to hit.
		_prev_vel = v
		return
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
		# And whatever the car ran into gives too, if it's a guardrail.
		if absf(inward.y) < 0.5:
			var s := clampf((best - MIN_HIT) / (FULL_HIT - MIN_HIT), 0.0, 1.0)
			get_tree().call_group("guardrails", "hit", at, -inward, s)


## A crash at world point `at`, pushing along `inward` (into the car) with `strength` m/s.
func hit(at: Vector3, inward: Vector3, strength: float) -> void:
	var s := clampf((strength - MIN_HIT) / (FULL_HIT - MIN_HIT), 0.0, 1.0)
	var p := _car.to_local(at)
	var dir := (_car.global_basis.inverse() * inward).normalized()
	# The body is a box, so a wall's contact comes in on the box's bottom edge, under most of
	# the bodywork: a hit from the side dents at the body's mid-height instead.
	if absf(dir.y) < 0.5:
		p.y = _mid_y
	var radius := DENT_RADIUS * lerpf(0.6, 1.0, s)
	var depth := DENT_DEPTH * lerpf(0.25, 1.0, s)
	# Reshaping the body is the costly part: one car's dent a frame, whoever's turn it is,
	# so a pile-up spreads over a few frames instead of stalling one.
	# (Out of sight it isn't seen at all: the car takes the damage without the dent.)
	if not _car.far:
		_queue.append([self, p, dir, radius, depth])
	# Lamps the files mark breakable go out in a hit hard enough to bend them.
	if s >= LAMP_BREAK:
		_car.break_lamps(p, radius)
	for n in _car.fittings():
		var f := 1.0 - n.position.distance_to(p) / radius
		if f > 0.0:
			n.position += dir * depth * f * f * (3.0 - 2.0 * f)
	damage = minf(damage + HIT_WEAR * lerpf(0.2, 1.0, s), 1.0)
	_car.damage = damage
	# A knock to a front corner bends the steering toward that side (+X is the driver's left).
	if p.z > 0.0:
		_car.steer_pull = clampf(_car.steer_pull + signf(p.x) * MAX_PULL * 0.3 * s, -MAX_PULL, MAX_PULL)


## Damage `amount` (0..1) carried over from an earlier race (a tournament's car not repaired
## since): the lost power at once, and dents about the body, more the worse it is.
func wear(amount: float) -> void:
	if amount <= damage:
		return
	damage = clampf(amount, 0.0, 1.0)
	_car.damage = damage
	var box: BoxShape3D = null
	for c in _car.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			box = c.shape
	if box == null:
		return
	var half := box.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_car.display_name)   # the same car, the same dents
	for k in mini(ceili(damage / HIT_WEAR * 1.5), 10):
		# Round the corners and sides, front and back alternately.
		var side := rng.randf_range(-1.0, 1.0)
		var end := 1.0 if k % 2 == 0 else -1.0
		var p := Vector3(side * half.x, _mid_y, end * half.z * rng.randf_range(0.3, 1.0))
		var dir := -Vector3(signf(side) * absf(side), 0.0, end * (1.0 - absf(side))).normalized()
		var s := clampf(damage * rng.randf_range(0.8, 1.6), 0.2, 1.0)
		_queue.append([self, p, dir, DENT_RADIUS * lerpf(0.6, 1.0, s), DENT_DEPTH * lerpf(0.25, 1.0, s)])


## The box's corners stand clear of the rounded bodywork: move the hit onto the body itself.
## The nearest vertex in the first cells out from the point that hold any (near enough: it
## only has to be on the body, under the hit).
func _nearest_vertex(p: Vector3) -> Vector3:
	var reach := CELL * 0.8
	while reach < 8.0:
		var best := INF
		var out := p
		for part in _parts:
			var o: Vector3 = part.mi.position
			var lp := p - o
			for sf in part.surfaces:
				var verts: PackedVector3Array = sf.arrays[Mesh.ARRAY_VERTEX]
				for i in _near(sf, lp, reach, 0.0):
					var d := verts[i].distance_squared_to(lp)
					if d < best:
						best = d
						out = verts[i] + o
		if best < INF:
			return out
		reach *= 2.0
	return p


## Indices of `sf`'s vertices that can be within `reach` of `lp` (car-part local), given
## they've moved up to `slack` from where they're filed.
static func _near(sf: Dictionary, lp: Vector3, reach: float, slack: float) -> PackedInt32Array:
	var grid := _grid(sf)
	var r := reach + slack
	var lo := Vector3i(floori((lp.x - r) / CELL), floori((lp.y - r) / CELL), floori((lp.z - r) / CELL))
	var hi := Vector3i(floori((lp.x + r) / CELL), floori((lp.y + r) / CELL), floori((lp.z + r) / CELL))
	var out := PackedInt32Array()
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var c: Variant = grid.get(Vector3i(x, y, z))
				if c != null:
					out.append_array(c)
	return out


## `sf`'s grid (see CELL), filed the first time a car of its model is hit.
static func _grid(sf: Dictionary) -> Dictionary:
	if not _grid_cache.has(sf.key):
		var rest: PackedVector3Array = sf.rest
		var grid := {}
		for i in rest.size():
			var v := rest[i]
			var c := Vector3i(floori(v.x / CELL), floori(v.y / CELL), floori(v.z / CELL))
			if not grid.has(c):
				grid[c] = PackedInt32Array()
			grid[c].append(i)
		_grid_cache[sf.key] = grid
	return _grid_cache[sf.key]


func _dent(p: Vector3, dir: Vector3, radius: float, depth: float) -> void:
	for part in _parts:
		var mi: MeshInstance3D = part.mi
		var lp := p - mi.position
		var mesh: ArrayMesh = part.mesh
		var changed := false
		for sf in part.surfaces:
			if sf.has("damaged"):
				changed = _bend_panels(sf, lp, radius, depth) or changed
				continue
			var arrays: Array = sf.arrays
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedVector3Array = sf.rest
			# The first vertex of each triangle that moved, for the creases.
			var moved := {}
			var slack: float = sf.get("slack", 0.0)
			for i in _near(sf, lp, radius, slack):
				var d := verts[i].distance_to(lp)
				if d >= radius:
					continue
				var f := 1.0 - d / radius
				var r := rest[i]
				# Crumple rather than a smooth dimple: a fixed per-position jitter (the same for
				# every copy of a vertex, so the unindexed triangles stay joined).
				var jitter := 0.6 + 0.8 * absf(fmod(sin(r.dot(Vector3(12.99, 78.23, 37.72))) * 43758.55, 1.0))
				var off := verts[i] + dir * depth * f * f * (3.0 - 2.0 * f) * jitter - r
				off = off.limit_length(MAX_DENT)
				verts[i] = r + off
				slack = maxf(slack, off.length())
				moved[i - i % 3] = true
			# How far this car's dents have pushed anything: where the next one has to look.
			sf.slack = slack
			if not moved.is_empty():
				arrays[Mesh.ARRAY_VERTEX] = verts
				_crease_normals(arrays, sf, PackedInt32Array(moved.keys()))
				changed = true
		if changed:
			mesh.clear_surfaces()
			for sf in part.surfaces:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sf.arrays)
				mesh.surface_set_material(mesh.get_surface_count() - 1, sf.material)
			mi.mesh = mesh


## High Stakes: the panels within `radius` of `lp` (part-local) bend toward the damaged
## model, a full hit on one all the way. A vertex goes as far as the most bent panel it's
## on, its normal with it. True if anything moved.
static func _bend_panels(sf: Dictionary, lp: Vector3, radius: float, depth: float) -> bool:
	var boxes: Dictionary = sf.panel_boxes
	var bent: Dictionary = sf.panel_bent
	var any := false
	for b: int in boxes:
		var box: AABB = boxes[b]
		var d := (lp.clamp(box.position, box.end) - lp).length()
		if d >= radius:
			continue
		var f := 1.0 - d / radius
		bent[b] = minf(float(bent.get(b, 0.0)) + f * f * (3.0 - 2.0 * f) * depth / DENT_DEPTH * 1.2, 1.0)
		any = true
	if not any:
		return false
	var dmg: Dictionary = sf.damaged
	var dpos: PackedVector3Array = dmg.pos
	var dnorm: PackedVector3Array = dmg.normal
	var panels: PackedInt32Array = dmg.panels
	var rest: PackedVector3Array = sf.rest
	var orig: PackedVector3Array = sf.normals
	var arrays: Array = sf.arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# How bent each vertex's panel is, for the crumpled paint (car.gdshader: 1 - COLOR.a).
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	if colours.size() != rest.size():
		colours.resize(rest.size())
		colours.fill(Color.WHITE)
	for i in rest.size():
		var m := panels[i]
		var w := 0.0
		var b := 0
		while m != 0:
			if m & 1:
				w = maxf(w, float(bent.get(b, 0.0)))
			m >>= 1
			b += 1
		if w <= 0.0:
			continue
		verts[i] = rest[i].lerp(dpos[i], w)
		normals[i] = orig[i].lerp(dnorm[i], w).normalized()
		colours[i] = Color(1.0, 1.0, 1.0, 1.0 - w)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	return true


## Bent panels catch the light as flat facets: turn the normals of moved triangles toward
## their face normal, the further the more they were pushed in. Only the `triangles` (first
## vertex of each) a dent just moved change; the rest keep what earlier dents gave them.
static func _crease_normals(arrays: Array, sf: Dictionary, triangles: PackedInt32Array) -> void:
	var orig = sf.normals
	if orig == null or arrays[Mesh.ARRAY_INDEX] != null:
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rest: PackedVector3Array = sf.rest
	var normals: PackedVector3Array = sf.get("creased", (orig as PackedVector3Array).duplicate())
	for t in triangles:
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
	sf.creased = normals
	arrays[Mesh.ARRAY_NORMAL] = normals

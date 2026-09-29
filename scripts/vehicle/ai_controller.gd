class_name AIController
extends Node
## Drives the parent Car along the TrackPath.
##   RACER   - races at the car's limit, picks a racing lane, overtakes.
##   TRAFFIC - cruises in a lane (optionally in the opposite direction).
##   COP     - parks by the road (or patrols); chases a target once a pursuit starts,
##             ramming it or getting ahead to block, then drives back to its post.

enum Role { RACER, TRAFFIC, COP }

var role := Role.RACER
var path: TrackPath
var car: Car
var enabled := false
var skill := 1.0             # 0.8 .. 1.1, scales cornering speed
var lane := 0.0              # desired lateral offset (m, + right)
var reverse_dir := false     # traffic driving against the track direction
var cruise_speed := 20.0     # traffic/cop patrol speed
var target: Car = null       # COP: who to chase
var chasing := false
var chase_slot := 0          # COP: 0 rams / PITs from behind, 1 gets ahead and blocks
var home := -1               # COP: node it parks at; -1 patrols the track instead
var home_lane := 0.0         # COP: lateral offset of its parking spot
var gap := Vector3.INF       # COP: the way through a roadblock, while one is up
var node := -1
var stranded_t := 0.0        # time spent making no headway; the race respawns the car after a while

var _stuck_t := 0.0
var _reverse_t := 0.0
var _lane_change_t := 0.0
var _progress_node := -1
var _dodge := 0.0            # TRAFFIC: temporary sideways shift around a stopped car
var _dodge_t := 0.0
var others: Array = []       # cars to avoid (set by the race)

const GHOST_ENTER := 320.0   # m from the camera and every non-traffic car: far-off traffic glides
const GHOST_LEAVE := 300.0   # ...and drives again inside this
var _ghost := false
var _ghost_check := 0.0
var _ghost_f := 0.0          # m past `node` along the road
var _ghost_h := 0.0          # m the body rides over the road

const LIMIT_TICKS := 3       # physics ticks between refreshes of the speed limit
var _limit := 0.0
var _limit_ticks := 0
var _limit_dir := 0
var _limit_chase := false


func _ready() -> void:
	car = get_parent() as Car
	process_physics_priority = -10
	_limit_ticks = randi() % LIMIT_TICKS
	_ghost_check = randf() * 0.25
	if role == Role.TRAFFIC:
		car.set_meta("traffic", true)


func _physics_process(dt: float) -> void:
	car.hold = false
	if not enabled or path == null:
		stranded_t = 0.0
		car.throttle = 0.0
		car.hold = true
		car.steer = 0.0
		return
	if role == Role.TRAFFIC and _ghost_step(dt):
		return
	node = path.closest(car.global_position, node)
	var chase := role == Role.COP and chasing and is_instance_valid(target)
	var home_d := 0.0
	if chase:
		# Follow the road whichever way the target is going round it.
		var along := target.linear_velocity.dot(path.forward(node))
		if absf(along) > 3.0:
			reverse_dir = along < 0.0
	elif role == Role.COP:
		home_d = _head_home()
	var dir := -1 if reverse_dir else 1

	# --- where to aim (about a second ahead: further out, the line cuts across bends into the inside wall)
	var aim_node := _aim_node(node)
	if role == Role.TRAFFIC:
		_pull_around(dt)
	# The lane was picked where the road was wide; keep it inside the walls where it narrows.
	var lo := -maxf(path.left_width[aim_node] - 2.5, 0.0)
	var hi := maxf(path.right_width[aim_node] - 2.5, 0.0)
	var off := clampf(lane + _dodge, lo, hi)
	# Round anything standing on the road ahead (a pillar, a median): past the aim point, and
	# far enough to see the next one of a row coming before drifting back into its line.
	var scan_to := path.ahead(node, dir, maxf(40.0, car.speed * 2.0))
	if fposmod((path.cumulative[aim_node] - path.cumulative[scan_to]) * dir, path.length) < path.length * 0.5:
		scan_to = path.idx(aim_node + 2 * dir)
	var clear := path.free_offset(path.idx(node + dir), scan_to, dir, off, path.lateral(car.global_position, node), lo, hi)
	if clear != off and role == Role.RACER:
		# Keep to the clear line rather than being pulled back into the obstacles after each one.
		lane = clear
	off = clear
	# Aiming a second ahead cuts across the inside of a bend: where pillars stand along it,
	# aim nearer until the straight way there misses them.
	while aim_node != path.idx(node + 2 * dir) and not path.chord_clear(car.global_position, node, aim_node, off, dir):
		aim_node = path.idx(aim_node - dir)
	var aim: Vector3 = path.points[aim_node] + path.rights[aim_node] * off
	# The look-ahead over the next 300 m is the AI's biggest cost: refreshed every few ticks
	# (staggered between the cars), which moves the braking point by well under a metre.
	_limit_ticks -= 1
	if _limit_ticks <= 0 or dir != _limit_dir or chase != _limit_chase:
		_limit = _speed_limit(dir)
		_limit_ticks = LIMIT_TICKS
		_limit_dir = dir
		_limit_chase = chase
	var desired := _limit
	car.power_scale = 1.0
	if chase:
		var plan := _chase(aim, desired)
		aim = plan[0]
		desired = plan[1]
	elif role == Role.TRAFFIC:
		desired = minf(desired, cruise_speed if _dodge == 0.0 else 10.0)
	elif role == Role.COP:
		# Back to its post (slowing onto the spot), or on patrol.
		desired = minf(desired, cruise_speed)
		if home >= 0:
			desired = minf(desired, sqrt(3.0 * maxf(absf(home_d) - 5.0, 0.0)) + 3.0)
			# Near enough: turning back to stop on the exact spot just circles round it.
			if absf(home_d) < 8.0:
				desired = 0.0

	if role == Role.RACER:
		_avoid(dt)
	elif role == Role.COP and desired > 0.0:
		# Cops cut through traffic rather than following a lane, so dodge whatever's in the way.
		aim += car.global_basis.x * _swerve()

	# --- steer toward aim (car's local +X is left)
	var local := car.global_transform.affine_inverse() * aim
	var angle := atan2(-local.x, maxf(local.z, 0.1))
	car.steer = clampf(angle * 2.2, -1.0, 1.0)
	var fwd_speed := car.speed
	if role == Role.COP and local.z < 0.0 and desired > 0.0:
		# Aim behind (turning back for its post, or after a target that doubled back): a
		# three-point turn - slow, full lock, and backing up with the wheels the other way.
		desired = minf(desired, 6.0)
		if absf(fwd_speed) < 2.5 and _reverse_t <= 0.0:
			_reverse_t = 1.1

	# --- throttle / brake
	if desired <= 0.0:
		# Parked (a cop waiting by the road): brakes on, no creeping forward.
		car.throttle = 0.0
		car.brake = 0.0
		car.hold = true
	elif fwd_speed < desired - 1.0:
		car.throttle = clampf((desired - fwd_speed) / 6.0, 0.25, 1.0)
		car.brake = 0.0
	elif fwd_speed > desired + 1.0 and role != Role.RACER and fwd_speed < desired + 3.0:
		# Cruising a little over: lift and let engine braking settle it. Braking here
		# drops it under, the hold throttle carries it back over, and the brake lights flicker.
		car.throttle = 0.0
		car.brake = 0.0
	elif fwd_speed > desired + 1.0:
		# Brake firmly: the limit already allows for the braking distance, so a gentle
		# proportional brake arrives at the bend too fast.
		car.throttle = 0.0
		car.brake = clampf((fwd_speed - desired) / 3.0, 0.35, 1.0)
	else:
		car.throttle = 0.35
		car.brake = 0.0
	car.handbrake = false

	# --- getting unstuck: back up for a moment, then carry on
	_update_stranded(dt, desired, dir)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		car.throttle = 0.0
		car.brake = 1.0
		car.steer = -car.steer
		return
	# Crawling well below the target speed (e.g. scraping along a wall) counts as stuck too.
	if desired > 5.0 and absf(fwd_speed) < 3.0:
		_stuck_t += dt
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			_reverse_t = 1.2
	else:
		_stuck_t = 0.0


## TRAFFIC far from the camera and from every car that isn't traffic: nobody sees it or meets
## it, so rather than drive it (suspension, tyres and all) it glides along its lane at its
## cruising speed as a kinematic body, and drives again before anyone comes near. Returns
## whether it's gliding this tick.
func _ghost_step(dt: float) -> bool:
	_ghost_check -= dt
	if _ghost_check <= 0.0:
		_ghost_check = 0.25
		var near := _nearest_watcher()
		if not _ghost and near > GHOST_ENTER and _dodge == 0.0 and absf(car.speed) > cruise_speed * 0.8 \
				and car.grounded_wheels == 4 and absf(path.lateral(car.global_position, node) - lane) < 1.0:
			_ghost_enter()
		elif _ghost and near < GHOST_LEAVE:
			_ghost_leave()
	if not _ghost:
		return false
	# Along the road from node to node, `_ghost_f` metres past the current one.
	var dir := -1 if reverse_dir else 1
	_ghost_f += cruise_speed * dt
	var nxt := path.idx(node + dir)
	var seg := path.points[node].distance_to(path.points[nxt])
	while _ghost_f > seg:
		_ghost_f -= seg
		node = nxt
		nxt = path.idx(node + dir)
		seg = path.points[node].distance_to(path.points[nxt])
	var t := _ghost_f / maxf(seg, 0.01)
	var right := path.rights[node].lerp(path.rights[nxt], t)
	var up := path.ups[node].lerp(path.ups[nxt], t) if path.ups.size() > nxt else Vector3.UP
	var fwd := (path.points[nxt] - path.points[node]).normalized()
	var pos := path.points[node].lerp(path.points[nxt], t) + right * lane + up * _ghost_h
	car.global_transform = Transform3D(Basis.looking_at(-fwd, up), pos)
	stranded_t = 0.0
	_progress_node = node
	return true


## Metres to the camera or the nearest car that isn't traffic, whichever is closer.
func _nearest_watcher() -> float:
	var p := car.global_position
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(p) if cam else INF
	for o in others:
		if is_instance_valid(o) and not o.has_meta("traffic"):
			d = minf(d, (o as Node3D).global_position.distance_to(p))
	return d


func _ghost_enter() -> void:
	_ghost = true
	node = path.closest(car.global_position, node)
	var dir := -1 if reverse_dir else 1
	var nxt := path.idx(node + dir)
	# Carry on from where it is: how far past the node, and how high its body rides over the road.
	var along := (path.points[nxt] - path.points[node]).normalized()
	_ghost_f = clampf((car.global_position - path.points[node]).dot(along), 0.0, path.points[node].distance_to(path.points[nxt]))
	var up := path.ups[node] if path.ups.size() > node else Vector3.UP
	_ghost_h = (car.global_position - path.points[node] - path.rights[node] * lane).dot(up)
	car.suspend()


func _ghost_leave() -> void:
	_ghost = false
	car.resume(car.global_basis.z * cruise_speed)


## Time spent making no headway. Measured as progress along the road, so a car that keeps
## backing off a wall and driving into it again still counts as stranded. A chasing cop
## goes wherever its target goes, so it only counts time spent (nearly) stationary.
func _update_stranded(dt: float, desired: float, dir: int) -> void:
	if desired <= 5.0:
		stranded_t = 0.0
		_progress_node = node
		return
	if role == Role.COP and chasing:
		stranded_t = stranded_t + dt if absf(car.speed) < 5.0 else 0.0
		# Measure road progress afresh once it's off the chase (and maybe heading the other way).
		_progress_node = -1
		return
	var gained := wrapi((node - _progress_node) * dir, -path.size() / 2, path.size() / 2)
	if _progress_node < 0 or gained >= 3:
		_progress_node = node
		stranded_t = 0.0
	else:
		stranded_t += dt


## Max speed now: every bend in the next few hundred metres must still be reachable at
## its cornering speed (v = sqrt(a_lat * r)) after braking over the distance to it.
## Measuring each bend where it is (not by the heading change from here) keeps the limit
## right once the car is already in a long bend such as a hairpin.
func _speed_limit(dir: int) -> float:
	var worst := car.top_speed
	var ground := _ground_grip()
	var a2 := 2.0 * car.brake_decel * 0.6 * ground
	# _corner_speed's per-car factors, hoisted out of the loop: it runs over 32 nodes.
	var k0 := 1.25 * 9.81 * 0.95 * skill * car.corner_grip() * ground
	var c := car.downforce_k * 0.5
	var pts := path.points
	var radii := path.radius
	var n := pts.size()
	var dist := 0.0
	var prev := node
	for k in range(0, 64, 2):
		var i := node + k * dir
		i = ((i % n) + n) % n
		dist += pts[prev].distance_to(pts[i])
		prev = i
		var r: float = radii[i]
		var kr := k0 * r
		var v2 := kr * 1.45
		if kr * c < 1.0:
			v2 = minf(kr / (1.0 - kr * c), v2)
		var v := (sqrt(v2) + 1.5) * car.bend_speed_factor(r)
		v = sqrt(v * v + a2 * maxf(dist - 6.0, 0.0))
		worst = minf(worst, v)
		if dist > 320.0:
			break
	return worst * (0.97 if role == Role.RACER or (role == Role.COP and chasing) else 0.8)


## Cornering speed for a bend of radius r: 95% of what the tyres hold (mu = 1.25 * grip *
## surface_grip on the weaker axle, see Car), with the extra grip that downforce gives at speed, plus a little for the line
## cutting across the inside of the bend. (_speed_limit inlines this.)
func _corner_speed(r: float) -> float:
	var k := 1.25 * 9.81 * 0.95 * skill * car.corner_grip() * _ground_grip() * r
	# Car's downforce adds 0.5 * min(downforce_k v^2, 0.9) g-units of load: v^2 = k (1 + c v^2).
	var c := car.downforce_k * 0.5
	var v2 := k * 1.45
	if k * c < 1.0:
		v2 = minf(k / (1.0 - k * c), v2)
	# The car's own caution in bends of each sharpness, from the original AI's tables.
	return (sqrt(v2) + 1.5) * car.bend_speed_factor(r)


## COP off the chase: picks the way back to its post (the short way round, in the lane on
## its side of the road) and returns the signed distance to it along the track.
func _head_home() -> float:
	if home < 0:
		reverse_dir = false
		return 0.0
	var L := path.length
	var d := fposmod(path.cumulative[home] - path.cumulative[node] + L * 0.5, L) - L * 0.5
	if absf(d) < 40.0:
		lane = home_lane
	else:
		if reverse_dir != (d < 0.0):
			_progress_node = -1
		reverse_dir = d < 0.0
		lane = -3.0 if reverse_dir else 3.0
	return d


## COP chasing: [aim point, desired speed]. Far off it closes in along the road; near, the
## rammer (slot 0) hits the target from behind or turns its rear out (a PIT) when alongside,
## and the blocker (slot 1) overtakes and sits on the target's line, braking.
func _chase(aim: Vector3, limit: float) -> Array:
	var to_t := target.global_position - car.global_position
	var dist := to_t.length()
	var tv := target.linear_velocity
	var t_speed := tv.length()
	var t_fwd := target.forward_dir()
	var t_left := target.global_basis.x
	# Catch-up: a cruiser that's fallen behind gets a boost, as in the original.
	car.power_scale = 1.35 if dist > 80.0 else 1.12
	if dist >= 70.0:
		return [aim, minf(limit, t_speed + 15.0)]
	var cap := maxf(limit * 1.1, 12.0)
	if gap != Vector3.INF:
		# Through the roadblock's gap rather than into the parked cruisers.
		var to_gap := gap - car.global_position
		if to_gap.dot(car.forward_dir()) > 2.0 and to_gap.length() < 90.0 and to_gap.length() < dist + 10.0:
			return [gap, minf(cap, 25.0)]
	var ahead := -to_t.dot(t_fwd)   # how far the cop is in front of its target
	var beside := -to_t.dot(t_left)  # + on the target's left
	if chase_slot == 1:
		if ahead > 8.0:
			# In front: sit on the target's line and brake-check it.
			var tn := path.closest(target.global_position, node)
			var t_lat := path.lateral(target.global_position, tn)
			var an := _aim_node(node)
			var line: Vector3 = path.points[an] + path.rights[an] * t_lat
			return [line, minf(cap, maxf(t_speed - 4.0, 6.0))]
		# Pass it, aiming well up the road from it.
		return [target.global_position + t_fwd * 25.0 + tv * 0.3, minf(cap, t_speed + 14.0)]
	if dist < 14.0 and ahead > -7.0 and ahead < 1.0 and absf(beside) > 1.2:
		# Alongside: steer into its rear quarter to spin it round.
		var pit := target.global_position - t_fwd * 1.6 + t_left * signf(beside) * 0.4
		return [pit, minf(cap, t_speed + 6.0)]
	var lead := tv * clampf(dist / 40.0, 0.0, 1.2)
	return [target.global_position + lead, minf(cap, t_speed + (12.0 if dist > 15.0 else 6.0))]


## A node a second or so up the road from `n`, like the normal aim point.
func _aim_node(n: int) -> int:
	var look := int(clampf(2.0 + car.linear_velocity.length() * 0.16, 3.0, 12.0))
	return path.idx(n + look * (-1 if reverse_dir else 1))


## Sideways shift (m, + to the car's left) of the aim point around the nearest car in the way.
## The chase target is never in the way: hitting it is the point.
func _swerve() -> float:
	var fwd := car.forward_dir()
	var left := car.global_basis.x
	var reach := clampf(absf(car.speed) * 1.2, 10.0, 35.0)
	var nearest := reach
	var shift := 0.0
	for o in others:
		if o == car or not is_instance_valid(o) or (chasing and o == target):
			continue
		var rel: Vector3 = o.global_position - car.global_position
		var ahead := rel.dot(fwd)
		var side := rel.dot(left)
		if ahead > 1.5 and ahead < nearest and absf(side) < 2.6:
			nearest = ahead
			# To whichever side it leaves more of the car's path clear.
			shift = -3.4 if side >= 0.0 else 3.4
	return shift


## Traffic: pull out around a car stopped in its lane (a parked cruiser, a wreck), then
## drop back into the lane.
func _pull_around(dt: float) -> void:
	_dodge_t -= dt
	if _dodge_t <= 0.0:
		_dodge = 0.0
	var fwd := car.forward_dir()
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - car.global_position
		var ahead := rel.dot(fwd)
		if ahead > 3.0 and ahead < 22.0 and absf(rel.dot(car.global_basis.x)) < 2.4 and absf(o.speed) < 1.5:
			# Towards the middle of the road (traffic lanes sit either side of it).
			_dodge = -3.2 if lane > 0.0 else 3.2
			_dodge_t = 2.5
			return


func _avoid(dt: float) -> void:
	_lane_change_t -= dt
	if _lane_change_t > 0.0:
		return
	var fwd := car.forward_dir()
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - car.global_position
		var ahead := rel.dot(fwd)
		# Pull out past slower cars, and try another line when stuck behind anything.
		if ahead > 2.0 and ahead < 25.0 and absf(rel.dot(car.global_basis.x)) < 2.5 and (o.speed < car.speed or stranded_t > 2.0):
			# The virtual road's walls can be far out past the tarmac, so keep to a few metres either side.
			var w: float = minf(minf(path.left_width[node], path.right_width[node]) * 0.6, 5.5)
			lane = clampf(lane + (4.0 if randf() < 0.5 else -4.0), -w, w)
			_lane_change_t = 2.0
			return


## The grip under the car: the weather's, less on loose ground (see TrackSurface.FEEL) when
## it has run wide off the road.
func _ground_grip() -> float:
	return car.surface_grip * lerpf(1.0, 0.68, car.off_road)

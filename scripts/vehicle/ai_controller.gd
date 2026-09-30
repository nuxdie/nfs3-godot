class_name AIController
extends Node
## Drives the parent Car along the TrackPath.
##   RACER   - races at the car's limit, picks a racing lane, overtakes.
##   TRAFFIC - cruises in a lane (optionally in the opposite direction), keeping its
##             distance, and gives way to cruisers with their sirens on (TrafficRules).
##   COP     - parks by the road (or patrols); chases a target once a pursuit starts,
##             ramming it or getting ahead to block, then drives back to its post.

enum Role { RACER, TRAFFIC, COP }

var role := Role.RACER
var path: TrackPath
var car: Car
var enabled := false
var skill := 1.0             # 0.8 .. 1.1, scales cornering speed
## Desired lateral offset (m, + right). A RACER on a track with High Stakes' racing line
## drives the line instead a few seconds after its lane was last set (the grid, a
## roadblock's gap, pulling out to pass, round an obstacle).
var lane := 0.0:
	set(v):
		lane = v
		_lane_hold = LANE_HOLD
var reverse_dir := false     # traffic driving against the track direction
var cruise_speed := 20.0     # traffic/cop patrol speed (traffic with a traffic_lane: at most)
## TRAFFIC in the race's traffic: its lane, 1 the nearest the centre line (0: keeps to `lane`
## instead, as a finished racer does), the side of the road it keeps to (+1 right, -1 left),
## its share of the cruising speed (TrafficRules.SPEED_FACTORS) and the racer it's in play
## for, whose speed sets how fast it may come the other way.
var traffic_lane := 0
var drive_side := 1
var speed_factor := 1.0
var basis: Car = null
var target: Car = null       # COP: who to chase
var chasing := false
var chase_slot := 0          # COP: its place round the target (CHASE_SPOTS), set by the race
var aggression := 0          # COP: 0..2, how close it sits and how long it rams (the race's heat)
var home := -1               # COP: node it parks at; -1 patrols the track instead
var home_lane := 0.0         # COP: lateral offset of its parking spot
var gap := Vector3.INF       # COP: the way through a roadblock, while one is up
var node := -1
var stranded_t := 0.0        # time spent making no headway; the race respawns the car after a while

var _stuck_t := 0.0
var _reverse_t := 0.0
var _pass_off := NAN         # RACER: the line it picked round the cars ahead (NAN: its own)
var _plan_ticks := 0
var _pass_urgent := false    # RACER: the line round a car ahead is well off where it's going
var _traffic_cap := INF      # RACER: the speed that keeps it off the car it can't get round
var _node_of := {}           # RACER: Car -> its node last time (a hint for TrackPath.closest)
var _lane_hold := 0.0        # s the set lane still overrides the racing line
const LANE_HOLD := 5.0
const TABLE_SHARE := 0.8    # of the original AI's target speeds that traffic and patrols keep to
var _progress_node := -1
var _dodge := 0.0            # TRAFFIC: temporary sideways shift around a stopped car
var _dodge_t := 0.0
enum Yield { NONE, IGNORE, STOP, PULL_OVER }
var _yield := Yield.NONE     # TRAFFIC: what it's doing about a cruiser with its siren on
var _yield_v := 0.0          # speed it's slowing through while giving way
var _cop_check := 0.0
# COP chasing (AIState_Chase): how it goes about it this tick, where the target is on the road,
# how long it has held its place, and the ram ("murder mode") it's on and its cool-down.
enum Chase { CLOSE, FAR, APPROACH, WAIT }
var _mode := Chase.CLOSE
var _t_node := -1
var _t_ahead := 0.0          # m further round the lap the target is than the cop
var _t_dir := 1              # which way round the lap the target is going
var _in_slot_t := 0.0
var _ram_t := 0.0
var _ram_cool := 0.0
var _passing := false        # getting round the target to a place in front

## COP: each chaser's place round its target (m to its right, m ahead of it), by aggression
## (AIH_Cop_chasePositions): the first dead ahead to block, one ahead on the left, one
## alongside on the right, the rest behind (the original stacks those three on one spot;
## here they're staggered).
const CHASE_SPOTS := [
	[Vector2(0, 8), Vector2(-6, 8), Vector2(6, 0), Vector2(0, -10), Vector2(-3, -16), Vector2(3, -16)],
	[Vector2(0, 5), Vector2(-4, 5), Vector2(4, 5), Vector2(0, -5), Vector2(-3, -11), Vector2(3, -11)],
]
## By aggression (AIHigh_Cop_AggressionData): s in its place before it rams, how near
## (m across, m along) it must be, how long the ram lasts, and the brake check in front.
const RAM_HOLD := [0.6, 0.45, 0.25]
const RAM_LAT := [10.0, 14.0, 18.0]
const RAM_LONG := [13.0, 15.0, 18.0]
const RAM_TIME := [5.0, 7.5, 11.0]
const RAM_COOL := 2.0         # s back in its place before the next ram
const BRAKE_CHECK := [0.79, 0.73, 0.65]
const CUT_OFF_RATE := 0.25    # chance a second of swerving across the nose of a car just behind
const TARGET_SLOW := 6.7      # m/s: a target slower than this is stopped for, not chased
var _honk_t := 0.0           # s the horn has left to sound
var _lane_change_cool := 0.0
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
	car.collision_mask |= Nfs3TrackBuilder.AI_WALL_LAYER
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
		_chase_mode()
	elif role == Role.COP:
		home_d = _head_home()
	var dir := -1 if reverse_dir else 1

	# --- where to aim (about a second ahead: further out, the line cuts across bends into the inside wall)
	var aim_node := _aim_node(node)
	if role == Role.TRAFFIC:
		if traffic_lane > 0:
			_check_cops(dt)
			_keep_lane(aim_node, dir, dt)
		if _yield != Yield.STOP and _yield != Yield.PULL_OVER:
			_pull_around(dt)
	# The lane was picked where the road was wide; keep it inside the walls where it narrows.
	var lo := -maxf(path.left_width[aim_node] - 2.5, 0.0)
	var hi := maxf(path.right_width[aim_node] - 2.5, 0.0)
	_lane_hold -= dt
	var off := clampf(_lane_at(aim_node, dir) + _dodge, lo, hi)
	if role == Role.RACER:
		off = _plan_pass(off, lo, hi, dir)
		if _pass_urgent:
			# Getting round a car: aim nearer, where the straight line there doesn't cut
			# the inside of a bend by the metre or two that would take it into the car.
			var look := int(clampf(1.0 + car.linear_velocity.length() * 0.1, 3.0, 8.0))
			aim_node = path.idx(node + look * dir)
	# Round anything standing on the road ahead (a pillar, a median): past the aim point, and
	# far enough to see the next one of a row coming before drifting back into its line.
	var scan_to := path.ahead(node, dir, maxf(40.0, car.speed * 2.0))
	if fposmod((path.cumulative[aim_node] - path.cumulative[scan_to]) * dir, path.length) < path.length * 0.5:
		scan_to = path.idx(aim_node + 2 * dir)
	var clear := path.free_offset(path.idx(node + dir), scan_to, dir, off, path.lateral(car.global_position, node), lo, hi)
	if clear != off and role == Role.RACER and is_nan(_pass_off):
		# Keep to the clear line rather than being pulled back into the obstacles after each one
		# (not a line round a car, which it leaves once past).
		lane = clear
	off = clear
	# Aiming a second ahead cuts across the inside of a bend: where pillars stand along it,
	# aim nearer until the straight way there misses them.
	while aim_node != path.idx(node + 2 * dir) and not path.chord_clear(car.global_position, node, aim_node, off, dir):
		aim_node = path.idx(aim_node - dir)
	if role == Role.RACER and _pass_urgent:
		# Getting out of a car's way: aim past the line picked so the car gets across to it
		# in time, rather than easing over a second's drive up the road.
		var lat_now := path.lateral(car.global_position, node)
		off = clampf(off + (off - lat_now) * 0.4, minf(lo, off), maxf(hi, off))
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
		var plan := _chase(aim, desired, dt)
		aim = plan[0]
		desired = plan[1]
	elif role == Role.TRAFFIC:
		desired = minf(desired, traffic_speed(node, dir) if _dodge == 0.0 else 10.0)
		desired = minf(desired, _follow(dt))
		if _yield == Yield.STOP or _yield == Yield.PULL_OVER:
			# Brake steadily to a stop, pulled over to the kerb unless stopping where it is.
			_yield_v = maxf(_yield_v - 4.5 * dt, 0.0)
			desired = minf(desired, _yield_v if _yield_v > 0.5 else 0.0)
		_honk(dt, dir)
	elif role == Role.COP:
		# Back to its post (slowing onto the spot), or on patrol.
		desired = minf(desired, cruise_speed)
		if home >= 0:
			desired = minf(desired, sqrt(3.0 * maxf(absf(home_d) - 5.0, 0.0)) + 3.0)
			# Near enough: turning back to stop on the exact spot just circles round it.
			if absf(home_d) < 8.0:
				desired = 0.0

	if role == Role.RACER:
		desired = minf(desired, minf(_traffic_cap, _wall_cap()))
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
		# Well astern: near enough stop, so it backs up, rather than lap a wide circle round.
		desired = minf(desired, 6.0 if -local.z < absf(local.x) else 2.0)
		# Full lock the way round that's nearer; dead astern, the angle to it reads as none.
		car.steer = -signf(local.x) if absf(local.x) > 0.5 else (signf(car.steer) if car.steer != 0.0 else 1.0)
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
	# Crawling well below the target speed (e.g. scraping along a wall) counts as stuck too;
	# not for traffic, whose buses and lorries take longer than that to pull away.
	if desired > 5.0 and absf(fwd_speed) < (0.8 if role == Role.TRAFFIC else 3.0):
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
		if not _ghost and near > GHOST_ENTER and _dodge == 0.0 and path.idx(node + (-1 if reverse_dir else 1)) != node \
				and absf(car.speed) > traffic_speed(node, -1 if reverse_dir else 1) * 0.8 \
				and car.grounded_wheels == 4 and absf(path.lateral(car.global_position, node) - lane) < 1.0:
			_ghost_enter()
		elif _ghost and near < GHOST_LEAVE:
			_ghost_leave()
	if not _ghost:
		return false
	# Along the road from node to node, `_ghost_f` metres past the current one.
	var dir := -1 if reverse_dir else 1
	_ghost_f += traffic_speed(node, dir) * dt
	if traffic_lane > 0:
		lane = move_toward(lane, path.lane_offset(node, drive_side * dir, traffic_lane), 1.2 * dt)
	var nxt := path.idx(node + dir)
	var seg := path.points[node].distance_to(path.points[nxt])
	while _ghost_f > seg:
		if nxt == node:
			# The end of a point-to-point road (TrackPath.idx clamps there): no further to
			# glide, so it drives again and the race deals with it like any other car.
			_ghost_leave()
			return false
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
	car.resume(car.global_basis.z * traffic_speed(node, -1 if reverse_dir else 1))


## TRAFFIC: puts the car down at `xf` on node `n`, moving at `v`, as if it had driven there
## (the race bringing it back into play).
func put_down(xf: Transform3D, n: int, v: float) -> void:
	if _ghost:
		_ghost = false
		car.resume(Vector3.ZERO)
	car.reset_to(xf)
	car.linear_velocity = car.global_basis.z * v
	car.speed = v
	node = n
	_progress_node = -1
	stranded_t = 0.0
	_stuck_t = 0.0
	_reverse_t = 0.0
	_dodge = 0.0
	_yield = Yield.NONE
	_honk_t = 0.0
	car.horn = false


## TRAFFIC: its cruising speed at node `n` heading `dir`: a share of the speed limit there
## (TrafficRules), slower coming the other way to a fast racer; `cruise_speed` for traffic
## that isn't the race's (a finished racer).
func traffic_speed(n: int, dir: int) -> float:
	if traffic_lane <= 0:
		return cruise_speed
	var legal: float = path.legal_speed[n] if path.legal_speed.size() == path.size() else TrafficRules.DEFAULT_LEGAL
	var against := NAN
	if is_instance_valid(basis):
		var along := basis.linear_velocity.dot(path.forward(n)) * dir
		if along < -1.0:
			against = along
	return minf(cruise_speed, TrafficRules.cruise(legal, speed_factor, against))


## TRAFFIC: steers for its lane (or the kerb, pulling over), easing across when the lanes
## change under it rather than jumping.
func _keep_lane(aim_node: int, dir: int, dt: float) -> void:
	var side := drive_side * dir
	var want := path.lane_offset(aim_node, side, traffic_lane)
	if _yield == Yield.PULL_OVER:
		want = path.lane_offset(aim_node, side, 99) + side * 1.8
	lane = move_toward(lane, want, (2.5 if _yield == Yield.PULL_OVER else 1.2) * dt)
	# Signalling while it eases across or pulls over (the path's right is its own going `dir`).
	var across := (want - lane) * dir
	car.indicate = 0 if absf(across) < 0.4 else 1 if across > 0.0 else -1


## TRAFFIC: gives way to the nearest cruiser with its siren on (AIHigh_Traffic::CopCheck):
## pulls over and waits for one stopped up ahead; for one on the move, pulls over,
## stops where it is or carries on, and drives on once none is near.
func _check_cops(dt: float) -> void:
	_cop_check -= dt
	if _cop_check > 0.0:
		return
	_cop_check = 0.25
	var cop: Car = null
	var best := TrafficRules.COP_REACT
	var fwd := car.forward_dir()
	for o in others:
		if not is_instance_valid(o) or not o.is_cop or not o.siren_on():
			continue
		var rel: Vector3 = o.global_position - car.global_position
		# One standing still only matters up ahead (a roadblock already passed doesn't).
		if absf(o.speed) < TrafficRules.COP_STOPPED and rel.dot(fwd) < -5.0:
			continue
		if absf(rel.y) < 8.0 and rel.length() < best:
			best = rel.length()
			cop = o
	if cop == null:
		_yield = Yield.NONE
		return
	if _yield == Yield.NONE:
		_yield_v = absf(car.speed)
		if absf(cop.speed) < TrafficRules.COP_STOPPED:
			_yield = Yield.PULL_OVER
		else:
			var r := randi() % 10
			_yield = Yield.STOP if r == 0 else (Yield.PULL_OVER if r < 8 else Yield.IGNORE)
	elif _yield == Yield.IGNORE and absf(cop.speed) < TrafficRules.COP_STOPPED:
		# A roadblock ahead is another matter.
		_yield_v = absf(car.speed)
		_yield = Yield.PULL_OVER


## TRAFFIC: the speed that keeps a safe gap to the car in front in its lane: about a
## second and a half plus a car length, closing up when that car is slower. Something
## coming the other way in its lane gets a slowdown, the horn, and room at the kerb.
func _follow(dt: float) -> float:
	var fwd := car.forward_dir()
	var left := car.global_basis.x
	var v := absf(car.speed)
	var cap := INF
	var look := 12.0 + v * 3.0
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - car.global_position
		var ahead := rel.dot(fwd)
		if ahead < 2.0 or ahead > look or absf(rel.dot(left)) > 2.3 or absf(rel.y) > 4.0:
			continue
		var ov: float = (o as Car).linear_velocity.dot(fwd)
		if ov < -3.0:
			# Head-on: brake, sound the horn and edge over to the kerb.
			if traffic_lane > 0 and ahead < 70.0:
				cap = minf(cap, 6.0)
				_honk_t = maxf(_honk_t, 0.6)
				if _dodge == 0.0:
					_dodge = drive_side * (-1 if reverse_dir else 1) * 1.6
					_dodge_t = 1.5
			continue
		if _dodge != 0.0 and absf(ov) < 1.5:
			continue   # pulling out round it
		var gap := ahead - 6.0 - maxf(ov, 0.0) * 1.5
		cap = minf(cap, maxf(ov, 0.0) + maxf(gap, 0.0) * 0.6)
	# Held up behind something that won't move: another lane on its side, if there is one.
	_lane_change_cool -= dt
	if traffic_lane > 0 and cap < v * 0.5 and _lane_change_cool <= 0.0:
		_lane_change_cool = 3.0
		var side := drive_side * (-1 if reverse_dir else 1)
		var lanes := path.lane_count(node, side)
		if lanes > 1:
			var k := traffic_lane + 1 if traffic_lane < lanes else traffic_lane - 1
			# A look in the mirror first: nothing alongside or coming up in that lane.
			if _lane_clear(path.lane_offset(node, side, k), side):
				traffic_lane = k
	return cap


## TRAFFIC: whether the lane at `off` (m right of the centre line) is clear to pull into:
## nothing beside it there, nor catching up from behind.
func _lane_clear(off: float, side: int) -> bool:
	var fwd := car.forward_dir()
	var dir := -1 if reverse_dir else 1
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var oc := o as Car
		var rel: Vector3 = oc.global_position - car.global_position
		var ahead := rel.dot(fwd)
		if ahead < -60.0 or ahead > 25.0 or absf(rel.y) > 4.0:
			continue
		if absf(path.lateral(oc.global_position, node) - off) > 2.6:
			continue
		var closing := oc.linear_velocity.dot(fwd) - absf(car.speed)
		if ahead > -10.0 or closing * 2.5 > -ahead:
			return false
	return true


## TRAFFIC: sounds the horn: coming the other way to a racer that can see it, now and then
## (AI_HandleTrafficHonking), and at whatever it met head-on (_follow).
func _honk(dt: float, dir: int) -> void:
	if traffic_lane <= 0:
		return
	if _honk_t <= 0.0 and is_instance_valid(basis) and absf(car.speed) > 1.0 \
			and basis.linear_velocity.dot(path.forward(node)) * dir < -1.0 \
			and basis.global_position.distance_to(car.global_position) < 170.0 \
			and randf() < TrafficRules.HONK_RATE * dt:
		_honk_t = randf_range(0.25, 0.7)
	_honk_t -= dt
	car.horn = _honk_t > 0.0


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


## The lateral offset to drive at node `n`: the set lane, or a RACER's racing line.
func _lane_at(n: int, dir: int) -> float:
	var line: PackedFloat32Array = path.racing_line[0 if dir > 0 else 1]
	if role != Role.RACER or _lane_hold > 0.0 or line.size() != path.size():
		return lane
	return line[n]


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
	# The original AI's own target speeds, where the track has them: traffic and cops on
	# patrol keep to a share of them (they know about crests, jumps and blind bends).
	# Racers don't: this AI corners harder than the original's, and held to its speeds it
	# lost a quarter of its pace.
	var table: PackedFloat32Array = path.ai_speeds[0 if dir > 0 else 1]
	var has_table := table.size() == pts.size() and (role == Role.TRAFFIC or role == Role.COP and not chasing)
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
		if has_table and table[i] > 5.0:
			v = minf(v, table[i] * TABLE_SHARE)
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


## COP chasing: how to go about it (AIState_Chase::Execute), and which way round the road
## that takes it. A target that has (nearly) stopped, or is coming head-on, is met and
## stopped for (APPROACH); one well ahead going away is run down along the road (FAR);
## a cop well up the road going the same way lets it come to it (WAIT); near and going the
## same way, it takes its place round the target (CLOSE).
func _chase_mode() -> void:
	_t_node = path.closest(target.global_position, _t_node if _t_node >= 0 else node)
	if path.points[_t_node].distance_squared_to(target.global_position) > 30.0 * 30.0:
		# A new target, or put back somewhere else: the local search only finds the road near the hint.
		_t_node = path.closest(target.global_position)
	var L := path.length
	# m further round the lap the target is than the cop.
	var ahead := fposmod(_along(target.global_position, _t_node) - _along(car.global_position, node) + L * 0.5, L) - L * 0.5
	var t_along := target.linear_velocity.dot(path.forward(_t_node))
	var t_dir := -1 if t_along < 0.0 else 1
	_t_ahead = ahead
	_t_dir = t_dir
	var my_dir := -1 if car.forward_dir().dot(path.forward(node)) < 0.0 else 1
	var dist := car.global_position.distance_to(target.global_position)
	var towards := ahead < 0.0   # reverse_dir that heads for the target
	# How far up the road (the way the target is going) the cop is from it.
	var up_road := -ahead * t_dir
	if target.linear_velocity.length() < TARGET_SLOW:
		_mode = Chase.APPROACH
		if absf(ahead) > 4.0:
			reverse_dir = towards
	elif up_road > 8.0 and my_dir != t_dir:
		# Coming at it head-on: into its path, slowing to a stop there.
		_mode = Chase.APPROACH
		reverse_dir = towards
	elif up_road > 8.0 and dist > 70.0:
		_mode = Chase.WAIT
		reverse_dir = t_dir < 0
	elif dist > 70.0:
		_mode = Chase.FAR
		reverse_dir = towards
	else:
		_mode = Chase.CLOSE
		reverse_dir = t_dir < 0


## COP chasing: [aim point, desired speed]. See _chase_mode for the modes; in CLOSE it drives
## for its place round the target (AIState_Chase::CloseTargeting), and once it has held it
## a moment it rams (murder mode): it goes for the target's own spot from wherever it is -
## into its back from behind, a side-swipe from beside, a brake check from in front. Now
## and then one just ahead of the target swerves across its nose (a cut-off).
func _chase(aim: Vector3, limit: float, dt: float) -> Array:
	var to_t := target.global_position - car.global_position
	var dist := to_t.length()
	var tv := target.linear_velocity
	var t_speed := tv.length()
	var aggr := clampi(aggression, 0, 2)
	_passing = false
	# Catch-up: a cruiser that's fallen behind gets a boost, as in the original's nitrous.
	car.power_scale = 1.35 if dist > 80.0 else 1.12
	_ram_cool -= dt
	if _ram_t > 0.0:
		_ram_t -= dt
		if _ram_t <= 0.0:
			_ram_cool = RAM_COOL
	if _mode != Chase.CLOSE:
		_ram_t = 0.0
		_in_slot_t = 0.0
	var cap := maxf(limit * 1.1, 12.0)
	if gap != Vector3.INF:
		# Through the roadblock's gap rather than into the parked cruisers.
		var to_gap := gap - car.global_position
		if to_gap.dot(car.forward_dir()) > 2.0 and to_gap.length() < 90.0 and to_gap.length() < dist + 10.0:
			return [gap, minf(cap, 25.0)]
	var t_lat := path.lateral(target.global_position, _t_node)
	match _mode:
		Chase.FAR:
			return [aim, minf(limit, t_speed + 15.0)]
		Chase.WAIT:
			# A rolling block: on its line, easing off so it closes up.
			return [_road_aim(t_lat, 1.5), minf(limit, t_speed * 0.6)]
		Chase.APPROACH:
			return [target.global_position if dist < 20.0 else _road_aim(t_lat, 1.5), minf(limit, _approach_speed(dist, aggr))]
	return _close(cap, dt, aggr)


## COP: CLOSE chasing (see _chase).
func _close(cap: float, dt: float, aggr: int) -> Array:
	var t_speed := target.linear_velocity.length()
	var ext := _extent(target)
	# Measured along and across the road, which on a bend the target's own heading isn't.
	var t_lat := path.lateral(target.global_position, _t_node)
	var long := -_t_ahead * _t_dir   # m the cop is ahead of the target
	var lat := (path.lateral(car.global_position, node) - t_lat) * _t_dir   # m to its right
	var spot: Vector2 = CHASE_SPOTS[mini(aggr, 1)][clampi(chase_slot, 0, 5)]
	if _ram_t > 0.0:
		spot = Vector2.ZERO
	# Where the cop is round the target, and where its place is: -1 / 0 / +1 across (left of,
	# level with, right of it) and along (behind, level, ahead).
	# (A metre's slack across: the target weaves about its line.)
	var lat_pos := -1 if lat < -ext.x - 1.0 else (1 if lat > ext.x + 1.0 else 0)
	var long_pos := -1 if long < 2.0 - ext.y else (1 if long > ext.y + 2.0 else 0)
	var big_long := -1 if long < -(ext.y + 2.0) else (1 if long > ext.y + 2.0 else 0)
	var lat_want := -1 if spot.x < -ext.x else (1 if spot.x > ext.x else 0)
	var long_want := -1 if spot.y < -ext.y else (1 if spot.y > ext.y else 0)

	# Rams: once it has held its place a moment, or (now and then) just ahead and to one side.
	if _ram_t <= 0.0:
		_in_slot_t = _in_slot_t + dt if lat_pos == lat_want and long_pos == long_want else 0.0
		if _ram_cool <= 0.0 and _in_slot_t > RAM_HOLD[aggr] and absf(lat) < RAM_LAT[aggr] and absf(long) < RAM_LONG[aggr]:
			_ram_t = RAM_TIME[aggr]
		elif long > 2.0 * ext.y + 2.0 and long < 12.0 and absf(lat) > ext.x + 1.0 and absf(lat) <= 4.0 \
				and randf() < CUT_OFF_RATE * dt:
			_ram_t = 1.0
		if _ram_t > 0.0:
			_in_slot_t = 0.0
			spot = Vector2.ZERO
			lat_want = 0
			long_want = 0
	if _ram_t > 0.0:
		car.power_scale = 1.3

	# Across: to its place, round the target to get in front of it, or holding its line.
	var side := 1.0 if (signf(spot.x) if spot.x != 0.0 else signf(lat)) >= 0.0 else -1.0
	var want_lat := spot.x
	var hold_line := false
	var long_force := 0
	if big_long * long_want == -1:
		# Behind it with its place ahead: pass on its place's side.
		want_lat = side * (ext.x + 3.5)
		_passing = true
	elif lat_pos * lat_want == -1 and big_long == 0:
		# Alongside on the wrong side: drop back to cross behind it.
		long_force = -1
		hold_line = true
	elif lat_want == 0 and big_long == 0 and _ram_t <= 0.0:
		# Level with it and bound for behind or in front: not into its side.
		hold_line = true
	elif long_want == 1 and big_long == 1 and lat_pos == 0 and long < 20.0:
		long_force = -2

	# Along: faster to get to its place, slower when past it, a brake check in front.
	var v := t_speed
	var short := spot.y - long   # m its place is ahead of it
	if long_pos < long_want:
		v = t_speed + clampf(short * 0.6, 4.0, t_speed * 0.4 + 6.0)
	elif long_pos > long_want or long_force == -1 or long > 20.0:
		v = t_speed * _ahead_slowdown(absf(long))
	elif long_force == -2:
		v = t_speed * BRAKE_CHECK[aggr]
	else:
		v = t_speed + clampf(short * 0.5, -4.0, 4.0)
	v = minf(cap, maxf(v, 5.0))

	var an: int = _aim_node(node)
	if _ram_t > 0.0 or absf(long) < 25.0:
		# Close by it, aim nearer so it gets onto its line (harder at it when ramming).
		var look := int(clampf(2.0 + car.linear_velocity.length() * (0.08 if _ram_t > 0.0 else 0.11), 2.0, 9.0))
		an = path.idx(node + look * (-1 if reverse_dir else 1))
	var off := path.lateral(car.global_position, node)
	if not hold_line:
		off = t_lat + want_lat * _t_dir
	var lo := -maxf(path.left_width[an] - 1.5, 0.0)
	var hi := maxf(path.right_width[an] - 1.5, 0.0)
	return [path.points[an] + path.rights[an] * clampf(off, lo, hi), v]


## COP: a point on the road ahead (the aim node) `off` m right of the centre line, kept
## `margin` m inside the walls.
func _road_aim(off: float, margin: float) -> Vector3:
	var an := _aim_node(node)
	var lo := -maxf(path.left_width[an] - margin, 0.0)
	var hi := maxf(path.right_width[an] - margin, 0.0)
	return path.points[an] + path.rights[an] * clampf(off, lo, hi)


## COP: the most it drives at `dist` m from a target it's meeting or stopping for
## (AIState_Chase::ApproachTargeting): easing down to a stop 6 m short of it.
static func _approach_speed(dist: float, aggr: int) -> float:
	if dist > 150.0:
		return 80.0 if aggr == 2 else 60.0
	if dist > 100.0:
		return 70.0 if aggr == 2 else 50.0
	if dist > 50.0:
		return 50.0 if aggr == 2 else 40.0
	if dist > 25.0:
		return 40.0 if aggr == 2 else 35.0
	if dist > 10.0:
		return [20.0, 10.0, 14.0][aggr]
	if dist > 6.0:
		return 6.0 if aggr == 2 else 3.0
	return 0.0


## COP: share of the target's speed to drop to when past its place in front
## (CalculateCloseTargettingAheadSlowDownFactor), more the further ahead it is.
static func _ahead_slowdown(ahead: float) -> float:
	if ahead < 30.0:
		return 0.95
	if ahead < 100.0:
		return 0.8
	if ahead < 150.0:
		return 0.75
	if ahead < 200.0:
		return 0.7
	return 0.6


## A node a second or so up the road from `n`, like the normal aim point.
func _aim_node(n: int) -> int:
	var look := int(clampf(2.0 + car.linear_velocity.length() * 0.16, 3.0, 12.0))
	return path.idx(n + look * (-1 if reverse_dir else 1))


## Sideways shift (m, + to the car's left) of the aim point around the nearest car in the way.
## The chase target is in the way only while the cop is getting round it to its place;
## otherwise the cop keeps its own distance (and hitting it is often the point).
func _swerve() -> float:
	var fwd := car.forward_dir()
	var left := car.global_basis.x
	var reach := clampf(absf(car.speed) * 1.2, 10.0, 35.0)
	var nearest := reach
	var shift := 0.0
	var hunting := chasing and not _passing
	for o in others:
		if o == car or not is_instance_valid(o) or (hunting and o == target):
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


## RACER: a line (lateral offset, m right) round the cars on the road ahead, nearest `want`
## (the racing line or the set lane), and the speed it can do behind whichever it still
## can't get round (_traffic_cap). Each car is taken where it will be when the racer
## reaches it - a car coming the other way sooner than one going its way - and the racer
## where it can steer to by then, so it doesn't pick a gap it can't get into in time.
## Cars alongside wall it in on their side. Only what a driver would see: the road ahead.
func _plan_pass(want: float, lo: float, hi: float, dir: int) -> float:
	_plan_ticks -= 1
	if _plan_ticks > 0 and not is_nan(_pass_off):
		return clampf(_pass_off, lo, hi)
	if _plan_ticks > 0:
		return want
	_plan_ticks = 2
	var fwd := path.forward(node) * dir
	var v := maxf(car.linear_velocity.dot(fwd), 0.0)
	var my_lat := path.lateral(car.global_position, node)
	var my_s := _along(car.global_position, node)
	var my_ext := _extent(car)
	var horizon := 4.0
	var reach := 30.0 + v * horizon + 40.0 * horizon   # an oncoming car at 140 km/h, too
	# [lateral, half-width + margin, seconds until level (0: alongside now), speed along,
	#  gap (m, bumper to bumper), seconds until past it]
	var obs := []
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var oc := o as Car
		var rel: Vector3 = oc.global_position - car.global_position
		if absf(rel.y) > 6.0 or rel.length_squared() > reach * reach:
			continue
		var on := path.closest(oc.global_position, _node_of.get(oc, node))
		if path.points[on].distance_squared_to(oc.global_position) > 30.0 * 30.0:
			# Put back into play somewhere else (traffic, a reset): the local search from
			# where it was finds only the nearest bit of road there.
			on = path.closest(oc.global_position)
		_node_of[oc] = on
		var along := fposmod((_along(oc.global_position, on) - my_s) * dir + path.length * 0.5, path.length) - path.length * 0.5
		var ext := _extent(oc)
		var gap := along - my_ext.y - ext.y
		if gap < -2.0 * (my_ext.y + ext.y):
			continue   # behind
		var ov := oc.linear_velocity.dot(path.forward(on) * dir)
		if oc.freeze:
			# Far-off traffic gliding along its lane (_ghost_step) has no velocity of its own.
			for ch in oc.get_children():
				if ch is AIController and ch._ghost:
					ov = ch.traffic_speed(on, -1 if ch.reverse_dir else 1) * (-1 if ch.reverse_dir else 1) * dir
					break
		var closing := v - ov
		# Some room between them, more the faster they close.
		var margin := my_ext.x + ext.x + 0.5
		var t0 := 0.0
		var t1 := horizon
		if gap > 0.0:
			if closing < 0.5:
				continue   # pulling away
			t0 = gap / closing
			if t0 > horizon:
				continue
			margin += clampf(closing * 0.02, 0.0, 0.8)
			if ov < -2.0:
				margin += 0.8   # coming the other way: no second chances
		if closing > 0.5:
			t1 = minf((gap + 2.0 * (my_ext.y + ext.y)) / closing, horizon)
		# A car that isn't moving along the road (spun, crossing) may be anywhere across it.
		if absf(ov) < 3.0 and oc.linear_velocity.length() > 3.0:
			margin += 1.0
		obs.append([path.lateral(oc.global_position, on), margin, t0, ov, gap, t1])
	if obs.is_empty():
		_pass_off = NAN
		_pass_urgent = false
		_traffic_cap = INF
		return want
	# Onto the tarmac only: the virtual road's walls can be far out past it.
	var an := _aim_node(node)
	var w_lane := path.lane_offset(an, 1, 99) + 2.0
	var w_left := -path.lane_offset(an, -1, 99) + 2.0
	lo = maxf(lo, minf(-maxf(w_left, 5.5), want - 1.0))
	hi = minf(hi, maxf(maxf(w_lane, 5.5), want + 1.0))
	# Steering across takes time: a couple of m/s sideways, less when slow.
	var lat_rate := clampf(v * 0.055, 1.2, 2.4)
	# ...after a moment carrying on the way it's drifting now (at the limit in a bend, wide).
	var lat_v := car.linear_velocity.dot(path.rights[node])
	var prev := want if is_nan(_pass_off) else _pass_off
	var best := want
	var best_cost := INF
	var best_block := -1
	var c := lo
	while c <= hi + 0.01:
		var cost := 0.25 * absf(c - want) + 0.15 * absf(c - prev)
		var block := -1
		var block_t := INF
		for k in obs.size():
			var ob: Array = obs[k]
			var l: float = ob[0]
			var m: float = ob[1]
			var t0: float = ob[2]
			# Where the car is across the road while level with it: from where it has got to
			# by then on its way over to `c`, to where it has got to once past.
			var x0 := _lat_at(my_lat, lat_v, c, lat_rate, t0)
			var x1 := _lat_at(my_lat, lat_v, c, lat_rate, ob[5])
			var d := 0.0 if (x0 - l) * (x1 - l) <= 0.0 else minf(absf(x0 - l), absf(x1 - l))
			var hit := d < m
			if hit and t0 == 0.0 and absf(my_lat - l) < m:
				# Already too close alongside: only closing in on it is out; easing away is the fix.
				hit = (c - my_lat) * (l - my_lat) > 0.0
			if hit and t0 < block_t:
				block_t = t0
				block = k
			# A little more room than the least is worth a little.
			cost += maxf(m + 0.8 - absf(c - l), 0.0) * 1.5 * (1.0 - t0 / horizon)
		if block >= 0:
			cost += 60.0 / (0.3 + block_t)
		if cost < best_cost:
			best_cost = cost
			best = c
			best_block = block
		c += 0.5
	_pass_off = best if absf(best - want) > 0.3 or best_block >= 0 else NAN
	_pass_urgent = false
	if not is_nan(_pass_off) and absf(best - my_lat) > 1.0:
		for ob: Array in obs:
			if ob[2] < 2.5 and absf(ob[0] - best) < ob[1] + 2.0:
				_pass_urgent = true
	# Nowhere through: hold back behind it (going its way), or scrub off speed (coming at it).
	# The same when the way the car is really going (drifting wide at the limit, say) still
	# takes it into one soon: slowing down tightens the line too.
	_traffic_cap = INF
	if best_block < 0:
		for k in obs.size():
			var ob: Array = obs[k]
			if ob[2] > 0.0 and ob[2] < 1.5 and absf(my_lat + lat_v * ob[2] - ob[0]) < ob[1] - 0.3:
				best_block = k
				break
	if best_block >= 0 and obs[best_block][2] > 0.0:
		var ob: Array = obs[best_block]
		var ov: float = ob[3]
		var room := maxf(ob[4] - 2.0, 0.0)
		var a := car.brake_decel * 0.6 * _ground_grip()
		_traffic_cap = maxf(ov, 0.0) + sqrt(2.0 * a * room) if ov > -2.0 else sqrt(2.0 * a * room) * 0.5
	return best if not is_nan(_pass_off) else want


## RACER: running wide at the limit towards a wall, lift and brake a little: it tightens the
## line (the speed limit only knows about the bend, not how far out the car already is).
func _wall_cap() -> float:
	var v := car.speed
	if v < 12.0:
		return INF
	var lat := path.lateral(car.global_position, node)
	var drift := car.linear_velocity.dot(path.rights[node])
	# Where its side will be in a moment, against the wall on that side: further on when
	# the tyres are already sliding, as there's no more grip to turn in with.
	var h := 0.6 if car.slip < 0.3 else 1.1
	var room := 0.0
	if drift > 1.0:
		room = path.right_width[node] - _extent(car).x - (lat + drift * h)
	elif drift < -1.0:
		room = path.left_width[node] - _extent(car).x + (lat + drift * h)
	else:
		return INF
	return INF if room > 0.0 else v * 0.93


## RACER: where across the road (m right) a car at `x` drifting sideways at `lat_v` has got to
## `t` seconds on, heading over to `c` at `rate` once it has reacted.
static func _lat_at(x: float, lat_v: float, c: float, rate: float, t: float) -> float:
	var lag := minf(t, 0.3)
	var p := x + lat_v * lag
	var r := rate * (t - lag)
	return p + clampf(c - p, -r, r)


## Distance along the lap of `pos`, near node `n` (not snapped to the node).
func _along(pos: Vector3, n: int) -> float:
	return path.cumulative[n] + (pos - path.points[n]).dot(path.forward(n))


## Half the car's width and length (m), from its body box.
static func _extent(c: Car) -> Vector2:
	if c.has_meta("ai_ext"):
		return c.get_meta("ai_ext")
	var e := Vector2(0.95, 2.3)
	for ch in c.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			var sz: Vector3 = ((ch as CollisionShape3D).shape as BoxShape3D).size
			e = Vector2(sz.x * 0.5, sz.z * 0.5)
			break
	c.set_meta("ai_ext", e)
	return e


## The grip under the car: the weather's, less on loose ground (see TrackSurface.FEEL) when
## it has run wide off the road.
func _ground_grip() -> float:
	return car.surface_grip * lerpf(1.0, 0.68, car.off_road)

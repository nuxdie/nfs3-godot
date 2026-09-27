class_name AIController
extends Node
## Drives the parent Car along the TrackPath.
##   RACER   - races at the car's limit, picks a racing lane, overtakes.
##   TRAFFIC - cruises in a lane (optionally in the opposite direction).
##   COP     - waits by the road; chases a target once a pursuit starts.

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
var node := -1
var stranded_t := 0.0        # time spent making no headway; the race respawns the car after a while

var _stuck_t := 0.0
var _reverse_t := 0.0
var _lane_change_t := 0.0
var _progress_node := -1
var _dodge := 0.0            # TRAFFIC: temporary sideways shift around a stopped car
var _dodge_t := 0.0
var others: Array = []       # cars to avoid (set by the race)


func _ready() -> void:
	car = get_parent() as Car
	process_physics_priority = -10


func _physics_process(dt: float) -> void:
	car.hold = false
	if not enabled or path == null:
		stranded_t = 0.0
		car.throttle = 0.0
		car.hold = true
		car.steer = 0.0
		return
	node = path.closest(car.global_position, node)
	var dir := -1 if reverse_dir else 1
	var spd := car.linear_velocity.length()

	# --- where to aim (about a second ahead: further out, the line cuts across bends into the inside wall)
	var look := int(clampf(2.0 + spd * 0.16, 3.0, 12.0))
	var aim_node := path.idx(node + look * dir)
	if role == Role.TRAFFIC:
		_pull_around(dt)
	# The lane was picked where the road was wide; keep it inside the walls where it narrows.
	var off := clampf(lane + _dodge, -maxf(path.left_width[aim_node] - 2.5, 0.0), maxf(path.right_width[aim_node] - 2.5, 0.0))
	var aim: Vector3 = path.points[aim_node] + path.rights[aim_node] * off
	var desired := _speed_limit(dir)
	if role == Role.COP and chasing and target:
		var to_t := target.global_position - car.global_position
		var lead := target.linear_velocity * clampf(to_t.length() / 40.0, 0.0, 1.2)
		if to_t.length() < 70.0:
			aim = target.global_position + lead
		desired = maxf(desired, target.linear_velocity.length() + 12.0) if to_t.length() > 15.0 else target.linear_velocity.length() + 4.0
	elif role == Role.TRAFFIC:
		desired = minf(desired, cruise_speed if _dodge == 0.0 else 10.0)
	elif role == Role.COP:
		desired = 0.0

	if role == Role.RACER:
		_avoid(dt)

	# --- steer toward aim (car's local +X is left)
	var local := car.global_transform.affine_inverse() * aim
	var angle := atan2(-local.x, maxf(local.z, 0.1))
	car.steer = clampf(angle * 2.2, -1.0, 1.0)

	# --- throttle / brake
	var fwd_speed := car.speed
	if desired <= 0.0:
		# Parked (a cop waiting by the road): brakes on, no creeping forward.
		car.throttle = 0.0
		car.brake = 0.0
		car.hold = true
	elif fwd_speed < desired - 1.0:
		car.throttle = clampf((desired - fwd_speed) / 6.0, 0.25, 1.0)
		car.brake = 0.0
	elif fwd_speed > desired + 2.0:
		car.throttle = 0.0
		car.brake = clampf((fwd_speed - desired) / 8.0, 0.2, 1.0)
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
		return
	var gained := wrapi((node - _progress_node) * dir, -path.size() / 2, path.size() / 2)
	if _progress_node < 0 or gained >= 3:
		_progress_node = node
		stranded_t = 0.0
	else:
		stranded_t += dt


## Max speed for the upcoming bend: v = sqrt(a_lat * r).
func _speed_limit(dir: int) -> float:
	var worst := car.top_speed
	var here := path.forward(node) * dir
	for k in [6, 12, 20, 30]:
		var i := path.idx(node + k * dir)
		var f := path.forward(i) * dir
		var ang := here.angle_to(f)
		if ang < 0.02:
			continue
		var dist := path.points[node].distance_to(path.points[i])
		var radius := dist / ang
		var v := sqrt(9.0 * skill * car.grip * radius) + 4.0
		# Allow for braking distance to that bend.
		v = sqrt(v * v + 2.0 * car.brake_decel * 0.7 * maxf(dist - 8.0, 0.0))
		worst = minf(worst, v)
	return worst * (0.97 if role == Role.RACER else 0.8)


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

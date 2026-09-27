extends Node3D
## One race session: builds the track, spawns cars, runs the countdown, tracks
## laps/positions, and runs the Hot Pursuit rules (cops, tickets, roadblocks).

enum State { LOADING, COUNTDOWN, RACING, FINISHED }

const COP_SPEED_TRIGGER := 33.0   # m/s (~120 km/h) - speeding near a cop starts a pursuit
const BUST_RADIUS := 10.0
const BUST_TIME := 1.6
const ESCAPE_DISTANCE := 380.0
const MAX_TICKETS := 3
const TICKET_FINES := [150, 400, 0]

var state := State.LOADING
var path: TrackPath
var player: Car
var racers: Array[Dictionary] = []   # {car, name, lap, max_lap, node, progress, total, finished, time, best, lap_start}
var cops: Array[Car] = []
var traffic_cars: Array[Car] = []
var roadblock: Array[Car] = []
var race_time := 0.0
var countdown := 3.5
var tickets := 0
var fines := 0
var pursuit_time := 0.0
var bust_t := 0.0
var _cooldown := 0.0
var _finish_order: Array = []

@onready var hud: Hud = $HUD
@onready var cam: ChaseCamera = $Camera


func _ready() -> void:
	hud.race = self
	hud.show_loading("Loading " + Game.track_name(Game.track_id) + "...")
	# Let the loading text render before the heavy lifting.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_world()
	# Let the physics space pick up the track collision so spawn points can be ray-checked.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_cars()
	state = State.COUNTDOWN
	hud.hide_loading()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var track_root := Node3D.new()
	track_root.name = "Track"
	add_child(track_root)
	var ok := false
	if Game.track_id != Game.PROCEDURAL_TRACK and Game.has_game_data():
		var t := Nfs3Track.load_dir(Game.track_dir(Game.track_id))
		if t.error == "" and t.vroad.size() > 10:
			path = Nfs3TrackBuilder.build(t, track_root)
			ok = true
		else:
			push_warning("Track load failed (%s), using procedural track" % t.error)
	if not ok:
		path = ProceduralTrack.build(track_root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.48, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.35, 0.4, 0.35)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.8, 0.9)
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _make_car(data: Object, tint := Color(0, 0, 0, 0)) -> Car:
	var c := Car.new()
	c.setup(data, tint)
	add_child(c)
	return c


func _node_behind(start: int, metres: float) -> int:
	var i := start
	var d := 0.0
	while d < metres:
		var j := path.idx(i - 1)
		d += path.points[j].distance_to(path.points[i])
		i = j
	return i


## Lateral offset near `offset` at node `n` that has drivable ground under it. The virtual
## road's walls can sit far out over water or gaps, so step towards the centre line.
func _ground_offset(n: int, offset: float) -> float:
	var space := get_world_3d().direct_space_state
	for f: float in [1.0, 0.66, 0.33, 0.0]:
		var xf := path.transform_at(n, offset * f, 0.0)
		var q := PhysicsRayQueryParameters3D.create(xf.origin + xf.basis.y * 4.0, xf.origin - xf.basis.y * 4.0, 1)
		if not space.intersect_ray(q).is_empty():
			return offset * f
	return 0.0


func _spawn_cars() -> void:
	var start := 0
	var half_w := minf(path.left_width[start], path.right_width[start])
	var col := clampf(half_w * 0.4, 1.8, 3.5)

	# Player
	player = _make_car(Game.player_car_data())
	player.is_player = true
	var pc := PlayerController.new()
	player.add_child(pc)
	var audio := CarAudio.new()
	player.add_child(audio)
	cam.target = player
	hud.player = player

	var grid: Array[Car] = [player]
	var n_opp := 0
	match Game.mode:
		Game.Mode.SINGLE_RACE:
			n_opp = Game.opponents
		Game.Mode.HOT_PURSUIT:
			n_opp = mini(Game.opponents, 1)
	# Opponents come from the regular cars, not the police-liveried "Pursuit" versions.
	var pool := range(Game.cars.size()).filter(func(ci: int) -> bool:
		return ci != Game.car_index and not Game.cars[ci].name.begins_with("Pursuit"))
	pool.shuffle()
	for k in n_opp:
		var data: Object
		var tint := Color(0, 0, 0, 0)
		if pool.is_empty():
			data = Game.player_car_data()
			tint = Color.from_hsv(randf(), 0.6, 1.0)
		else:
			var ci: int = pool[k % pool.size()]
			data = Game.load_car(Game.cars[ci].path, ci)
			if data.colours.size() > 1:
				tint = data.colours[randi() % data.colours.size()]
		var ai_car := _make_car(data, tint)
		var ai := AIController.new()
		ai.role = AIController.Role.RACER
		ai.path = path
		ai.skill = randf_range(0.9, 1.05)
		ai_car.add_child(ai)
		grid.append(ai_car)
	# Player starts at the back, like the original.
	grid.reverse()
	for i in grid.size():
		var row := i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var n := _node_behind(start, 8.0 + row * 9.0)
		grid[i].reset_to(path.transform_at(n, side * col, 0.7))
		# AI racers keep to their grid lane, otherwise they all converge on the centre line.
		var grid_ai := _controller(grid[i])
		if grid_ai:
			grid_ai.lane = side * col
		racers.append({"car": grid[i], "name": grid[i].display_name, "lap": -1, "max_lap": -1, "node": n,
			"progress": path.progress_at(grid[i].global_position, n), "total": 0.0, "finished": false, "time": 0.0, "best": INF, "lap_start": 0.0})
	if Game.mode == Game.Mode.HOT_PURSUIT or Game.mode == Game.Mode.FREE_ROAM:
		_spawn_cops()
	if Game.traffic and Game.mode != Game.Mode.TIME_TRIAL:
		_spawn_traffic()
	# Racers steer around each other, traffic and parked cruisers; traffic pulls around stopped cars.
	for c in grid + traffic_cars:
		var ai: AIController = _controller(c)
		if ai:
			ai.others = grid + traffic_cars + cops


func _controller(c: Node) -> AIController:
	for ch in c.get_children():
		if ch is AIController:
			return ch
	return null


func _cop_data(i: int) -> Object:
	if Game.cop_cars.size() > 0:
		return Game.load_car(Game.cop_cars[i % Game.cop_cars.size()])
	return Game.load_car("", 3)


func _spawn_cops() -> void:
	var n_cops := 4 if Game.mode == Game.Mode.HOT_PURSUIT else 2
	for i in n_cops:
		var node := path.idx(int(path.size() * (i + 0.6) / n_cops))
		var cop := _make_car(_cop_data(i))
		cop.is_cop = true
		cop.display_name = "Police"
		var ai := AIController.new()
		ai.role = AIController.Role.COP
		ai.path = path
		ai.target = player
		ai.skill = 1.05
		# Parked on the right-hand verge (some tracks' walls are 30+ m out, so cap it).
		ai.lane = _ground_offset(node, minf(path.right_width[node] * 0.55, 7.0))
		cop.add_child(ai)
		var au := CarAudio.new()
		au.volume_db = -6.0
		cop.add_child(au)
		cop.reset_to(path.transform_at(node, ai.lane, 0.7))
		cop.set_meta("home", node)
		cops.append(cop)


func _spawn_traffic() -> void:
	var count := 8 if Game.mode != Game.Mode.FREE_ROAM else 12
	for i in count:
		var data: Object
		if Game.traffic_cars.size() > 0:
			data = Game.load_car(Game.traffic_cars[randi() % Game.traffic_cars.size()])
		else:
			data = ProceduralCar.make(4, Color.from_hsv(randf(), 0.4, 0.8))
		var tc := _make_car(data)
		var ai := AIController.new()
		ai.role = AIController.Role.TRAFFIC
		ai.path = path
		ai.reverse_dir = i % 2 == 1
		ai.cruise_speed = randf_range(16.0, 24.0)
		var node := path.idx(int(path.size() * (i + 0.3) / count))
		# Keep to a normal lane even where the walls are far apart (open ground, verges).
		var lane_w := clampf(minf(path.left_width[node], path.right_width[node]) * 0.4, 2.5, 4.5)
		ai.lane = _ground_offset(node, -lane_w if ai.reverse_dir else lane_w)
		tc.add_child(ai)
		var xf := path.transform_at(node, ai.lane, 0.7)
		if ai.reverse_dir:
			xf = xf.rotated_local(Vector3.UP, PI)
		tc.reset_to(xf)
		traffic_cars.append(tc)


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= dt
			hud.set_countdown(countdown)
			if countdown <= 0.0:
				_go()
		State.RACING:
			race_time += dt
			_update_progress()
			_update_pursuit(dt)
			_check_resets()
		State.FINISHED:
			# The rest of the field races on behind the results screen.
			_update_progress()
			_check_resets()
	if Input.is_action_just_pressed("reset_car") and state == State.RACING:
		_respawn(player)


func _go() -> void:
	state = State.RACING
	for r in racers:
		r.lap_start = 0.0
		for ch in r.car.get_children():
			if ch is PlayerController or ch is AIController:
				ch.enabled = true
	for c in traffic_cars:
		_controller(c).enabled = true
	for c in cops:
		_controller(c).enabled = true
	hud.flash("GO!", 1.0)


func _update_progress() -> void:
	var L := path.length
	for r in racers:
		var car: Car = r.car
		var n := path.closest(car.global_position, r.node)
		var prog := path.progress_at(car.global_position, n)
		if r.node >= 0:
			var prev: float = r.progress
			if prev > L * 0.75 and prog < L * 0.25:
				_lap_done(r)
			elif prev < L * 0.25 and prog > L * 0.75:
				r.lap -= 1
		r.node = n
		r.progress = prog
		r.total = r.lap * L + prog
	racers.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.time < b.time
		return a.total > b.total)


func _lap_done(r: Dictionary) -> void:
	r.lap += 1
	# Crossing the line again after backing over it (a spin, reversing off a wall) isn't a new lap.
	if r.lap <= r.max_lap:
		return
	r.max_lap = r.lap
	if r.lap <= 0:
		r.lap_start = race_time
		return
	var lap_time: float = race_time - r.lap_start
	r.lap_start = race_time
	r.best = minf(r.best, lap_time)
	if r.car == player and Game.mode != Game.Mode.FREE_ROAM:
		hud.flash("Lap %s" % Hud.fmt_time(lap_time), 2.0)
	if Game.mode == Game.Mode.FREE_ROAM:
		return
	if r.lap >= Game.laps and not r.finished:
		r.finished = true
		r.time = race_time
		_finish_order.append(r)
		var ai := _controller(r.car)
		if ai:
			ai.role = AIController.Role.TRAFFIC
			ai.cruise_speed = 18.0
		if r.car == player:
			_end_race(false)
	elif r.car == player and r.lap == Game.laps - 1:
		hud.flash("FINAL LAP", 2.0)


func _end_race(arrested: bool) -> void:
	state = State.FINISHED
	# The chase is over either way: no "PURSUIT" banner or sirens over the results.
	for cop in cops:
		_stop_chase(cop)
	hud.pursuit = false
	var pc: PlayerController = null
	for ch in player.get_children():
		if ch is PlayerController:
			pc = ch
	var auto := AIController.new()
	auto.role = AIController.Role.TRAFFIC
	auto.path = path
	auto.cruise_speed = 15.0
	auto.enabled = not arrested
	player.add_child(auto)
	if pc:
		pc.queue_free()
	var rows := []
	for r in racers:
		rows.append({"name": r.name + ("  (you)" if r.car == player else ""),
			"time": Hud.fmt_time(r.time) if r.finished else "--:--.--",
			"best": Hud.fmt_time(r.best) if r.best < INF else "--"})
	Game.last_results = rows
	var title := "ARRESTED" if arrested else "RACE COMPLETE"
	if not arrested and Game.mode != Game.Mode.TIME_TRIAL:
		title = "FINISHED %s" % Hud.ordinal(position_of(player))
	var extra := ""
	if Game.mode == Game.Mode.HOT_PURSUIT:
		extra = "Tickets: %d   Fines: $%d" % [tickets, fines]
	hud.show_results(title, rows, extra)


func position_of(car: Car) -> int:
	for i in racers.size():
		if racers[i].car == car:
			return i + 1
	return 0


func player_racer() -> Dictionary:
	for r in racers:
		if r.car == player:
			return r
	return {}


# ------------------------------------------------------------------ pursuit

func _update_pursuit(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	var any_chasing := false
	var nearest := INF
	for cop in cops:
		var ai := _controller(cop)
		var d := cop.global_position.distance_to(player.global_position)
		if not ai.chasing:
			if _cooldown <= 0.0 and d < 60.0 and player.kmh() / 3.6 > COP_SPEED_TRIGGER:
				ai.chasing = true
				cop.enable_siren(true)
				cop.get_children().filter(func(n): return n is CarAudio).map(func(a): a.siren = true)
				hud.flash("PURSUIT!", 1.5)
		elif d > ESCAPE_DISTANCE:
			_stop_chase(cop)
			hud.flash("Evaded", 1.5)
		if ai.chasing:
			any_chasing = true
			nearest = minf(nearest, d)
	if any_chasing:
		pursuit_time += dt
		if pursuit_time > 18.0 and roadblock.is_empty() and Game.mode == Game.Mode.HOT_PURSUIT:
			_spawn_roadblock()
	else:
		pursuit_time = 0.0
	hud.pursuit = any_chasing
	# Busted: stopped with a cop right on you.
	if any_chasing and nearest < BUST_RADIUS and player.linear_velocity.length() < 3.0:
		bust_t += dt
		if bust_t > BUST_TIME:
			_bust()
	else:
		bust_t = 0.0
	# Clear the roadblock once it's well behind the player.
	if not roadblock.is_empty():
		var rb_node: int = roadblock[0].get_meta("node")
		var pr := player_racer()
		# Signed distance past the roadblock, wrapped so a block just after the start line works.
		var behind := fposmod(path.cumulative[pr.node] - path.cumulative[rb_node] + path.length * 0.5, path.length) - path.length * 0.5
		if behind > 150.0:
			for n in roadblock:
				n.queue_free()
			roadblock.clear()
			# The next one only after another long stretch of chase.
			pursuit_time = 0.0


func _stop_chase(cop: Car) -> void:
	var ai := _controller(cop)
	ai.chasing = false
	cop.enable_siren(false)
	for a in cop.get_children():
		if a is CarAudio:
			a.siren = false


func _bust() -> void:
	bust_t = 0.0
	tickets += 1
	for cop in cops:
		_stop_chase(cop)
	_cooldown = 10.0
	if Game.mode == Game.Mode.HOT_PURSUIT and tickets >= MAX_TICKETS:
		hud.flash("BUSTED - you're under arrest!", 3.0)
		_end_race(true)
		return
	var fine: int = TICKET_FINES[mini(tickets - 1, TICKET_FINES.size() - 1)]
	fines += fine
	hud.flash("BUSTED! Ticket #%d - $%d fine" % [tickets, fine] if fine > 0 else "BUSTED! Warning", 3.0)


func _spawn_roadblock() -> void:
	var pr := player_racer()
	var n := path.idx(pr.node + 70)
	var w := minf(path.left_width[n], path.right_width[n])
	# Two cruisers across the road with a gap on one side to squeeze through.
	var gap_side := -1.0 if randf() < 0.5 else 1.0
	for k in 2:
		var cop := _make_car(_cop_data(k))
		cop.is_cop = true
		var off := (-0.55 + 0.6 * k) * w * gap_side
		var xf := path.transform_at(n, off, 0.6).rotated_local(Vector3.UP, PI * 0.5)
		cop.reset_to(xf)
		cop.enable_siren(true)
		cop.freeze = true
		cop.set_meta("node", n)
		roadblock.append(cop)
	# Racers head for the gap: just past the inner cruiser (parked sideways, ~2.4 m either side of
	# its centre), where there's road even when the walls are far apart. They also steer around
	# the cruisers like any other car.
	var gap_lane := (0.05 * w + 3.9) * gap_side
	for r in racers:
		var ai := _controller(r.car)
		if ai:
			ai.others.append_array(roadblock)
			ai.lane = gap_lane
	hud.flash("Roadblock ahead!", 2.0)


# ------------------------------------------------------------------ resets

func _check_resets() -> void:
	for c: Car in racers.map(func(r): return r.car) + traffic_cars + cops:
		if not is_instance_valid(c):
			continue
		# Start the nearest-node search from what the car already knows (a full scan per car is slow).
		var ai := _controller(c)
		var hint: int = player_racer().node if c == player else (ai.node if ai else -1)
		var n: int = path.closest(c.global_position, hint)
		var off: float = absf(path.lateral(c.global_position, n))
		var fell: bool = c.global_position.y < path.points[n].y - 25.0
		# Beyond the invisible wall (knocked over or through it): nothing to drive on out there.
		var lost: bool = off > maxf(path.left_width[n], path.right_width[n]) + 5.0
		# AI wedged against scenery that backing up hasn't cleared.
		var stranded: bool = ai != null and ai.stranded_t > 7.0
		if c.is_stuck_upside_down() or fell or lost or stranded:
			_respawn(c)


func _respawn(c: Car) -> void:
	var ai := _controller(c)
	# Search near the node the car was last tracked at: a global search can pick a stretch of
	# road on another level (bridges, overpasses) and skip part of the lap.
	var hint := ai.node if ai else -1
	for r in racers:
		if r.car == c:
			hint = r.node
	var n := path.closest(c.global_position, hint)
	var dir := -1 if ai and ai.reverse_dir else 1
	# Near the middle of the road: an overtaking line far out can be over a verge or a drop.
	var lane := clampf(ai.lane, -3.5, 3.5) if ai else 0.0
	# Put it down clear of other cars (a parked roadblock, a pile-up), moving up the road if need be.
	var off := 0.0
	for k in 8:
		var m := path.idx(n + k * 3 * dir)
		off = _ground_offset(m, lane)
		if k == 7 or not _car_near(c, path.transform_at(m, off, 0.0).origin, 5.0):
			n = m
			break
	if ai:
		ai.stranded_t = 0.0
		ai.lane = off
	var xf := path.transform_at(n, off, 1.0)
	if dir < 0:
		xf = xf.rotated_local(Vector3.UP, PI)
	c.reset_to(xf)


func _car_near(me: Car, pos: Vector3, radius: float) -> bool:
	for o in racers.map(func(r): return r.car) + traffic_cars + cops + roadblock:
		if o != me and is_instance_valid(o) and o.global_position.distance_to(pos) < radius:
			return true
	return false

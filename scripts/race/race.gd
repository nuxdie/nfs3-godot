extends Node3D
## One race session: builds the track, spawns cars, runs the countdown, tracks
## laps/positions, and runs the Hot Pursuit rules (cops, tickets, roadblocks).

enum State { LOADING, COUNTDOWN, RACING, FINISHED }

const COP_SPEED_TRIGGER := 33.0   # m/s (~120 km/h) - speeding near a cop starts a pursuit
const COP_SIGHT := 60.0
const BUST_RADIUS := 10.0
const BUST_TIME := 1.6
const ESCAPE_DISTANCE := 380.0
const HEAT_STEP := 20.0           # s of unbroken chase per heat level (max 3)
const RIVAL_HOLD := 5.0           # s a busted rival sits at the side of the road
const MAX_TICKETS := 3
const RB_HALF := 2.4              # m, half a cruiser's length (they park across the road)
const RB_TRACK_RANGE := 80.0      # m short of a roadblock where its cruisers start covering your line
const RB_COMMIT := 18.0           # m: closer than this they hold still, so a late juke gets through
const RB_SLIDE := 4.5             # m/s the pair shuffles sideways at
const RB_MIN_WAY := 3.0           # m, an opening narrower than this makes a racer switch sides
const MAX_LIGHT_CONES := 16   # MAX_BEAMS in track.gdshader
const MAX_SHADOWS := 16       # MAX_SHADOWS in track.gdshader
const TICKET_FINES := [150, 400]   # the third ticket in Hot Pursuit is an arrest; Free Roam keeps fining

var state := State.LOADING
var path: TrackPath
var player: Car
var racers: Array[Dictionary] = []   # {car, name, lap, max_lap, node, progress, total, finished, time, best, lap_start}
var cops: Array[Car] = []
var traffic_cars: Array[Car] = []
var roadblock: Array[Car] = []
var spikes: Array[SpikeStrip] = []
var race_time := 0.0
var countdown := 3.5
var tickets := 0
var fines := 0
var pursuit_time := 0.0   # length of the current chase after the player
var heat := 0              # 0 no chase; 1..3 as it drags on: backup units, roadblocks, spikes
var _block_t := 0.0        # until the next roadblock may go up
var _backup_t := 0.0       # until the next backup unit may join
var _gap := Vector3.INF    # the way through the current roadblock
var _rb := {}              # roadblock geometry: node, side (+1 gap to the right), w, shift range, shift
var _finish_order: Array = []
var _results_dirty := false   # a car finished behind the results screen; refresh the table
var _reset_check_t := 0.0
var _skid_marks: SkidMarks
var _track_mat: ShaderMaterial   # NFS3 track only: takes the night tint and headlight cones
var _reflections: Reflections

@onready var hud: Hud = $HUD
@onready var cam: ChaseCamera = $Camera


func _ready() -> void:
	hud.race = self
	hud.show_loading("Loading " + Game.track_name(Game.track_id) + "...")
	# Let the loading text render before the heavy lifting. The player can pause and restart
	# or quit meanwhile, so stop if this scene has already been swapped out.
	var tree := get_tree()
	for k in 2:
		await tree.process_frame
		if not is_inside_tree():
			return
	_build_world()
	# Let the physics space pick up the track collision so spawn points can be ray-checked.
	for k in 2:
		await tree.physics_frame
		if not is_inside_tree():
			return
	_spawn_cars()
	state = State.COUNTDOWN
	hud.hide_loading()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var world := TrackWorld.load_track(Game.track_id)
	add_child(world.root)
	path = world.path
	_track_mat = world.track_mat
	world.light(self, Game.night, Game.weather, get_viewport())
	var w: Weather = null
	if world.horizon or Game.weather:
		w = Weather.new()
		add_child(w)
		w.setup(world.horizon, path, world.env, _track_mat, world.root)
	_reflections = Reflections.new()
	add_child(_reflections)
	_reflections.setup(world.root, path, world.env, _track_mat, w)


func _make_car(data: Object, tint := Color(0, 0, 0, 0)) -> Car:
	var c := Car.new()
	c.setup(data, tint)
	# At night every car's headlights light the other cars; weak GPUs keep just the player's.
	c.set_headlight_beam(Game.night and Game.quality != Game.Quality.LOW)
	if _skid_marks == null:
		var sfx := Nfs3Sfx.shared(Game.data_root)
		_skid_marks = SkidMarks.new([1024, 2048, 4096][Game.quality], sfx.skid_atlas if sfx else null)
		add_child(_skid_marks)
	c.add_child(CarEffects.new(_skid_marks))
	if Game.damage:
		c.add_child(CarDamage.new())
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
	player.set_headlight_beam(true, true)
	var pc := PlayerController.new()
	player.add_child(pc)
	var audio := CarAudio.new()
	player.add_child(audio)
	cam.target = player
	_reflections.follow(player)
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
		grid[i].reset_to(path.transform_at(n, side * col, 0.0))
		# AI racers keep to their grid lane, otherwise they all converge on the centre line.
		var grid_ai := _controller(grid[i])
		if grid_ai:
			grid_ai.lane = side * col
		racers.append({"car": grid[i], "name": grid[i].display_name, "lap": -1, "max_lap": -1, "node": n,
			"progress": path.progress_at(grid[i].global_position, n), "total": 0.0, "finished": false, "time": 0.0, "best": INF, "lap_start": 0.0,
			"bust_t": 0.0, "cool": 0.0})
	if Game.mode == Game.Mode.HOT_PURSUIT or Game.mode == Game.Mode.FREE_ROAM:
		_spawn_cops()
	if Game.traffic and Game.mode != Game.Mode.TIME_TRIAL:
		_spawn_traffic()
	# Racers steer around each other, traffic and parked cruisers; traffic pulls around stopped
	# cars; cops dodge anything but whoever they're chasing.
	for c in grid + traffic_cars + cops:
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
		return Game.load_car(Game.cop_cars[i % Game.cop_cars.size()], 3)
	return Game.load_car("", 3)


## Cruisers spread round the track: all but one parked on the verge, the last on patrol.
func _spawn_cops() -> void:
	var n_cops := 4 if Game.mode == Game.Mode.HOT_PURSUIT else 2
	for i in n_cops:
		var node := path.idx(int(path.size() * (i + 0.6) / n_cops))
		var cop := _make_cop(i)
		var ai := _controller(cop)
		if i < n_cops - 1:
			# Parked on the right-hand verge (some tracks' walls are 30+ m out, so cap it).
			ai.home = node
			ai.home_lane = _ground_offset(node, minf(path.right_width[node] * 0.55, 7.0))
			ai.lane = ai.home_lane
		else:
			ai.lane = _ground_offset(node, 3.0)
		cop.reset_to(path.transform_at(node, ai.lane, 0.0))
		cops.append(cop)


func _make_cop(i: int) -> Car:
	var cop := _make_car(_cop_data(i))
	cop.is_cop = true
	cop.display_name = "Police"
	var ai := AIController.new()
	ai.role = AIController.Role.COP
	ai.path = path
	ai.skill = 1.05
	ai.cruise_speed = 22.0
	cop.add_child(ai)
	var au := CarAudio.new()
	au.volume_db = -6.0
	cop.add_child(au)
	return cop


func _spawn_traffic() -> void:
	var count := 8 if Game.mode != Game.Mode.FREE_ROAM else 12
	for i in count:
		var data: Object
		if Game.traffic_cars.size() > 0:
			data = Game.load_car(Game.traffic_cars[randi() % Game.traffic_cars.size()], 4)
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
		var xf := path.transform_at(node, ai.lane, 0.0)
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
			_check_resets(dt)
		State.FINISHED:
			# The rest of the field races on behind the results screen, on the same clock.
			race_time += dt
			_update_progress()
			_check_resets(dt)
	if Input.is_action_just_pressed("reset_car") and state == State.RACING:
		_respawn(player)


func _process(_dt: float) -> void:
	_update_car_shadows()
	if Game.night:
		_update_headlight_cones()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("headlights") and player:
		player.set_headlights(not player.headlights_on)
	elif e.is_action_pressed("high_beam") and player:
		player.set_high_beam(not player.high_beam)
	elif e.is_action_pressed("handling_feel"):
		# A/B the body sway and progressive grip against the plain NFS3 handling (all cars).
		Car.body_sway = not Car.body_sway
		Car.progressive_grip = Car.body_sway
		hud.flash("Handling: " + ("sway + progressive grip" if Car.body_sway else "classic"), 1.5)


## Hands the track shader the drop shadows of the MAX_SHADOWS cars nearest the camera.
func _update_car_shadows() -> void:
	var cam3d := get_viewport().get_camera_3d()
	if _track_mat == null or cam3d == null:
		return
	var eye := cam3d.global_position
	var near: Array = []
	for c: Car in racers.map(func(r): return r.car) + traffic_cars + cops + roadblock:
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		var d := c.global_position.distance_squared_to(eye)
		if d < 200.0 * 200.0:
			near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var pos := PackedVector3Array()
	var ax := PackedVector3Array()
	var az := PackedVector3Array()
	for k in mini(near.size(), MAX_SHADOWS):
		var f: Array = near[k][1].shadow_footprint()
		pos.append(f[0])
		ax.append(f[1])
		az.append(f[2])
	pos.resize(MAX_SHADOWS)
	ax.resize(MAX_SHADOWS)
	az.resize(MAX_SHADOWS)
	_track_mat.set_shader_parameter("shadow_count", mini(near.size(), MAX_SHADOWS))
	_track_mat.set_shader_parameter("shadow_pos", pos)
	_track_mat.set_shader_parameter("shadow_x", ax)
	_track_mat.set_shader_parameter("shadow_z", az)


## Hands the track shader the light cones (headlights, reversing lamps) nearest the camera;
## it has MAX_LIGHT_CONES slots.
func _update_headlight_cones() -> void:
	var cam3d := get_viewport().get_camera_3d()
	if _track_mat == null or cam3d == null:
		return
	var eye := cam3d.global_position
	var lit: Array = []
	for c: Car in racers.map(func(r): return r.car) + traffic_cars + cops + roadblock:
		if not is_instance_valid(c):
			continue
		var d := c.global_position.distance_squared_to(eye)
		if d < 250.0 * 250.0:
			for cone in c.light_cones():
				lit.append([d, cone])
	lit.sort_custom(func(a, b): return a[0] < b[0])
	var pos := PackedVector3Array()
	var dir := PackedVector3Array()
	var shape := PackedVector3Array()
	for k in mini(lit.size(), MAX_LIGHT_CONES):
		var xf: Transform3D = lit[k][1][0]
		pos.append(xf.origin)
		dir.append(-xf.basis.z.normalized())
		shape.append(lit[k][1][1])
	pos.resize(MAX_LIGHT_CONES)
	dir.resize(MAX_LIGHT_CONES)
	shape.resize(MAX_LIGHT_CONES)
	_track_mat.set_shader_parameter("beam_count", mini(lit.size(), MAX_LIGHT_CONES))
	_track_mat.set_shader_parameter("beam_pos", pos)
	_track_mat.set_shader_parameter("beam_dir", dir)
	_track_mat.set_shader_parameter("beam_shape", shape)


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
	hud.flash("GO!", 1.0, "go")


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
	if _results_dirty:
		_results_dirty = false
		hud.update_results(_result_rows())


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
		elif state == State.FINISHED:
			_results_dirty = true
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
	var rows := _result_rows()
	var title := "ARRESTED" if arrested else "RACE COMPLETE"
	if not arrested and Game.mode != Game.Mode.TIME_TRIAL:
		title = "FINISHED %s" % Hud.ordinal(position_of(player))
	var extra := ""
	if Game.mode == Game.Mode.HOT_PURSUIT:
		extra = "Tickets: %d   Fines: $%d" % [tickets, fines]
	hud.show_results(title, rows, extra)


## The leaderboard in its current order; also kept in Game.last_results.
func _result_rows() -> Array:
	var rows := []
	for r in racers:
		rows.append({"name": r.name, "you": r.car == player,
			"time": Hud.fmt_time(r.time) if r.finished else "--:--.--",
			"best": Hud.fmt_time(r.best) if r.best < INF else "--",
			"t": r.time if r.finished else INF})
	Game.last_results = rows
	return rows


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
	for r in racers:
		r.cool = maxf(r.cool - dt, 0.0)
	for cop in cops.duplicate():
		var ai := _controller(cop)
		if ai.chasing:
			if not is_instance_valid(ai.target) or cop.global_position.distance_to(ai.target.global_position) > ESCAPE_DISTANCE:
				var was_player := ai.target == player
				_stop_chase(cop)
				if was_player and _chasers(player).is_empty():
					hud.flash("Evaded", 1.5)
		else:
			var speeder := _speeder_near(cop)
			if speeder:
				_start_chase(cop, speeder)

	var on_player := _chasers(player)
	hud.pursuit = not on_player.is_empty()
	if on_player.is_empty():
		pursuit_time = 0.0
		heat = 0
		_dismiss_backup()
	else:
		pursuit_time += dt
		var h := mini(1 + int(pursuit_time / HEAT_STEP), 3)
		if h > heat and heat > 0:
			hud.flash("Heat level %d" % h, 1.5, "alert")
		heat = h
		# Backup units: one per heat level above the first.
		_backup_t -= dt
		var backup := cops.filter(func(c): return c.has_meta("backup")).size()
		if backup < heat - 1 and _backup_t <= 0.0:
			_spawn_backup()
			_backup_t = 8.0
		_block_t -= dt
		if heat >= 2 and roadblock.is_empty() and _block_t <= 0.0:
			_spawn_roadblock(heat >= 3)

	# Busted: stopped with a cop right on you. Rivals get held up; the player gets a ticket.
	for r in racers:
		var nearest := INF
		for cop in _chasers(r.car):
			nearest = minf(nearest, cop.global_position.distance_to(r.car.global_position))
		if nearest < BUST_RADIUS and r.car.linear_velocity.length() < 3.0:
			r.bust_t += dt
			if r.bust_t > BUST_TIME:
				r.bust_t = 0.0
				if r.car == player:
					_bust()
					if state != State.RACING:
						return
				else:
					_bust_rival(r)
		else:
			r.bust_t = 0.0
	_update_roadblock(dt)
	_clear_roadblock()


## Racer speeding within sight of a cop that isn't on a chase, preferring the player.
func _speeder_near(cop: Car) -> Car:
	var found: Car = null
	for r in racers:
		var c: Car = r.car
		if r.finished or r.cool > 0.0 or c.speed < COP_SPEED_TRIGGER:
			continue
		if cop.global_position.distance_to(c.global_position) < COP_SIGHT:
			if c == player:
				return c
			found = c if found == null else found
	return found


func _chasers(target: Car) -> Array[Car]:
	var out: Array[Car] = []
	for cop in cops:
		var ai := _controller(cop)
		if ai.chasing and ai.target == target:
			out.append(cop)
	return out


func _start_chase(cop: Car, target: Car) -> void:
	var ai := _controller(cop)
	# Every second cop on the same car goes round it to block instead of ramming.
	ai.chase_slot = _chasers(target).size() % 2
	if target == player and ai.chase_slot == 0 and _chasers(target).is_empty():
		hud.flash("PURSUIT!", 1.5, "alert")
	ai.target = target
	ai.chasing = true
	cop.enable_siren(true)
	for a in cop.get_children():
		if a is CarAudio:
			a.siren = true


func _stop_chase(cop: Car) -> void:
	var ai := _controller(cop)
	ai.chasing = false
	ai.target = null
	cop.enable_siren(false)
	for a in cop.get_children():
		if a is CarAudio:
			a.siren = false


func _bust() -> void:
	tickets += 1
	for cop in _chasers(player):
		_stop_chase(cop)
	player_racer().cool = 10.0
	if Game.mode == Game.Mode.HOT_PURSUIT and tickets >= MAX_TICKETS:
		hud.flash("BUSTED - you're under arrest!", 3.0, "alert")
		_end_race(true)
		return
	var fine: int = TICKET_FINES[mini(tickets - 1, TICKET_FINES.size() - 1)]
	fines += fine
	hud.flash("BUSTED! Ticket #%d - $%d fine" % [tickets, fine], 3.0, "alert")


## A rival pulled over: it sits out a few seconds while the cop writes the ticket.
func _bust_rival(r: Dictionary) -> void:
	for cop in _chasers(r.car):
		_stop_chase(cop)
	r.cool = RIVAL_HOLD + 8.0
	hud.flash("%s busted!" % r.name, 2.0)
	var ai := _controller(r.car)
	if ai == null:
		return
	ai.enabled = false
	get_tree().create_timer(RIVAL_HOLD, false, true).timeout.connect(func() -> void:
		if is_instance_valid(ai):
			ai.enabled = true)


## Called in from further back up the road, already on the player's tail.
func _spawn_backup() -> void:
	var pr := player_racer()
	var fwd := player.linear_velocity.dot(path.forward(pr.node)) >= 0.0
	var dir := 1 if fwd else -1
	# Out of sight behind the player, at least a road's bend or two back.
	var n: int = pr.node
	var d := 0.0
	while d < 170.0:
		var m := path.idx(n - dir)
		d += path.points[m].distance_to(path.points[n])
		n = m
	var cop := _make_cop(cops.size())
	var ai := _controller(cop)
	ai.lane = _ground_offset(n, 0.0)
	ai.reverse_dir = not fwd
	ai.enabled = true
	cop.set_meta("backup", true)
	ai.gap = _gap
	var xf := path.transform_at(n, ai.lane, 0.0)
	if not fwd:
		xf = xf.rotated_local(Vector3.UP, PI)
	cop.reset_to(xf)
	# Arrives at speed rather than from a standstill.
	cop.linear_velocity = cop.forward_dir() * minf(player.linear_velocity.length(), 40.0)
	cops.append(cop)
	_add_obstacles([cop])
	_start_chase(cop, player)
	ai.others = racers.map(func(r): return r.car) + traffic_cars + cops + roadblock


## Backup units go home once the chase is off: out of the player's sight, they vanish.
func _dismiss_backup() -> void:
	for cop in cops.duplicate():
		if cop.has_meta("backup") and not _controller(cop).chasing \
				and cop.global_position.distance_to(player.global_position) > 120.0:
			cops.erase(cop)
			cop.queue_free()


## Every AI car steers around `cars` from now on.
func _add_obstacles(cars: Array) -> void:
	for c: Car in racers.map(func(r): return r.car) + traffic_cars + cops:
		var ai := _controller(c)
		if ai:
			ai.others = ai.others.filter(func(o): return is_instance_valid(o))
			for o in cars:
				if o != c and not ai.others.has(o):
					ai.others.append(o)


## Two cruisers parked across the road a little way ahead of the player, with a gap on one
## side to squeeze through. At top heat a spike strip lies across the gap.
func _spawn_roadblock(with_spikes: bool) -> void:
	var pr := player_racer()
	var n := path.idx(pr.node + 70)
	var w := minf(path.left_width[n], path.right_width[n])
	var gap_side := -1.0 if randf() < 0.5 else 1.0
	for k in 2:
		var cop := _make_car(_cop_data(k))
		cop.is_cop = true
		var off := (-0.55 + 0.6 * k) * w * gap_side
		var xf := path.transform_at(n, off, 0.0).rotated_local(Vector3.UP, PI * 0.5)
		cop.reset_to(xf)
		cop.enable_siren(true)
		# Kinematic, so it shoves whatever it slides into rather than passing through.
		cop.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		cop.freeze = true
		cop.set_meta("node", n)
		cop.set_meta("off", off)
		cop.set_meta("lift", (cop.global_position - xf.origin).dot(xf.basis.y))
		roadblock.append(cop)
	# How far the pair can shuffle across (along the road's right, times gap_side) while
	# staying on the tarmac: towards the gap until the inner cruiser meets the edge, away
	# until the outer one does. Measured on the ground, as the walls can sit far out.
	var reach_gap := absf(_ground_offset(n, w * gap_side))
	var reach_far := absf(_ground_offset(n, -w * gap_side))
	_rb = {"node": n, "side": gap_side, "w": w, "shift": 0.0, "vel": 0.0,
		"gap_edge": reach_gap, "far_edge": reach_far,
		"max": maxf(reach_gap - 0.05 * w - RB_HALF, 0.0), "min": minf(-(reach_far - 0.55 * w - RB_HALF), 0.0)}
	# Racers head for the gap: just past the inner cruiser (parked sideways, ~2.4 m either side of
	# its centre), where there's road even when the walls are far apart. They also steer around
	# the cruisers like any other car.
	var gap_lane := (0.05 * w + 3.9) * gap_side
	_add_obstacles(roadblock)
	for r in racers:
		r.erase("rb_pick")
		var ai := _controller(r.car)
		if ai:
			ai.lane = gap_lane
	# Chasing cops thread the gap too, aiming a little past the cruisers.
	_gap = path.transform_at(path.idx(n + 2), gap_lane, 0.0).origin
	for cop in cops:
		_controller(cop).gap = _gap
	if with_spikes:
		# A few metres short of the cruisers, covering the gap.
		var m := _node_behind(n, 7.0)
		var strip := SpikeStrip.new(7.0)
		add_child(strip)
		var xf := path.transform_at(m, gap_lane, 0.0)
		var q := PhysicsRayQueryParameters3D.create(xf.origin + xf.basis.y * 3.0, xf.origin - xf.basis.y * 3.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			xf.origin = hit.position
		strip.global_transform = xf
		strip.punctured.connect(_on_punctured)
		spikes.append(strip)
	hud.flash("Roadblock ahead!" if not with_spikes else "Roadblock - spikes!", 2.0, "alert")


## The roadblock pair shuffles across the road to cover the line of the racer bearing down
## on it, as in Most Wanted: commit to the gap early and it closes, leaving an opening on
## the other side. Close in, the cruisers hold still, so a late juke gets through.
## Racers and chasing cops keep re-picking whichever opening is left.
func _update_roadblock(dt: float) -> void:
	if _rb.is_empty() or roadblock.is_empty():
		return
	var n: int = _rb.node
	var side: float = _rb.side
	var w: float = _rb.w
	var fwd := path.forward(n)
	var origin: Vector3 = path.points[n]
	# The racer closing fastest on the block, and how far off it is.
	var threat: Dictionary = {}
	var near := INF
	for r in racers:
		var c: Car = r.car
		if r.finished or not is_instance_valid(c):
			continue
		var along := (c.global_position - origin).dot(fwd)   # - short of the block
		var closing := -signf(along) * c.linear_velocity.dot(fwd)
		var d := absf(along)
		if closing > 3.0 and d < RB_TRACK_RANGE and d < near:
			near = d
			threat = r
	var target: float = _rb.shift
	if not threat.is_empty() and near > RB_COMMIT:
		var c: Car = threat.car
		# Where it'll be across the road a moment from now: sit the pair's middle on that.
		var cn: int = threat.node
		var lat := path.lateral(c.global_position, cn) + c.linear_velocity.dot(path.rights[cn]) * 0.5
		target = clampf(lat * side + 0.25 * w, _rb.min, _rb.max)
	var want := clampf((target - _rb.shift) * 3.0, -RB_SLIDE, RB_SLIDE)
	if near <= RB_COMMIT:
		want = 0.0
	_rb.vel = move_toward(_rb.vel, want, RB_SLIDE * 3.0 * dt)
	_rb.shift += _rb.vel * dt
	for cop in roadblock:
		var xf := path.transform_at(n, cop.get_meta("off") + _rb.shift * side, 0.0).rotated_local(Vector3.UP, PI * 0.5)
		cop.global_transform = xf.translated_local(Vector3.UP * cop.get_meta("lift"))

	# The two ways through, as [width, centre] across the road (times side): by the gap-side
	# edge past the inner cruiser, and by the far edge past the outer one.
	var inner: float = _rb.shift + 0.05 * w + RB_HALF
	var outer: float = _rb.shift - 0.55 * w - RB_HALF
	var ways := [[_rb.gap_edge - inner, (inner + _rb.gap_edge) * 0.5], [outer + _rb.far_edge, (outer - _rb.far_edge) * 0.5]]
	var best := 0 if ways[0][0] >= ways[1][0] else 1
	for r in racers:
		var c: Car = r.car
		var ai := _controller(c)
		if ai == null or r.finished:
			continue
		var along := (c.global_position - origin).dot(fwd)
		if along > 0.0 or along < -RB_TRACK_RANGE * 1.6:
			continue
		# Stick with the chosen way until it's closing up, then switch.
		var pick: int = r.get("rb_pick", best)
		if ways[pick][0] < RB_MIN_WAY and ways[1 - pick][0] > ways[pick][0]:
			pick = 1 - pick
		r.rb_pick = pick
		ai.lane = ways[pick][1] * side
	_gap = path.transform_at(path.idx(n + 2), ways[best][1] * side, 0.0).origin
	for cop in cops:
		_controller(cop).gap = _gap


## Takes the roadblock down once it's well behind the player.
func _clear_roadblock() -> void:
	if roadblock.is_empty():
		return
	var rb_node: int = roadblock[0].get_meta("node")
	var pr := player_racer()
	# Signed distance past the roadblock, wrapped so a block just after the start line works.
	var behind := fposmod(path.cumulative[pr.node] - path.cumulative[rb_node] + path.length * 0.5, path.length) - path.length * 0.5
	# A chase that's ended short of it (the player turned back, or got busted) takes it down too.
	if behind > 150.0 or (heat == 0 and absf(behind) > 300.0):
		for c in roadblock:
			c.queue_free()
		for sp in spikes:
			sp.queue_free()
		roadblock.clear()
		spikes.clear()
		_rb = {}
		_gap = Vector3.INF
		for cop in cops:
			_controller(cop).gap = _gap
		# The next one only after another stretch of chase.
		_block_t = 20.0


func _on_punctured(c: Car) -> void:
	if c == player:
		hud.flash("Spiked! Tyres shredded", 2.5, "alert")
	elif not c.is_cop and position_of(c) > 0:
		hud.flash("%s hit the spikes" % c.display_name, 1.5)


# ------------------------------------------------------------------ resets

func _check_resets(dt: float) -> void:
	# Every trigger below is seconds-long, so a few checks a second is plenty.
	_reset_check_t -= dt
	if _reset_check_t > 0.0:
		return
	_reset_check_t = 0.1
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
		# A shortcut can run further out than the virtual road's walls, so only off the
		# drivable surface. In free roam the player may wander off: the reset key brings them back.
		var lost: bool = off > maxf(path.left_width[n], path.right_width[n]) + path.lost_margin and not _on_road(c) \
			and not (c == player and Game.mode == Game.Mode.FREE_ROAM)
		# AI wedged against scenery that backing up hasn't cleared. A cop out of the player's
		# sight gets put back on the road sooner: nobody sees it jump.
		var give_up := 3.0 if c.is_cop and c.global_position.distance_to(player.global_position) > 150.0 else 7.0
		var stranded: bool = ai != null and ai.stranded_t > give_up
		if c.is_stuck_upside_down() or fell or lost or stranded:
			_respawn(c)


## Whether the car is over the track's drivable surface (the "Road" body, not the terrain).
func _on_road(c: Car) -> bool:
	var from := c.global_position + Vector3.UP
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1, [c.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider.name == "Road"


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
	var xf := path.transform_at(n, off, 0.0)
	if dir < 0:
		xf = xf.rotated_local(Vector3.UP, PI)
	c.reset_to(xf, 0.3)


func _car_near(me: Car, pos: Vector3, radius: float) -> bool:
	for o in racers.map(func(r): return r.car) + traffic_cars + cops + roadblock:
		if o != me and is_instance_valid(o) and o.global_position.distance_to(pos) < radius:
			return true
	return false

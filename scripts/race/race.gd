extends Node3D
## One race session: builds the track, spawns cars, runs the countdown, tracks
## laps/positions, and runs the Hot Pursuit rules (cops, tickets, roadblocks).

## INTRO: the track's own fly-by round the grid (its trNN00.can), before the countdown.
enum State { LOADING, COUNTDOWN, RACING, FINISHED, INTRO }

const COP_SPEED_TRIGGER := 33.0   # m/s (~120 km/h) - speeding near a cop starts a pursuit
const COP_SIGHT := 60.0
const BUST_RADIUS := 10.0
const BUST_TIME := 1.6
const ESCAPE_DISTANCE := 380.0
const HEAT_STEP := 20.0           # s of unbroken chase per heat level (max 3)
const RIVAL_HOLD := 5.0           # s a busted rival sits at the side of the road
const MAX_TICKETS := 3
const PLAYER_HOLD := 6.0          # s the tower marks you BUSTED while the officer writes it up
const SHORTCUT_BACK := 30         # nodes behind and ahead of its last a car off on a shortcut
const SHORTCUT_AHEAD := 250       # is looked for along the lap (_update_progress)
const RADIO_DB := -3.0   # the police radio, a little under the voices on the spot
const DROWN_DEPTH := 0.3          # m under a stream or lake surface that counts as in the water
const DROWN_TIME := 1.5           # s in the water before the car is put back on the road
const RB_HALF := 2.4              # m, half a cruiser's length (they park across the road)
const RB_TRACK_RANGE := 80.0      # m short of a roadblock where its cruisers start covering your line
const RB_COMMIT := 18.0           # m: closer than this they hold still, so a late juke gets through
const RB_SLIDE := 4.5             # m/s the pair shuffles sideways at
const RB_MIN_WAY := 3.0           # m, an opening narrower than this makes a racer switch sides
const MAX_LIGHT_CONES := 16   # MAX_BEAMS in track.gdshader
const MAX_SHADOWS := 16       # MAX_SHADOWS in track.gdshader
const TICKET_FINES := [150, 400]   # the third ticket in Hot Pursuit is an arrest; Free Roam keeps fining
const SPECTATE_CUT := 3.0      # s the camera lingers on a finished car before cutting to the race

var state := State.LOADING
var path: TrackPath
var player: Car
var racers: Array[Dictionary] = []   # {car, name, lap, max_lap, node, progress, total, finished, time, best, lap_start}
var cops: Array[Car] = []
var traffic_cars: Array[Car] = []
var parked_cars: Array[Car] = []
var _parking: Array = []
var roadblock: Array[Car] = []
var spikes: Array[SpikeStrip] = []
var _rb_props: Array[Node3D] = []   # High Stakes' cones, medians and flares round the roadblock
var race_time := 0.0
var countdown := 3.5
const INTRO_TIME := 6.0     # s the start fly-by takes
var _intro: CanFile
var _intro_t := 0.0
var _intro_xf: Transform3D
var _intro_from := 0.0      # where along it to start (0..1): past keys inside the scenery
var tickets := 0
var fines := 0
var pursuit_time := 0.0   # length of the current chase after the player
var heat := 0              # 0 no chase; 1..3 as it drags on: backup units, roadblocks, spikes
var _block_t := 0.0        # until the next roadblock may go up
var _backup_t := 0.0       # until the next backup unit may join
var _gap := Vector3.INF    # the way through the current roadblock
var _rb := {}              # roadblock geometry: node, side (+1 gap to the right), w, shift range, shift
var _heli: Helicopter      # High Stakes' helicopter, over the player from heat 2
var _heli_data := {}       # ...its model, loaded the first time it's called in
var _finish_order: Array = []
var _results_dirty := false   # a car finished behind the results screen; refresh the table
var _cut_t := -1.0            # spectating: counts down to leaving a car that's finished
var _reset_check_t := 0.0
var _water_t := {}         # car -> seconds spent in a stream or a lake
var _skid_marks: SkidMarks
var _track_mat: ShaderMaterial   # NFS3 track only: takes the night tint and headlight cones
var _reflections: Reflections

var _rival_pool := []      # the rivals' cars, picked before loading (Game.rival_pool)
var _quip_t := 8.0         # s until a rival may next have a word passing you
var _ahead_of_you := {}    # rivals' cars ahead of you at the last check

@onready var hud: Hud = $HUD
## The voices: lap calls, the finish, the cops' loudhailer and radio (NFS3's speech banks).
var speech := Speech.new()
@onready var cam: ChaseCamera = $Camera


func _ready() -> void:
	hud.race = self
	speech.hp2 = Game.is_hp2_track(Game.track_id)   # its own voices on Hot Pursuit 2's tracks
	add_child(speech)
	hud.show_loading()
	# Let the loading screen render before the heavy lifting; stop if this scene has been
	# swapped out meanwhile.
	var tree := get_tree()
	for k in 2:
		await tree.process_frame
		if not is_inside_tree():
			return
	# The track itself is read and built on a worker thread (as the menu's postcards are),
	# so the loading screen keeps moving; the rest has to be done here.
	hud.loading_stage("Reading the track", 0.04, 0.55)
	var built := []
	var task := WorkerThreadPool.add_task(func() -> void:
		built.append(TrackWorld.load_track(Game.track_id, Game.night, Game.layout)))
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree():
		return
	# Then the cars' files, one a frame so the screen keeps moving (reading them on the worker
	# thread crashes now and then: something in them isn't safe off the main thread). The
	# rivals are picked now for it.
	_rival_pool = Game.rival_pool(_opponent_count())
	var cars := _cars_to_load()
	for i in cars.size():
		hud.loading_stage("Loading the cars", 0.56 + 0.18 * i / cars.size(), 0.56 + 0.18 * (i + 1) / cars.size())
		await tree.process_frame
		if not is_inside_tree():
			return
		if i == 0:
			Game.player_car_data()
		else:
			Game.load_car(cars[i][0], cars[i][1])
	hud.loading_stage("Lighting the scenery", 0.76, 0.82)
	await tree.process_frame
	_build_world(built[0])
	var dir := Game.track_dir(Game.track_id)
	if dir != "":
		cam.tv = TvCameras.load_dir(dir, Game.is_hs_track(Game.track_id))
		cam.tv.lay_out(Game.layout_mirrored(), Game.layout_reversed(), path.size())
		cam.tv_path = path
	hud.loading_stage("Putting the cars on the grid", 0.84, 0.97)
	# Let the physics space pick up the track collision so spawn points can be ray-checked.
	for k in 2:
		await tree.physics_frame
		if not is_inside_tree():
			return
	# Where scenery stands on the road, so the AI steers round it.
	path.scan_obstacles(get_world_3d().direct_space_state)
	_spawn_cars()
	# Resolution that gives way when the GPU can't keep up (the preset's scale is its ceiling).
	var drs := DynamicResolution.new()
	add_child(drs)
	drs.watch(hud.mirror_viewport())
	hud.hide_loading()
	# Nothing to start in free roam: hand over control straight away.
	if Game.mode == Game.Mode.FREE_ROAM:
		_go()
	else:
		_start_intro()


var _flybys: Array[CanFile] = []   # the track's own fly-bys (Porsche Unleashed's)

## The track's start fly-by, if it has one and it's wanted; else straight to the countdown.
## Its keys circle the player's car looking at it, but which way the files' "ahead" runs
## isn't settled (NFS3 and High Stakes seem to differ), so each fly-by is tried both ways
## round and the one that keeps the car in sight best is flown; none if all fly through
## the scenery.
func _start_intro() -> void:
	var dir := Game.track_dir(Game.track_id)
	var list: Array[CanFile] = []
	if Game.intro_flyby and dir != "":
		list = CanFile.intros(dir, Game.is_hs_track(Game.track_id))
		# Porsche Unleashed's come with the track (Nfs5Track.flybys).
		if list.is_empty():
			for c in _flybys:
				var copy := CanFile.new()
				copy.keys.assign(c.keys.map(func(k: Dictionary) -> Dictionary: return k.duplicate()))
				list.append(copy)
	if Game.layout_mirrored():
		for c in list:
			for k in c.keys:
				k.pos = Vector3(-k.pos.x, k.pos.y, k.pos.z)
	var best := 0.35   # the most keys that may lose sight of the car
	_intro = null
	var space := get_world_3d().direct_space_state
	var look := player.global_position + Vector3.UP * 0.6
	# The ground, walls and buildings (and what the chase camera keeps out of).
	var mask := 1 | Nfs3TrackBuilder.SCENERY_LAYER | Nfs3TrackBuilder.CAMERA_LAYER
	for c: CanFile in list:
		for yaw in [0.0, PI]:
			var xf := player.global_transform.rotated_local(Vector3.UP, yaw)
			var blocked := 0
			var first_clear := -1
			for i in c.keys.size():
				# Both ways: a ray starting inside a building doesn't hit its walls.
				var at := xf * (c.keys[i].pos as Vector3)
				var hit := not space.intersect_ray(PhysicsRayQueryParameters3D.create(at, look, mask)).is_empty() \
					or not space.intersect_ray(PhysicsRayQueryParameters3D.create(look, at, mask)).is_empty()
				blocked += int(hit)
				if not hit and first_clear < 0:
					first_clear = i
			var share := float(blocked) / c.keys.size()
			if share < best:
				best = share
				_intro = c
				_intro_xf = xf
				_intro_from = float(first_clear) / (c.keys.size() - 1)
	if _intro == null:
		state = State.COUNTDOWN
		return
	_intro_t = 0.0
	cam.set_physics_process(false)
	state = State.INTRO
	hud.flash(Game.track_name(Game.track_id), INTRO_TIME * 0.6)


## Flies the camera along the fly-by, round the player's car on the grid, looking at it.
## Throttle, handbrake or Enter skips to the countdown.
func _update_intro(dt: float) -> void:
	_intro_t += dt
	var f := _intro_t / INTRO_TIME
	var skip := Input.is_action_just_pressed("accelerate") or Input.is_action_just_pressed("handbrake") \
		or Input.is_action_just_pressed("ui_accept")
	if f >= 1.0 or skip:
		cam.set_physics_process(true)
		state = State.COUNTDOWN
		return
	# Easing out into the chase view where it ends.
	cam.global_position = _intro_xf * _intro.position_at(lerpf(_intro_from, 1.0, 1.0 - pow(1.0 - f, 1.6)))
	var look := player.global_position + Vector3.UP * 0.6
	if cam.global_position.distance_to(look) > 0.2:
		cam.look_at(look, Vector3.UP)


# ------------------------------------------------------------------ world

## The track (TrackWorld.load_track, built off the main thread) into the scene, with its
## sky, weather and reflections.
func _build_world(world: TrackWorld) -> void:
	if Game.quality == Game.Quality.LOW:
		_trim_draw_distance(world.root)
		_merge_land(world.root)
	add_child(world.root)
	_parking = world.root.get_meta("parking", [])
	_flybys.assign(world.root.get_meta("flybys", []))
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
	if Game.is_hp2_track(Game.track_id):
		var amb := Hp2Ambience.make(Game.track_dir(Game.track_id), world.mirrored)
		if amb:
			add_child(amb)


const LOW_CAR_RANGE := 250.0   # m: how far off cars are drawn on Low quality
const LOW_SCENERY_RANGE := 0.6  # share of its draw distance scenery keeps on Low quality


const MERGE_CELL := 600.0   # m: Low quality merges the land's meshes into squares this big


## Low quality: the procedural track's land and road come in hundreds of small meshes, each
## a draw call, which a weak GPU pays for more than for their vertices. Merged into big
## squares (per material, and per draw distance and the like) they're a few dozen.
static func _merge_land(root: Node) -> void:
	var shaders := [Game.shader("res://shaders/proc_ground.gdshader"), Game.shader("res://shaders/proc_road.gdshader")]
	var groups := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m == null or not m.shader in shaders or mi.get_script() != null or not mi.visible \
				or mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.get_child_count() > 0:
			continue
		# Where it sits under the root (which isn't in the tree yet).
		var xf := mi.transform
		var p := mi.get_parent()
		while p != root and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var c := xf * mi.mesh.get_aabb().get_center()
		var key := [m.get_instance_id(), mi.mesh.surface_get_format(0), floori(c.x / MERGE_CELL), floori(c.z / MERGE_CELL),
			mi.visibility_range_end, mi.cast_shadow, mi.layers]
		if not groups.has(key):
			groups[key] = []
		groups[key].append([mi, xf])
	for key: Array in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		var n := 0
		for entry: Array in list:
			var mi: MeshInstance3D = entry[0]
			var xf: Transform3D = entry[1]
			var a := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if xf != Transform3D.IDENTITY:
				verts = xf * verts
				if a[Mesh.ARRAY_NORMAL] != null:
					var nb := xf.basis.inverse().transposed()
					var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
					for k in nrm.size():
						nrm[k] = (nb * nrm[k]).normalized()
					a[Mesh.ARRAY_NORMAL] = nrm
			a[Mesh.ARRAY_VERTEX] = verts
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
			for k in idx.size():
				idx[k] += n
			a[Mesh.ARRAY_INDEX] = idx
			for t in Mesh.ARRAY_MAX:
				if a[t] == null:
					continue
				if out[t] == null:
					out[t] = a[t]
				else:
					out[t].append_array(a[t])
			n += verts.size()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var first: MeshInstance3D = list[0][0]
		var merged := MeshInstance3D.new()
		merged.mesh = mesh
		merged.material_override = first.material_override
		merged.visibility_range_end = first.visibility_range_end
		merged.visibility_range_end_margin = first.visibility_range_end_margin
		merged.cast_shadow = first.cast_shadow
		merged.layers = first.layers
		for meta in first.get_meta_list():
			merged.set_meta(meta, first.get_meta(meta))
		root.add_child(merged)
		# Gone at once (the root isn't in the tree yet): the rain cover mustn't find them too.
		for entry: Array in list:
			entry[0].free()


## Low quality: the scenery (trees, buildings, signs, rails) is drawn out to only part of its
## usual distance, as a weak GPU pays for each of them however small in the fog. The land and
## road themselves ("landscape") keep theirs, or they'd leave holes to the sky.
static func _trim_draw_distance(root: Node) -> void:
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end > 0.0 and not g.has_meta("landscape"):
			g.visibility_range_end *= LOW_SCENERY_RANGE


func _make_car(data: Object, tint := Color(0, 0, 0, 0), upgrade := 0) -> Car:
	var c := Car.new()
	c.setup(data, tint, upgrade)
	# At night every car's headlights light the other cars; weak GPUs keep just the player's.
	c.set_headlight_beam(Game.night and Game.quality != Game.Quality.LOW)
	if _skid_marks == null:
		var sfx := Nfs3Sfx.shared(Game.data_root)
		_skid_marks = SkidMarks.new([1024, 2048, 4096][Game.quality], sfx.skid_atlas if sfx else null)
		add_child(_skid_marks)
	c.add_child(CarEffects.new(_skid_marks))
	if Game.damage:
		c.add_child(CarDamage.new())
	if Game.quality == Game.Quality.LOW:
		# Each car is a dozen draws; out in the fog they aren't worth them.
		for g in c.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = LOW_CAR_RANGE
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


func _opponent_count() -> int:
	match Game.mode:
		Game.Mode.SINGLE_RACE, Game.Mode.SPECTATE, Game.Mode.HOT_PURSUIT:
			return Game.opponents
	return 0


## [path, preset] of every car _spawn_cars can put on the track, for Game.load_car to read
## ahead on the loading thread: yours, the rivals', and the police and traffic models.
func _cars_to_load() -> Array:
	var out := [[Game.cars[Game.car_index].path, Game.car_index]]
	var rivals := Game.circuit_rivals() if not Game.circuit_run.is_empty() else []
	for r in rivals:
		out.append([Game.cars[r.car].path, r.car])
	if rivals.is_empty() and not _rival_pool.is_empty():
		for k in _opponent_count():
			var ci: int = _rival_pool[k % _rival_pool.size()]
			out.append([Game.cars[ci].path, ci])
	if Game.mode == Game.Mode.HOT_PURSUIT or Game.mode == Game.Mode.FREE_ROAM:
		for m in Game.cop_models():
			out.append([m, 3])
	if Game.traffic and Game.mode != Game.Mode.TIME_TRIAL:
		for m in Game.traffic_models():
			out.append([m, 4])
	return out


func _spawn_cars() -> void:
	var start := path.start_node
	var half_w := minf(path.left_width[start], path.right_width[start])
	var col := clampf(half_w * 0.4, 1.8, 3.5)

	# Player (in spectate mode an AI racer drives it, and `player` is whichever car is watched)
	var player_data := Game.player_car_data()
	player = _make_car(player_data, Game.paint_tint(Game.car_index, player_data), Game.player_upgrade())
	player.is_player = true
	# A tournament's car comes with the damage it wasn't repaired of.
	if not Game.circuit_run.is_empty():
		for ch in player.get_children():
			if ch is CarDamage:
				ch.wear(Game.garage_damage(Game.car_index))
	player.set_headlight_beam(true, true)
	if spectating():
		var auto := AIController.new()
		auto.role = AIController.Role.RACER
		auto.path = path
		auto.skill = randf_range(0.9, 1.05)
		player.add_child(auto)
	else:
		player.add_child(PlayerController.new())
	var audio := CarAudio.new()
	player.add_child(audio)
	cam.target = player
	_reflections.follow(player)
	hud.player = player

	var grid: Array[Car] = [player]
	var n_opp := _opponent_count()
	var pool := _rival_pool
	# A tournament's circuit races the same field every race (less those knocked out).
	var rivals := Game.circuit_rivals() if not Game.circuit_run.is_empty() else []
	if not rivals.is_empty():
		n_opp = rivals.size()
	player.set_meta("circuit_key", "you")
	player.set_meta("racer", true)
	# Each rival a driver of its own (Rivals), in the driver's colours; a circuit's keep theirs.
	var drivers := Rivals.pick(n_opp)
	for k in n_opp:
		var data: Object
		var driver: Dictionary = Rivals.get_driver(rivals[k].driver if not rivals.is_empty() else drivers[k])
		if not rivals.is_empty():
			var ci: int = rivals[k].car
			data = Game.load_car(Game.cars[ci].path, ci)
		elif pool.is_empty():
			data = Game.player_car_data()
		else:
			var ci: int = pool[k % pool.size()]
			data = Game.load_car(Game.cars[ci].path, ci)
		var ai_car := _make_car(data, driver.color, rivals[k].upgrade if not rivals.is_empty() else Game.rival_upgrade())
		ai_car.display_name = driver.name
		ai_car.set_meta("racer", true)
		ai_car.set_meta("driver", driver)
		var ai := AIController.new()
		ai.role = AIController.Role.RACER
		ai.path = path
		ai.skill = randf_range(0.95, 1.02)
		if not rivals.is_empty():
			ai_car.set_meta("circuit_key", rivals[k].key)
			ai.skill = Game.circuit_skill() * randf_range(0.99, 1.01)
		ai.set_driver(driver)
		ai_car.add_child(ai)
		ai_car.add_child(CarAudio.new())
		grid.append(ai_car)
	# Player starts at the back, like the original; a tournament's circuit lines up after its
	# first race by the standings (Game.circuit_grid).
	grid.reverse()
	if not rivals.is_empty():
		var order := Game.circuit_grid()
		grid.sort_custom(func(a: Car, b: Car) -> bool:
			return order.find(a.get_meta("circuit_key")) < order.find(b.get_meta("circuit_key")))
	for i in grid.size():
		var row := i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var n := _node_behind(start, 8.0 + row * 9.0)
		grid[i].reset_to(path.transform_at(n, side * col, 0.0))
		# AI racers keep to their grid lane, otherwise they all converge on the centre line.
		var grid_ai := _controller(grid[i])
		if grid_ai:
			grid_ai.lane = side * col
		var drv: Dictionary = grid[i].get_meta("driver", {})
		# Your row in the tower says YOU (the car's name is under it).
		var short: String = "YOU" if grid[i] == player and not spectating() else drv.get("short", grid[i].display_name)
		racers.append({"car": grid[i], "name": grid[i].display_name, "lap": -1,
			"color": drv.get("color", UiKit.ACCENT), "short": short, "max_lap": -1, "node": n,
			"progress": path.progress_at(grid[i].global_position, n), "total": 0.0, "finished": false, "time": 0.0, "best": INF, "lap_start": 0.0,
			"bust_t": 0.0, "cool": 0.0, "model": grid[i].car_data.display_name, "tickets": 0, "held_t": 0.0})
	if Game.mode == Game.Mode.HOT_PURSUIT or Game.mode == Game.Mode.FREE_ROAM:
		_spawn_cops()
	if Game.traffic and Game.mode != Game.Mode.TIME_TRIAL:
		_spawn_traffic()
	# Cars parked where the track leaves room for them (the procedural track's streets and lots).
	parked_cars = ParkedCars.spawn(get_tree(), _make_car, _parking)
	# Racers steer around each other, traffic and parked cruisers; traffic pulls around stopped
	# cars; cops dodge anything but whoever they're chasing.
	for c in grid + traffic_cars + cops:
		var ai: AIController = _controller(c)
		if ai:
			ai.others = grid + traffic_cars + cops


func _controller(c: Node) -> AIController:
	# Looked up many times a tick: remembered on the car once found.
	var ai: AIController = c.get_meta("ai") if c.has_meta("ai") else null
	if is_instance_valid(ai) and ai.get_parent() == c:
		return ai
	for ch in c.get_children():
		if ch is AIController:
			c.set_meta("ai", ch)
			return ch
	return null


func _cop_data(i: int) -> Object:
	var models := Game.cop_models()
	if models.size() > 0:
		return Game.load_car(models[i % models.size()], 3)
	return Game.load_car("", 3)


## Cruisers spread round the track: all but one parked on the verge, the last on patrol.
## A pursuit gets four, and one more for every two rivals past the first.
func _spawn_cops() -> void:
	var n_cops := 4 + maxi(_opponent_count() - 1, 0) / 2 if Game.mode == Game.Mode.HOT_PURSUIT else 2
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
	au.volume_db = -2.0   # with CarAudio.OTHERS_DB, 6 dB under the player
	cop.add_child(au)
	cop.body_entered.connect(_on_cop_hit.bind(cop))
	return cop


## The traffic: the original's own cars (or stand-ins), spread along the road either side
## of the start in both directions and the lanes each way, from then on kept around the
## racers (_update_traffic).
func _spawn_traffic() -> void:
	var count := 8 if Game.mode != Game.Mode.FREE_ROAM else 12
	var models := Game.traffic_models()
	var start: int = player_racer().node
	for i in count:
		var data: Object
		if models.size() > 0:
			data = Game.load_car(models[randi() % models.size()], 4)
		else:
			data = ProceduralCar.make(4, Color.from_hsv(randf(), 0.4, 0.8))
		# Porsche Unleashed's traffic comes in any of its stock paints (Nfs5Car.STOCK_PAINTS), Hot
		# Pursuit 2's in its skins' colours.
		var tc := _make_car(data, data.colours.pick_random() if (data is Nfs5Car or data is Nfs6Car) and not data.colours.is_empty() else Color(0, 0, 0, 0))
		var ai := AIController.new()
		ai.role = AIController.Role.TRAFFIC
		ai.path = path
		ai.cruise_speed = 40.0   # the speed limit sets its pace (AIController.traffic_speed)
		ai.drive_side = TrafficRules.drive_side(Game.track_id, Game.layout_mirrored() and Game.track_dir(Game.track_id) != "")
		ai.traffic_lane = 1
		tc.add_child(ai)
		tc.add_child(CarAudio.new())
		traffic_cars.append(tc)
		# Alternately ahead and behind, further out each pair, clear of the grid.
		var approach := 1 if i % 2 == 0 else -1
		var metres := lerpf(140.0, TrafficRules.SPAWN_MAX, float(i / 2) / maxf(count / 2 - 1, 1.0))
		for k in 6:
			if _place_traffic(tc, player, start, approach, metres + k * 25.0, false, k == 5):
				break


## Puts traffic car `tc` down `metres` along the road ahead of (`approach` +1) or behind
## (-1) node `from`, heading either way in one of the lanes on its side of the road there,
## in play for racer `basis`. `moving`: at its cruising speed, and only out of the racers'
## and the camera's sight. Returns false, moving nothing, if the spot won't do (with `force`,
## any spot will).
func _place_traffic(tc: Car, basis: Car, from: int, approach: int, metres: float, moving: bool, force := false) -> bool:
	var ai := _controller(tc)
	var n := path.ahead(from, approach, metres)
	var dir := 1 if randf() < 0.5 else -1
	var side := ai.drive_side * dir
	var k := 1 + randi() % path.lane_count(n, side)
	var off := _ground_offset(n, path.lane_offset(n, side, k))
	var xf := path.transform_at(n, off, 0.0)
	if _car_near(tc, xf.origin, 14.0) and not force:
		return false
	if moving:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(xf.origin) < TrafficRules.SPAWN_MIN * 0.75:
			return false
		for r in racers:
			if r.car.global_position.distance_to(xf.origin) < TrafficRules.SPAWN_MIN * 0.6:
				return false
	if dir < 0:
		xf = xf.rotated_local(Vector3.UP, PI)
	ai.reverse_dir = dir < 0
	ai.traffic_lane = k
	ai.lane = off
	ai.speed_factor = TrafficRules.SPEED_FACTORS.pick_random()
	ai.basis = basis
	ai.put_down(xf, n, minf(ai.traffic_speed(n, dir), 20.0) if moving else 0.0)
	return true


var _traffic_t := 0.0

## Keeps the traffic where the racers are, as the original's AILife does: each car is in
## play for the racer nearest it, and one that has dropped out of every racer's reach is
## brought back further up the road from one of them (the player, half the time), in front
## of a fast one, heading either way.
func _update_traffic(dt: float) -> void:
	_traffic_t -= dt
	if _traffic_t > 0.0 or traffic_cars.is_empty():
		return
	_traffic_t = 0.5
	var cam := get_viewport().get_camera_3d()
	for tc in traffic_cars:
		if not is_instance_valid(tc):
			continue
		var p := tc.global_position
		var near: Car = null
		var d := INF
		for r in racers:
			var dr: float = r.car.global_position.distance_to(p)
			if dr < d:
				d = dr
				near = r.car
		var ai := _controller(tc)
		ai.basis = near
		if d < TrafficRules.LIVE or cam and cam.global_position.distance_to(p) < TrafficRules.LIVE:
			continue
		var r: Dictionary = player_racer() if randf() < 0.5 else racers.pick_random()
		var along: float = r.car.linear_velocity.dot(path.forward(r.node))
		var approach := 1 if randf() < 0.5 else -1
		if absf(along) > TrafficRules.FAST:
			approach = 1 if along > 0.0 else -1
		_place_traffic(tc, r.car, r.node, approach, randf_range(TrafficRules.SPAWN_MIN, TrafficRules.SPAWN_MAX), true)


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	match state:
		State.INTRO:
			_update_intro(dt)
		State.COUNTDOWN:
			var before := countdown
			countdown -= dt
			# "Three", "two", "one" as the numbers come up (and "go" in _go).
			for n in [3, 2, 1]:
				if before > n and countdown <= n:
					_say_count(3 - n)
			hud.set_countdown(countdown)
			if countdown <= 0.0:
				_go()
		State.RACING:
			race_time += dt
			_update_progress()
			_call_place(dt)
			_update_pursuit(dt)
			_update_traffic(dt)
			_check_resets(dt)
		State.FINISHED:
			# The rest of the field races on behind the results screen, on the same clock.
			race_time += dt
			_update_progress()
			_update_traffic(dt)
			_check_resets(dt)
	if Input.is_action_just_pressed("reset_car") and state == State.RACING and not spectating():
		_respawn(player)
	if spectating() and state != State.LOADING:
		_update_spectate(dt)
		# The arrows too while the race is on (the results screen needs them for its buttons).
		var arrows := state != State.FINISHED
		if Input.is_action_just_pressed("watch_next") or arrows and Input.is_action_just_pressed("steer_right"):
			_watch_step(1)
		elif Input.is_action_just_pressed("watch_prev") or arrows and Input.is_action_just_pressed("steer_left"):
			_watch_step(-1)


func _process(_dt: float) -> void:
	_update_car_shadows()
	if Game.night:
		_update_headlight_cones()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("headlights") and player:
		player.set_headlights(not player.headlights_on)
	elif e.is_action_pressed("high_beam") and player:
		player.set_high_beam(not player.high_beam)
	elif e.is_action_pressed("soft_top") and player and player.has_soft_top():
		player.set_top_down(not player.top_down)
		hud.flash("Top down" if player.top_down else "Top up", 1.0)
	elif e.is_action_pressed("handling_feel"):
		# A/B the body sway and progressive grip against the plain NFS3 handling (all cars).
		Car.body_sway = not Car.body_sway
		Car.progressive_grip = Car.body_sway
		hud.flash("Handling: " + ("sway + progressive grip" if Car.body_sway else "classic"), 1.5)


func _input(e: InputEvent) -> void:
	# Ahead of the GUI, which could otherwise swallow it.
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F4:
		if e.shift_pressed:
			_probe_hide_next()
		else:
			_probe_view()


## What a drawable is, for the probe: its shader's file, or its material's class.
static func _probe_what(g: GeometryInstance3D) -> String:
	var mat: Material = g.material_override
	if mat == null and g is MeshInstance3D and (g as MeshInstance3D).mesh:
		var m := (g as MeshInstance3D).mesh
		mat = m.surface_get_material(0) if m.get_surface_count() > 0 else null
	elif mat == null and g is CPUParticles3D and (g as CPUParticles3D).mesh:
		mat = (g as CPUParticles3D).mesh.surface_get_material(0)
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		return (mat as ShaderMaterial).shader.resource_path.get_file()
	return mat.get_class() if mat else "-"


## Debug (F4): prints what's drawn, bar the track's own scenery (near the camera, or at any
## distance for particles and anything over 15 m), and saves the frame, to catch a rare
## visual glitch in the act. Shift+F4 hides one kind of thing more each press (_probe_hide_next).
func _probe_view() -> void:
	var cam3d := get_viewport().get_camera_3d()
	if cam3d == null:
		return
	var eye := cam3d.global_position
	var rows: Array = []
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or (_track_mat and g.material_override == _track_mat):
			continue
		var what := _probe_what(g)
		if what.begins_with("track"):
			continue
		var box := g.global_transform * g.get_aabb()
		var d := (eye.clamp(box.position, box.end) - eye).length()
		var p := g as CPUParticles3D
		var big := box.size.length() > 15.0 and not g is MultiMeshInstance3D
		if d > 40.0 and not big and not (p and p.emitting):
			continue
		var extra := ""
		if p:
			# Particles' AABB says nothing: where the emitter is, and what it's making.
			extra = "  emitting %s at %s (%.0f m) scale %.1f-%.1f colour %s" % [p.emitting,
				p.global_position.snapped(Vector3.ONE * 0.1), p.global_position.distance_to(eye),
				p.scale_amount_min, p.scale_amount_max, p.color]
		rows.append([d, "%6.1f m  size %s  %s  layers %d  %s%s%s" % [d, box.size.snapped(Vector3.ONE * 0.1),
			what, g.layers, g.get_path(), extra, "  <== BIG" if big else ""]])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	var lines := PackedStringArray(["--- F4 probe at %s, looking %s" % [eye.snapped(Vector3.ONE * 0.1),
		(-cam3d.global_basis.z).snapped(Vector3.ONE * 0.01)]])
	for r in rows:
		lines.append(r[1])
	if _skid_marks:
		var near: Array = [eye]
		for c: Car in racers.map(func(r): return r.car) + traffic_cars + cops:
			if is_instance_valid(c):
				near.append(c.global_position)
		lines.append_array(_skid_marks.odd_marks(near).slice(0, 40))
	var path := "user://probe_%d" % Time.get_unix_time_from_system()
	get_viewport().get_texture().get_image().save_png(path + ".png")
	lines.append("--- saved " + ProjectSettings.globalize_path(path) + ".png/.txt")
	var f := FileAccess.open(path + ".txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	print("\n".join(lines))
	hud.flash("Probe saved", 1.5)


var _probe_hidden := 0   # how many of _PROBE_KINDS Shift+F4 has hidden so far
const _PROBE_KINDS := ["particles", "skid marks", "other cars", "player car", "all non-track"]


## Debug (Shift+F4): hides the next kind of drawable in _PROBE_KINDS on top of the ones
## already hidden (then shows everything again), to find which one a glitch belongs to.
func _probe_hide_next() -> void:
	_probe_hidden = (_probe_hidden + 1) % (_PROBE_KINDS.size() + 1)
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if _probe_what(g).begins_with("track") or (_track_mat and g.material_override == _track_mat):
			continue
		var car: Node = g
		while car != null and not car is Car:
			car = car.get_parent()
		var kind := 4
		if g is CPUParticles3D or g is GPUParticles3D:
			kind = 0
		elif g is SkidMarks:
			kind = 1
		elif car != null:
			kind = 3 if car == player else 2
		# (Its own flag, so the game's own visibility switching is left alone.)
		var off := kind < _probe_hidden
		if off and not g.has_meta("probe_layers"):
			g.set_meta("probe_layers", g.layers)
			g.layers = 0
		elif not off and g.has_meta("probe_layers"):
			g.layers = g.get_meta("probe_layers")
			g.remove_meta("probe_layers")
	var msg := "Probe: all shown" if _probe_hidden == 0 else "Probe hid: " + ", ".join(_PROBE_KINDS.slice(0, _probe_hidden))
	print(msg)
	hud.flash(msg, 2.0)


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
	if Game.mode != Game.Mode.FREE_ROAM:
		hud.flash("GO!", 1.0, "go")
		_say_count(3)


## NFS3's countdown voice: 0 "three" .. 3 "go".
func _say_count(i: int) -> void:
	if Game.mode == Game.Mode.FREE_ROAM:
		return
	var s := GameSounds.shared()
	if s and s.countdown:
		GameSounds.say(self, s.countdown.stream(i))


func _update_progress() -> void:
	var L := path.length
	for r in racers:
		var car: Car = r.car
		var n := path.closest(car.global_position, r.node)
		# Away from the lap's road on a side road (a shortcut): where along the lap it's got to.
		if not path.side_roads.is_empty() and r.node >= 0 \
				and absf(path.lateral(car.global_position, n)) > maxf(path.wall_width(n, -1.0), path.wall_width(n, 1.0)) + 2.0:
			n = path.closest_along(car.global_position, r.node, SHORTCUT_BACK, SHORTCUT_AHEAD)
		var prog := path.progress_at(car.global_position, n)
		if not path.closed:
			# A point-to-point run: the start line, then the finish line, each crossed once.
			var line: float = path.cumulative[path.start_node if r.lap < 0 else path.finish_node]
			var prev: float = r.progress
			if prev < line and prog >= line:
				_lap_done(r)
			elif r.lap >= 0 and prev >= path.cumulative[path.start_node] and prog < path.cumulative[path.start_node]:
				r.lap = -1
			r.node = n
			r.progress = prog
			r.total = prog
			continue
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
	_update_rivals(L)
	if _results_dirty:
		_results_dirty = false
		hud.update_results(_result_rows())


## The rivals' share of the race run (their form, AIController.race_frac), and a word from
## one now and then as it gets past you.
func _update_rivals(L: float) -> void:
	var span := L * Game.race_laps() if path.closed else path.cumulative[path.finish_node] - path.cumulative[path.start_node]
	var from := 0.0 if path.closed else path.cumulative[path.start_node]
	var you := player_racer()
	_quip_t -= get_physics_process_delta_time()
	for r in racers:
		var ai := _controller(r.car)
		if ai and ai.role == AIController.Role.RACER:
			ai.race_frac = (r.total - from) / maxf(span, 1.0)
		if r.car == player or you.is_empty() or spectating() or r.finished or you.finished:
			continue
		var ahead: bool = r.total > you.total
		var was: bool = _ahead_of_you.get(r.car, ahead)
		_ahead_of_you[r.car] = ahead
		if ahead and not was and _quip_t <= 0.0 and race_time > 6.0 and r.car.has_meta("driver") \
				and r.car.global_position.distance_to(player.global_position) < 40.0 and randf() < 0.6:
			var d: Dictionary = r.car.get_meta("driver")
			hud.chatter(d.name, d.color, d.quips.pick_random())
			_quip_t = randf_range(14.0, 24.0)


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
	if not r.has("cross"):
		r.cross = {}
	r.cross[r.lap] = race_time
	if r.car == player and r.lap >= 2 and lap_time < r.best and Game.mode != Game.Mode.FREE_ROAM and r.lap < Game.race_laps():
		speech.say("lapeng", [0, 1, 2])
	r.best = minf(r.best, lap_time)
	if r.car == player and Game.mode != Game.Mode.FREE_ROAM:
		hud.flash("Lap %s" % Hud.fmt_time(lap_time), 2.0)
	if Game.mode == Game.Mode.FREE_ROAM:
		return
	if r.lap >= Game.race_laps() and not r.finished:
		r.finished = true
		r.time = race_time
		_finish_order.append(r)
		var ai := _controller(r.car)
		if ai:
			ai.role = AIController.Role.TRAFFIC
			ai.cruise_speed = 18.0
		if spectating():
			if r.car == player:
				hud.flash("%s finishes %s" % [r.name, Hud.ordinal(_finish_order.size())], 2.5)
				_cut_t = SPECTATE_CUT
			if state != State.FINISHED and racers.all(func(o: Dictionary) -> bool: return o.finished):
				_end_race(false)
			elif state == State.FINISHED:
				_results_dirty = true
		elif r.car == player:
			_say_place(_finish_order.size())
			_end_race(false)
		elif state == State.FINISHED:
			_results_dirty = true
	elif r.car == player and r.lap == Game.race_laps() - 1:
		hud.flash("FINAL LAP", 2.0)
		speech.say("lapeng", [5, 6])
	elif r.car == player and r.lap + 1 <= 7:
		speech.say("lapeng", r.lap + 6)   # 7 is "lap 2"
	if r.car == player and not r.finished:
		_say_gap(r)


var _said_place := 0      # the place last announced (0: none yet)
var _place_t := 0.0       # s the player has held a new place
var _place_cool := 0.0    # s until another place may be called


## The co-driver calls a new place once it's held 1.5 s: "second place!", "you're in the lead!".
func _call_place(dt: float) -> void:
	if racers.size() < 2 or Game.mode == Game.Mode.FREE_ROAM:
		return
	_place_cool -= dt
	var p := position_of(player)
	if _said_place == 0:
		_said_place = p   # the grid position goes unsaid
	if p == _said_place:
		_place_t = 0.0
		return
	_place_t += dt
	if _place_t < 1.5 or _place_cool > 0.0 or speech.busy():
		return
	_said_place = p
	_place_cool = 6.0
	if p == 1:
		speech.say("vocasst", [1, 10, 11])
	elif p == racers.size():
		speech.say("vocasst", 8)   # "last place!"
	else:
		speech.say("vocasst", p if p < 8 else 9)


## At the line, behind: how far the leader is ahead ("you're 3 seconds back", "you're way behind").
func _say_gap(r: Dictionary) -> void:
	var lead := INF
	for o in racers:
		if o != r and o.has("cross") and o.cross.has(r.lap):
			lead = minf(lead, o.cross[r.lap])
	if lead == INF:
		return   # nobody's crossed ahead: leading
	var gap := roundi(race_time - lead)
	if gap < 1:
		return
	speech.say("vocasst", 16 + gap if gap <= 12 else [29, 30])   # 17 is "one second back"


## "You placed first!" .. "You placed last."
func _say_place(place: int) -> void:
	if place == 1:
		speech.say("lapeng", [16, 17, 18])
	elif place == racers.size():
		speech.say("lapeng", 28)
	elif place <= 3:
		speech.say("lapeng", [17 + place, 18 + place] if place == 2 else [21, 22])
	elif place <= 8:
		speech.say("lapeng", 19 + place)   # 23 is fourth


## The dispatcher's voice for this track (NFS3 recorded one for each of its pursuit tracks,
## with the officers' three voices, a to c; other tracks borrow Hometown's).
func _dispatch() -> String:
	return "disp%02d" % _radio_track()


## A cop's radio voice: offNN + a..c, the same one for the same car.
func _officer(cop: Car) -> String:
	var i := maxi(cops.find(cop), 0)
	return "off%02d%s" % [_radio_track(), ["a", "b", "c"][i % 3]]


func _radio_track() -> int:
	var n := Game.track_id.trim_prefix("trk").to_int() if Game.track_id.begins_with("trk") else -1
	return n if n in [0, 1, 2, 3, 8] else 0


## A cop joining the chase calls in ("<unit> to County"), the dispatcher answers ("go ahead,
## unit <unit>": the same eight units, in the same order, in both banks) and he reports
## `report` (an officer patch or list).
func _radio_call(cop: Car, report: Variant) -> void:
	var unit := maxi(cops.find(cop), 0) % 8
	speech.say(_officer(cop), 16 + unit, RADIO_DB)
	speech.say(_dispatch(), 36 + unit, RADIO_DB)
	speech.say(_officer(cop), report, RADIO_DB)


## "He's going more than 100 / 120 / 140 / 160" (mph), or "here he comes" below that.
func _speed_call() -> Variant:
	var mph := absf(player.speed) * 2.237
	for k in [3, 2, 1, 0]:
		if mph > [100, 120, 140, 160][k]:
			return 60 + k
	return [36, 37, 39]


func _end_race(arrested: bool) -> void:
	state = State.FINISHED
	# The chase is over either way: no "PURSUIT" banner or sirens over the results.
	for cop in cops:
		_stop_chase(cop)
	hud.pursuit = false
	if spectating():
		hud.show_results("RACE COMPLETE", _result_rows(), "")
		return
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
	if not Game.circuit_run.is_empty():
		_end_circuit_race(title, rows)
		return
	hud.show_results(title, rows, extra)


## A tournament race over: its results beside the circuit's standings, then on to the next
## race (the car mended first, if you'll pay), or at the circuit's end its trophy, prize or
## car and what it opens.
func _end_circuit_race(title: String, rows: Array) -> void:
	var cars_in_order: Array = racers.map(func(r): return r.car)
	cars_in_order.sort_custom(func(a: Car, b: Car) -> bool: return position_of(a) < position_of(b))
	var order := cars_in_order.map(func(c: Car) -> Variant: return c.get_meta("circuit_key", "you"))
	var run := Game.circuit_run
	var career := Game.career_data()
	var c: Dictionary = career.circuits[run.circuit]
	var tour := {}
	for t in career.tournaments:
		if t.id == run.tournament:
			tour = t
	var race_no: int = run.race + 1
	# The car keeps its damage until it's paid for.
	if Game.damage:
		Game.set_garage_damage(Game.car_index, player.damage)
	var times := {}
	for r in racers:
		times[r.car.get_meta("circuit_key", "you")] = _finish_time(r)
	var outcome := Game.circuit_race_done(order, times)
	Game.save_career()
	var standings := []
	for s: Dictionary in outcome.standings:
		standings.append({"name": Game.circuit_name(s.key), "you": s.key is String, "race": s.race, "gained": s.gained,
			"color": UiKit.ACCENT if s.key is String else Rivals.get_driver(Game.circuit_driver(s.key)).color,
			"points": s.points, "out": s.out, "total": Hud.fmt_time(s.total) if s.total >= 0.0 else ""})
	var circuit := {"standings": standings,
		"caption": "%s  ·  %s  ·  RACE %d OF %d" % [Game.track_name(Game.track_id).to_upper(), str(tour.get("name", "")).to_upper()
			+ (" · " + str(c.name).to_upper() if c.has("name") else " %d" % (tour.get("circuits", []).find(run.circuit) + 1)),
			race_no, c.races.size()],
		"standings_caption": "FINAL STANDINGS" if outcome.done else "STANDINGS AFTER RACE %d OF %d" % [race_no, c.races.size()]}
	if outcome.done:
		if run.you_out:
			title = "KNOCKED OUT"
		elif outcome.place == 1:
			title = "CIRCUIT WON"
		else:
			title = "%s OVERALL" % Hud.ordinal(outcome.place).to_upper()
		var lines := []
		if outcome.race_prize > 0:
			lines.append("$%s for the race" % TournamentPanel.money(outcome.race_prize))
		if outcome.award >= 0:
			lines.append("%s is yours" % Game.cars[outcome.award].name)
		if outcome.prize > 0:
			lines.append("$%s prize" % TournamentPanel.money(outcome.prize))
		if outcome.tournament != "":
			lines.append("%s won" % outcome.tournament)
		if not outcome.opened.is_empty():
			lines.append("Opens " + " & ".join(outcome.opened))
		lines.append("Money $%s" % TournamentPanel.money(Game.career_money))
		circuit.trophy = outcome.trophy
		circuit.tour = Game.trophy_design(run.tournament)
		circuit.lines = lines
		var extra: String = outcome.message if outcome.award < 0 else ""
		hud.show_results(title, rows, extra, [
			["Tournaments", func() -> void:
				Game.circuit_run = {}
				Game.menu_screen = "tournaments"
				hud.quit()],
			["Main menu", func() -> void:
				Game.circuit_run = {}
				hud.quit()]], circuit)
		return
	var msg: String = outcome.message
	if outcome.race_prize > 0:
		msg = ("%s   ·   " % msg if msg != "" else "") + "$%s won" % TournamentPanel.money(outcome.race_prize)
	hud.show_results(title, rows, _circuit_extra(msg), _circuit_actions(c), circuit)


## A racer's time for the race: its own if it's finished, else what it would take at the
## pace it's gone so far (a rally adds the times up).
func _finish_time(r: Dictionary) -> float:
	if r.finished:
		return r.time
	var covered: float = r.total
	var whole: float = path.length * Game.race_laps()
	if not path.closed:
		covered -= path.cumulative[path.start_node]
		whole = path.cumulative[path.finish_node] - path.cumulative[path.start_node]
	return race_time * whole / maxf(covered, whole * 0.05)


## Between a circuit's races: what's happened, the car's damage and what mending it costs.
func _circuit_extra(message := "") -> String:
	var parts := PackedStringArray()
	if message != "":
		parts.append(message)
	var cost := Game.repair_cost(Game.car_index)
	if cost > 0:
		parts.append("Car damage %d%%  ·  repair $%s" % [roundi(Game.garage_damage(Game.car_index) * 100.0), TournamentPanel.money(cost)])
	parts.append("Money $%s" % TournamentPanel.money(Game.career_money))
	return "   ·   ".join(parts)


## Between a circuit's races: on to the next, mend the car (while it's damaged), or give up.
func _circuit_actions(c: Dictionary) -> Array:
	var run := Game.circuit_run
	var actions := [["Race %d of %d" % [run.race + 1, c.races.size()], func() -> void:
		Game.next_circuit_race()
		get_tree().paused = false
		get_tree().reload_current_scene()]]
	var cost := Game.repair_cost(Game.car_index)
	if cost > 0:
		actions.append(["Repair  $%s" % TournamentPanel.money(cost), func() -> void:
			var err := Game.repair_car(Game.car_index)
			hud.set_result_extra(_circuit_extra(err))
			if err == "":
				hud.set_result_actions(_circuit_actions(c))])
	actions.append(["Quit circuit", func() -> void:
		Game.circuit_run = {}
		hud.quit()])
	return actions


## The leaderboard in its current order; also kept in Game.last_results.
func _result_rows() -> Array:
	var rows := []
	for r in racers:
		rows.append({"name": r.name, "you": r.car == player and not spectating(), "color": r.get("color", UiKit.ACCENT),
			"time": Hud.fmt_time(r.time) if r.finished else "--:--.--",
			"best": Hud.fmt_time(r.best) if r.best < INF else "--",
			"t": r.time if r.finished else INF})
	Game.last_results = rows
	return rows


func spectating() -> bool:
	return Game.mode == Game.Mode.SPECTATE


## Spectate mode: moves the camera (and the HUD and reflections with it) to the
## racer `step` places behind (+1) or ahead (-1) of the one being watched.
## Spectating: cuts away from a car that's finished to the best-placed one still racing. The
## results only come up once the whole field is home; until then the tower shows who's finished.
func _update_spectate(dt: float) -> void:
	if _cut_t >= 0.0:
		_cut_t -= dt
		if _cut_t < 0.0:
			for r in racers:
				if not r.finished:
					_watch(r.car)
					break


func _watch_step(step: int) -> void:
	var i := posmod(position_of(player) - 1 + step, racers.size())
	_watch(racers[i].car)


func _watch(car: Car) -> void:
	if car == player or not is_instance_valid(car):
		return
	_cut_t = -1.0
	var old := player
	old.is_player = false
	old.set_headlight_beam(Game.night and Game.quality != Game.Quality.LOW)
	player = car
	player.is_player = true
	player.set_headlight_beam(true, true)
	# Each racer has its own CarAudio: the watched one's switches to its full engine (is_player).
	cam.target = player
	_reflections.retarget(player)
	hud.player = player
	hud.flash("Watching " + player.display_name, 1.5)


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
		r.held_t = maxf(r.held_t - dt, 0.0)
	for cop in cops.duplicate():
		var ai := _controller(cop)
		if ai.chasing:
			if not is_instance_valid(ai.target) or cop.global_position.distance_to(ai.target.global_position) > ESCAPE_DISTANCE:
				var was_player := ai.target == player
				_stop_chase(cop)
				if was_player and _chasers(player).is_empty():
					speech.say(_officer(cop), [32, 33, 34, 35], RADIO_DB)
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
		if is_instance_valid(_heli):
			_heli.leave()
		_heli = null
	else:
		pursuit_time += dt
		heat = mini(1 + int(pursuit_time / HEAT_STEP), 3)
		# Backup units: one per heat level above the first.
		_backup_t -= dt
		var backup := cops.filter(func(c): return c.has_meta("backup")).size()
		if backup < heat - 1 and _backup_t <= 0.0:
			_spawn_backup()
			_backup_t = 8.0
		_block_t -= dt
		if heat >= 2 and _rb.is_empty() and _block_t <= 0.0:
			_spawn_roadblock(heat >= 3)
		if heat >= 2 and _heli == null:
			_call_helicopter()

	# Each chase's cruisers keep their places round their car, closer and rougher as the heat rises.
	for r in racers:
		var cs := _chasers(r.car)
		if not cs.is_empty():
			_assign_slots(r.car, cs)
			for cop in cs:
				_controller(cop).aggression = clampi(heat - 1, 0, 2) if r.car == player else 0

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
		if cop.global_position.distance_to(c.global_position) < COP_SIGHT and _in_sight(cop, c):
			if c == player:
				return c
			found = c if found == null else found
	return found


## Whether `cop` can see `c`: nothing solid (a building, the brow of a hill) between them.
func _in_sight(cop: Car, c: Car) -> bool:
	var up := Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(cop.global_position + up, c.global_position + up,
		1 | Nfs3TrackBuilder.SCENERY_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The chasers' places round `target` (AIHigh_BasicPerp::CheckChaserPosition): a newcomer
## joins at the back, and any cruiser more than 12 m further up the road than the one a place
## before it swaps with it, so the one furthest on takes the block in front.
func _assign_slots(target: Car, cs: Array[Car]) -> void:
	cs.sort_custom(func(a: Car, b: Car) -> bool: return _controller(a).chase_slot < _controller(b).chase_slot)
	var fwd := target.linear_velocity.normalized() if target.linear_velocity.length() > 3.0 else target.forward_dir()
	for i in range(1, cs.size()):
		var k := i
		while k > 0 and (cs[k].global_position - cs[k - 1].global_position).dot(fwd) > 12.0:
			var tmp := cs[k]
			cs[k] = cs[k - 1]
			cs[k - 1] = tmp
			k -= 1
	for i in cs.size():
		_controller(cs[i]).chase_slot = i


## A racer that rams a cruiser not already on a chase has one on its hands.
func _on_cop_hit(other: Node, cop: Car) -> void:
	if state != State.RACING or not other is Car or not cops.has(cop) or _controller(cop).chasing:
		return
	var c := other as Car
	var r: Dictionary = {}
	for rr in racers:
		if rr.car == c:
			r = rr
	if r.is_empty() or r.finished or r.cool > 0.0 or (c.linear_velocity - cop.linear_velocity).length() < 6.0:
		return
	_start_chase(cop, c)


func _chasers(target: Car) -> Array[Car]:
	var out: Array[Car] = []
	for cop in cops:
		var ai := _controller(cop)
		if ai.chasing and ai.target == target:
			out.append(cop)
	return out


func _start_chase(cop: Car, target: Car) -> void:
	var ai := _controller(cop)
	# In at the back; _assign_slots moves it up as it gets further up the road than the others.
	ai.chase_slot = 99
	if target == player and _chasers(target).is_empty():
		speech.say("copspch", range(10))
		_radio_call(cop, _speed_call())
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
	var pr := player_racer()
	pr.tickets = tickets
	pr.held_t = PLAYER_HOLD
	var arresting: Car = _chasers(player)[0] if not _chasers(player).is_empty() else null
	_send_officer(_chasers(player), player)
	for cop in _chasers(player):
		_stop_chase(cop)
	pr.cool = 10.0
	if Game.mode == Game.Mode.HOT_PURSUIT and tickets >= MAX_TICKETS:
		speech.say("copspch", [32, 33, 34])
		speech.say(_officer(arresting), [44, 45, 46, 47], RADIO_DB)
		_end_race(true)
		return
	var fine: int = TICKET_FINES[mini(tickets - 1, TICKET_FINES.size() - 1)]
	fines += fine
	speech.say("copspch", 19 if Game.mode == Game.Mode.HOT_PURSUIT and tickets == MAX_TICKETS - 1 else [16, 17, 18])


## A rival pulled over: it sits out a few seconds while the cop writes the ticket.
func _bust_rival(r: Dictionary) -> void:
	_send_officer(_chasers(r.car), r.car)
	for cop in _chasers(r.car):
		_stop_chase(cop)
	r.cool = RIVAL_HOLD + 8.0
	r.tickets += 1
	r.held_t = RIVAL_HOLD
	var ai := _controller(r.car)
	if ai == null:
		return
	ai.enabled = false
	get_tree().create_timer(RIVAL_HOLD, false, true).timeout.connect(func() -> void:
		if is_instance_valid(ai):
			ai.enabled = true)


## The nearest of `chasers` that carries an officer (High Stakes' cruisers) sends him to
## `busted`'s window; the cruiser waits for him to get back in.
func _send_officer(chasers: Array[Car], busted: Car) -> void:
	# NFS3's cruisers carry no officer: High Stakes' generic one (GameArt cop0) gets out of those.
	var generic := Game.hs_prop("cop0")
	var cop: Car = null
	for c in chasers:
		if (c.officer_mesh or generic) and (cop == null or c.global_position.distance_to(busted.global_position)
				< cop.global_position.distance_to(busted.global_position)):
			cop = c
	if cop == null:
		return
	var o := Officer.new()
	add_child(o)
	o.setup(cop.officer_mesh if cop.officer_mesh else generic, cop, busted)
	var ai := _controller(cop)
	if ai:
		ai.enabled = false
		o.done.connect(func() -> void:
			if is_instance_valid(ai):
				ai.enabled = true)


## High Stakes' helicopter joins the chase, flying in from behind.
func _call_helicopter() -> void:
	if Game.hs_helicopter == "":
		return
	if _heli_data.is_empty():
		_heli_data = Fce4.load_helicopter(Game.hs_helicopter)
		if _heli_data.is_empty():
			Game.hs_helicopter = ""
			return
	_heli = Helicopter.new()
	add_child(_heli)
	var at := player.global_transform * Vector3(0, 60.0, -180.0)
	_heli.setup(_heli_data, player, at, Game.night)
	# On the radio: it calls in, the dispatcher answers, it's on its way; then it finds him.
	var air := randi() % 3   # Air One, Air 3, Rotor 1
	speech.say("helicop", air, RADIO_DB)
	speech.say(_dispatch(), 44 + air, RADIO_DB)
	speech.say("helicop", [34, 35, 36, 37], RADIO_DB)
	get_tree().create_timer(8.0, false).timeout.connect(func() -> void:
		if is_instance_valid(_heli) and state == State.RACING:
			speech.say("helicop", [69, 70, 73, 76], RADIO_DB)
			var mph := absf(player.speed) * 2.237
			if mph > 100.0:
				speech.say("helicop", 96 + mini(int((mph - 100.0) / 20.0), 9), RADIO_DB))


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
## side to squeeze through. At top heat a spike strip lies across the gap. Once the player is
## through (or has stopped short of it), they pull out and join the chase.
func _spawn_roadblock(with_spikes: bool) -> void:
	var pr := player_racer()
	var n := path.idx(pr.node + 70)
	var w := minf(path.left_width[n], path.right_width[n])
	var gap_side := -1.0 if randf() < 0.5 else 1.0
	for k in 2:
		var cop := _make_cop(k)
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
	_rb = {"node": n, "side": gap_side, "approach": signf((player.global_position - path.points[n]).dot(path.forward(n))), "w": w, "shift": 0.0, "vel": 0.0,
		"gap_edge": reach_gap, "far_edge": reach_far,
		"max": maxf(reach_gap - 0.05 * w - RB_HALF, 0.0), "min": minf(-(reach_far - 0.55 * w - RB_HALF), 0.0)}
	# Racers head for the gap: just past the inner cruiser (parked sideways, ~2.4 m either side of
	# its centre), where there's road even when the walls are far apart. They also steer around
	# the cruisers like any other car.
	var gap_lane := (0.05 * w + 3.9) * gap_side
	if Game.is_hs_track(Game.track_id):
		_rb_props = RoadblockProps.build(self, path, n, gap_side, w, reach_gap, reach_far, Game.night)
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
		spikes.append(strip)
	# The officer asks, the dispatcher clears it, the officer reports it done.
	var off := _officer(cops[0] if not cops.is_empty() else null)
	speech.say(off, [55, 56] if with_spikes else [51, 52], RADIO_DB)
	speech.say(_dispatch(), [52, 53] if with_spikes else [58, 59], RADIO_DB)
	speech.say(off, [57, 58, 59] if with_spikes else [53, 54], RADIO_DB)


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
	# The player through it (on the far side from where it came), or pulled up in front of it.
	var p_along := (player.global_position - origin).dot(fwd)
	if (p_along * _rb.approach < 0.0 and absf(p_along) > 8.0) or (absf(p_along) < 25.0 and player.linear_velocity.length() < 4.0):
		_release_roadblock()
		return
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


## The roadblock's cruisers pull out and join the chase (AIHigh_Cop's blockade release);
## the cones, flares and spikes stay until the player is well past.
func _release_roadblock() -> void:
	for cop in roadblock:
		cop.resume(Vector3.ZERO)
		cop.set_meta("backup", true)   # sent home out of sight once the chase is over
		var ai := _controller(cop)
		ai.enabled = true
		ai.others = racers.map(func(r): return r.car) + traffic_cars + cops + roadblock
		cops.append(cop)
		if heat > 0:
			_start_chase(cop, player)
	roadblock.clear()
	# Nothing left across the road to thread.
	_gap = Vector3.INF
	for cop in cops:
		_controller(cop).gap = _gap


## Takes the roadblock down once it's well behind the player.
func _clear_roadblock() -> void:
	if _rb.is_empty():
		return
	var rb_node: int = _rb.node
	var pr := player_racer()
	# Signed distance past the roadblock, wrapped so a block just after the start line works.
	var behind := fposmod(path.cumulative[pr.node] - path.cumulative[rb_node] + path.length * 0.5, path.length) - path.length * 0.5
	# A chase that's ended short of it (the player turned back, or got busted) takes it down too.
	if behind > 150.0 or (heat == 0 and absf(behind) > 300.0):
		for c in roadblock:
			c.queue_free()
		for sp in spikes:
			sp.queue_free()
		for p in _rb_props:
			if is_instance_valid(p):
				p.queue_free()
		roadblock.clear()
		spikes.clear()
		_rb_props.clear()
		_rb = {}
		_gap = Vector3.INF
		for cop in cops:
			_controller(cop).gap = _gap
		# The next one only after another stretch of chase.
		_block_t = 20.0


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
		# (A side road can run in a valley well below the lap: not while on or near one.)
		var fell: bool = c.global_position.y < path.points[n].y - 25.0 \
			and not path.on_side_road(c.global_position, path.lost_margin, 25.0)
		# Beyond the invisible wall (knocked over or through it): nothing to drive on out there.
		# A shortcut can run further out than the virtual road's walls, so only off the
		# drivable surface. In free roam the player may wander off: the reset key brings them back.
		# Heading down a bank to the water isn't lost: the water deals with it.
		# Nor is a car on a side road the walls leave open (a shortcut), or off one by no more
		# than it may stray off the lap.
		var lost: bool = off > maxf(path.wall_width(n, -1.0), path.wall_width(n, 1.0)) + path.lost_margin and not _on_road(c) \
			and not (c == player and Game.mode == Game.Mode.FREE_ROAM) and not _near_water(c) \
			and not path.on_side_road(c.global_position, path.lost_margin, 25.0)
		# In a stream or a lake: it wades (Car.water_depth), then gets fished out.
		c.water_depth = _water_depth(c)
		var drowned := false
		if c.water_depth > DROWN_DEPTH:
			_water_t[c] = _water_t.get(c, 0.0) + 0.1
			drowned = _water_t[c] > DROWN_TIME
		else:
			_water_t.erase(c)
		# AI wedged against scenery that backing up hasn't cleared. A cop out of the player's
		# sight gets put back on the road sooner: nobody sees it jump.
		var give_up := 3.0 if c.is_cop and c.global_position.distance_to(player.global_position) > 150.0 else 7.0
		var stranded: bool = ai != null and ai.stranded_t > give_up
		if c.is_stuck_upside_down() or fell or lost or stranded or drowned:
			_water_t.erase(c)
			_respawn(c, stranded)


## How far (m) the car is under the surface of a stream or a lake (the track's "Water"
## body), 0 when it isn't.
func _water_depth(c: Car) -> float:
	var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3.UP * 20.0, c.global_position,
		Nfs3TrackBuilder.WATER_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else hit.position.y - c.global_position.y


## Whether there is a stream or a lake within reach of the road's opened edge (see
## Nfs3TrackBuilder.WATER_REACH), with some to spare for the drop down the bank.
func _near_water(c: Car) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = Nfs3TrackBuilder.WATER_REACH + 15.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), c.global_position)
	q.collision_mask = Nfs3TrackBuilder.WATER_LAYER
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Whether the car is over the track's drivable surface (the "Road" body, not the terrain).
func _on_road(c: Car) -> bool:
	var from := c.global_position + Vector3.UP
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1, [c.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider.name == "Road"


func _respawn(c: Car, past_blockage := false) -> void:
	var ai := _controller(c)
	# Search near the node the car was last tracked at: a global search can pick a stretch of
	# road on another level (bridges, overpasses) and skip part of the lap.
	var hint := ai.node if ai else -1
	for r in racers:
		if r.car == c:
			hint = r.node
	var n := path.closest(c.global_position, hint)
	# Off the lap on a side road (a shortcut): back on that road, not the lap's nearest stretch.
	if ai == null and not path.side_roads.is_empty() \
			and absf(path.lateral(c.global_position, n)) > maxf(path.wall_width(n, -1.0), path.wall_width(n, 1.0)):
		var side := path.side_road_spot(c.global_position, c.forward_dir())
		if side.basis != Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO) and not _car_near(c, side.origin, 5.0) and not _blocked(c, side):
			c.reset_to(side, 0.3)
			return
	var dir := -1 if ai and ai.reverse_dir else 1
	# Wedged against something: put it down beyond it, or it drives straight back into it.
	if past_blockage:
		n = path.ahead(n, dir, 12.0)
	# In the lane it was in (the centre line can have a median, lamp posts or pillars on it),
	# but not far out: an overtaking line can be over a verge or a drop.
	var lane := clampf(ai.lane if ai else path.lateral(c.global_position, n), -3.5, 3.5)
	if absf(lane) < 1.5:
		lane = 2.5 * dir if lane == 0.0 else signf(lane) * 2.5
	# Put it down clear of other cars (a parked roadblock, a pile-up) and of solid scenery
	# standing on the road, trying other lanes and moving up the road if need be. The middle
	# of the road is the last resort.
	var spot := n
	var off := _ground_offset(n, lane)
	var found := false
	var m := n
	for k in 12:
		var clear := path.free_offset(m, path.ahead(m, dir, 6.0), dir, lane, lane,
			-minf(path.left_width[m], 3.5), minf(path.right_width[m], 3.5))
		for l: float in [clear, lane, -lane, 0.0]:
			var o := _ground_offset(m, l)
			var pos := path.transform_at(m, o, 0.0)
			if not _car_near(c, pos.origin, 5.0) and not _blocked(c, pos):
				spot = m
				off = o
				found = true
				break
		if found:
			break
		m = path.ahead(m, dir, 4.0)
	n = spot
	if ai:
		ai.stranded_t = 0.0
		ai.lane = off
	var xf := path.transform_at(n, off, 0.0)
	if dir < 0:
		xf = xf.rotated_local(Vector3.UP, PI)
	c.reset_to(xf, 0.3)


## Whether a car put down at `xf` (a point on the road surface) would be inside something
## solid: a tree, pillar or building standing on the road, or another car's body (a bus or a
## truck is far longer than _car_near's radius). The box starts clear of the road surface
## itself so it only catches things sticking up out of it.
func _blocked(me: Car, xf: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.6, 5.5)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = xf.translated_local(Vector3.UP * 1.3)
	q.collision_mask = 1 | 2 | Nfs3TrackBuilder.SCENERY_LAYER
	q.exclude = [me.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		var body := hit.collider as Node
		if body and body.name != "Road":
			return true
	return false


## Whether another car is at `pos`, or will be within the next second or so (traffic
## bearing down on the spot would plough straight into the car put down there).
func _car_near(me: Car, pos: Vector3, radius: float) -> bool:
	for o in racers.map(func(r): return r.car) + traffic_cars + cops + roadblock:
		if o == me or not is_instance_valid(o):
			continue
		var p: Vector3 = o.global_position
		var ahead: Vector3 = p + o.linear_velocity * 1.5
		if Geometry3D.get_closest_point_to_segment(pos, p, ahead).distance_to(pos) < radius:
			return true
	return false

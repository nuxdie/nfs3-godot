extends Node
## Scripted play-through: starts a race, drives the player's car through the input
## actions, saves screenshots to shots/ and prints telemetry, then quits.
## --ram (procedural track): instead drives the car into a few of the track's props that
## knock over and a guardrail, one every few seconds, with a screenshot of each.

var t := 0.0
var shots := [3.0, 8.0, 14.0, 22.0, 32.0]
var duration := 34.0
var race: Node


var _ai: AIController

## --perf: frame times of the whole run after the start (ms), printed as a summary at the end
## and every 5 s, with where the time went (script process, physics, render CPU and GPU).
var _perf := false
var _frames := PackedFloat32Array()
var _win := PackedFloat32Array()
var _cpu_ms := 0.0
var _gpu_ms := 0.0
var _proc_ms := 0.0
var _phys_ms := 0.0
var _perf_t := 0.0
var _cb_us := 0          # physics callbacks (scripts + internal), first to last node
var _heat := 0           # --heat=N: every cop on the player from the start, at heat N
var _heated := false
var _surrender := -1.0     # --surrender=S: S s into a chase after the player, pull over and wait to be busted
var _chased_t := 0.0
var _dented := false
var _perf_win := 5.0     # --perfwin=S: seconds per perf line
var _scale := 0.0        # --scale=: overrides the 3D resolution scale
var _pcb_us := 0         # process callbacks, likewise
var _proc_first := 0
# Between the markers: 1 = after the last physics callback, 2 = after the last process one.
var _ev := 0
var _ev_t := 0
var _gap_render := 0     # process end -> next physics/process start: drawing, swap, input, body sync
var _gap_step := 0       # between two physics ticks: the physics step and the next body sync
var _gap_tail := 0       # last physics callback -> process start: the step, deferred calls
var _ticks := 0
var _subvps: Array[Node] = []
var _tick_first := 0
## --stoplog: every car that goes from over 50 km/h to a standstill within 1.5 s is printed
## with its virtual road node and the solid things within a few metres of it.
var _speeds := {}   # Car -> its last 90 physics ticks' speeds
var _stopped := {}  # Car -> race time of its last logged stop
## --aistats: the racers' hits (over 4 m/s closing), by what they hit, printed at the end.
var _hits := {}
var _look := NAN          # --look=DEG: the head held turned this far (+ left), e.g. to a side mirror
var _hit_armed := false


func _ready() -> void:
	# Runs after the ghost AI (-20) has written its decisions to the car and before the
	# PlayerController (-10) reads the input actions back.
	process_physics_priority = -15
	var args := OS.get_cmdline_user_args()
	# Positional after --autotest: track, mode, car. Flags (--night, --duration=N, ...) go anywhere.
	var pos := Array(args.slice(args.find("--autotest") + 1)).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if pos.size() > 0:
		Game.track_id = pos[0]
	if pos.size() > 1:
		Game.mode = int(pos[1])
	if pos.size() > 2:
		Game.car_index = int(pos[2]) if pos[2].is_valid_int() else maxi(Game.cars.find_custom(func(c: Dictionary) -> bool: return c.id == pos[2]), 0)
	Game.night = "--night" in args
	for arg in args:
		if arg.begins_with("--duration="):
			duration = float(arg.trim_prefix("--duration="))
		# --camera=N starts in that camera mode (ChaseCamera.MODES; 3 is the in-car view).
		elif arg.begins_with("--camera="):
			Game.camera_mode = clampi(int(arg.trim_prefix("--camera=")), 0, ChaseCamera.MODES.size() - 1)
		elif arg.begins_with("--look="):
			_look = deg_to_rad(float(arg.trim_prefix("--look=")))
	Game.weather = "--weather" in args
	# The start fly-by only with --intro (it would shift every run's timings).
	Game.intro_flyby = "--intro" in args
	# --classic-hud: High Stakes' dials.
	# (--classic-hud-bottom: the same, bottom centre.)
	Game.hud_style = 2 if "--classic-hud-bottom" in args else int("--classic-hud" in args)
	# --classic: the plain NFS3 handling, without body sway and progressive grip (F6 in game).
	if "--no-traffic" in args:
		Game.traffic = false
	if "--no-damage" in args:
		Game.damage = false
	Car.body_sway = not "--classic" in args
	# --hide=map,standings,...: those HUD parts off (Game.HUD_WIDGETS); --no-hud: all of it.
	for arg in args:
		if arg.begins_with("--hide="):
			Game.hud_hidden.assign(arg.trim_prefix("--hide=").split(",", false))
	Game.hud_on = not "--no-hud" in args
	Car.progressive_grip = Car.body_sway
	Game.laps = 2
	Game.opponents = 3
	_perf = "--perf" in args
	for arg in args:
		if arg.begins_with("--heat="):
			_heat = int(arg.trim_prefix("--heat="))
		# --layout=N: the track that way round (Game.LAYOUTS: 1 reverse, 2 mirror, 3 both).
		if arg.begins_with("--layout="):
			Game.layout = int(arg.trim_prefix("--layout="))
		# --seed=N: the same rivals, skills and traffic every run (to compare two).
		if arg.begins_with("--seed="):
			seed(int(arg.trim_prefix("--seed=")))
		# --upgrade=N races the car at High Stakes upgrade level N.
		if arg.begins_with("--upgrade="):
			Game.set_upgrade(Game.car_index, int(arg.trim_prefix("--upgrade=")))
		# --shots=S,S,... takes the screenshots at those times instead.
		if arg.begins_with("--shots="):
			shots = Array(arg.trim_prefix("--shots=").split(",")).map(func(v: String) -> float: return v.to_float())
		if arg.begins_with("--surrender="):
			_surrender = float(arg.trim_prefix("--surrender="))
	for arg in args:
		if arg.begins_with("--perfwin="):
			_perf_win = float(arg.trim_prefix("--perfwin="))
		if arg.begins_with("--scale="):
			_scale = float(arg.trim_prefix("--scale="))
	if _perf:
		# Bracket every physics callback: first and last in physics priority order.
		var first := _PerfMark.new()
		first.process_physics_priority = -100000
		first.cb = func() -> void:
			_tick_first = Time.get_ticks_usec()
			_ticks += 1
			if _ev == 2:
				_gap_render += _tick_first - _ev_t
			elif _ev == 1:
				_gap_step += _tick_first - _ev_t
		first.process_priority = -100000
		first.pcb = func() -> void:
			_proc_first = Time.get_ticks_usec()
			if _ev == 2:
				_gap_render += _proc_first - _ev_t
			elif _ev == 1:
				_gap_tail += _proc_first - _ev_t
		var last := _PerfMark.new()
		last.process_physics_priority = 100000
		last.cb = func() -> void:
			_ev_t = Time.get_ticks_usec()
			_ev = 1
			_cb_us += _ev_t - _tick_first
		last.process_priority = 100000
		last.pcb = func() -> void:
			_ev_t = Time.get_ticks_usec()
			_ev = 2
			_pcb_us += _ev_t - _proc_first
		add_child(first)
		add_child(last)
	for arg in args:
		if arg.begins_with("--opponents="):
			Game.opponents = int(arg.trim_prefix("--opponents="))
		if arg.begins_with("--quality="):
			Game.quality = int(arg.trim_prefix("--quality=")) as Game.Quality
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	# --series=nfs3|hs|pu: that game's tournaments (on a scratch career file), for the menu's
	# tournaments or --circuit.
	for arg in args:
		if arg.begins_with("--series="):
			Game.career_path = "user://career_autotest.cfg"
			Game._career_loaded = false
			Game.career_data()
			Game.set_career_series(arg.trim_prefix("--series="))
	if Game.track_id == "menu":
		# Just photograph the front end.
		if "--settings" in args:
			get_tree().current_scene.open_settings.call_deferred()
		# --hud-settings: the settings' HUD page.
		if "--hud-settings" in args:
			get_tree().current_scene.open_settings.call_deferred(SettingsPanel.PAGE_HUD)
		# --tournaments: High Stakes' tournaments panel open.
		if "--tournaments" in args:
			get_tree().current_scene._open_tournaments.call_deferred()
		# --cars: the car browser open (on the car given as the third argument).
		if "--cars" in args:
			get_tree().current_scene._open_cars.call_deferred()
		# --screen=home|track|car|options|tournaments|garage: that screen of the front end.
		for arg in args:
			if arg.begins_with("--screen="):
				get_tree().current_scene.show_screen.call_deferred(arg.trim_prefix("--screen="))
		for k in 60:
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("shots/menu.png")
		get_tree().quit()
		return
	# --circuit=N: circuit N (its first race) of High Stakes' (or --series'), on a scratch career file.
	for arg in args:
		if arg.begins_with("--circuit="):
			Game.career_path = "user://career_autotest.cfg"
			var career := Game.career_data()
			Game.career_money = 10000000
			Game.career_garage[Game.cars[Game.car_index].id] = {"upgrade": 0, "damage": 0.0}
			var cid := int(arg.trim_prefix("--circuit="))
			for tt in career.tournaments:
				if cid in tt.circuits:
					print("circuit %d: %s" % [cid, Game.start_circuit(tt, cid)])
		# --laps=N: shorter races (after the circuit has set its own).
		if arg.begins_with("--laps="):
			Game.laps = int(arg.trim_prefix("--laps="))
	get_tree().change_scene_to_file.call_deferred("res://scenes/race.tscn")


func _process(dt: float) -> void:
	if not is_nan(_look) and race and race.get("cam"):
		race.cam._yaw = _look
		race.cam._idle = 0.0
	if _scale > 0.0:
		get_viewport().scaling_3d_scale = _scale
	if not _perf:
		return
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	race = get_tree().current_scene
	# Only the race proper counts: from the countdown on, after loading's long frames.
	if race == null or not race.has_method("player_racer") or race.player == null or t < 2.0:
		return
	var ms := dt * 1000.0
	_frames.append(ms)
	_win.append(ms)
	_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	# SubViewports (the mirror, reflections) render on the GPU too.
	if _subvps.is_empty() or Engine.get_process_frames() % 60 == 0:
		_subvps = get_tree().root.find_children("*", "SubViewport", true, false)
	for v: SubViewport in _subvps:
		if is_instance_valid(v):
			RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
			_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
	_proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf_t += dt
	if _perf_t >= _perf_win:
		var n := float(_win.size())
		# (proc/phys monitors are the worst frame of each second: spikes, not averages.)
		print("perf t=%.0f state=%d %s | scale %.2f | phys cb %.1f/tick x%.2f, proc cb %.1f, draw+swap %.1f, step %.1f, tail %.1f, rcpu %.1f, gpu %.1f ms/f | spikes proc %.0f phys %.0f | draws %d prims %dk objs %d" % [
			t, race.state, _perf_line(_win), get_viewport().scaling_3d_scale, _cb_us / 1000.0 / maxf(_ticks, 1), _ticks / n, _pcb_us / 1000.0 / n,
			_gap_render / 1000.0 / n, _gap_step / 1000.0 / n, _gap_tail / 1000.0 / n, _cpu_ms / n, _gpu_ms / n, _proc_ms / n, _phys_ms / n,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		_win.clear()
		_cpu_ms = 0.0
		_gpu_ms = 0.0
		_proc_ms = 0.0
		_phys_ms = 0.0
		_perf_t = 0.0
		_cb_us = 0
		_pcb_us = 0
		_gap_render = 0
		_gap_step = 0
		_gap_tail = 0
		_ticks = 0


func _perf_line(f: PackedFloat32Array) -> String:
	if f.is_empty():
		return "no frames"
	var s := f.duplicate()
	s.sort()
	var total := 0.0
	var slow := 0
	for v in f:
		total += v
		if v > 18.0:
			slow += 1
	return "fps %.1f p50 %.1f p95 %.1f p99 %.1f max %.1f ms, %.1f%% >18ms" % [
		1000.0 * f.size() / total, s[s.size() / 2], s[int(s.size() * 0.95)], s[int(s.size() * 0.99)],
		s[s.size() - 1], 100.0 * slow / f.size()]


func _exit_tree() -> void:
	if _perf:
		print("PERF TOTAL %s over %d frames" % [_perf_line(_frames), _frames.size()])


func _physics_process(dt: float) -> void:
	race = get_tree().current_scene
	if race == null or not race.has_method("player_racer") or race.player == null:
		return
	t += dt
	var p: Car = race.player
	var r: Dictionary = race.player_racer()
	if "--stoplog" in OS.get_cmdline_user_args() and race.state == 2:
		_log_stops()
	if "--dentbench" in OS.get_cmdline_user_args() and race.state == 2 and not _dented:
		_dented = true
		var dmg: CarDamage = null
		for ch in p.get_children():
			if ch is CarDamage:
				dmg = ch
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var t0 := Time.get_ticks_usec()
		for k in 30:
			var at := p.global_transform * Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-2, 2))
			dmg.hit(at, (p.global_position - at).normalized(), 15.0)
			# (Dents wait for their frame: work through them here.)
			CarDamage._queue_frame = -1
			dmg._process(0.0)
		print("dentbench: %.2f ms a hit" % ((Time.get_ticks_usec() - t0) / 1000.0 / 30.0))
		get_tree().quit()
	if "--ghosttest" in OS.get_cmdline_user_args():
		_ghost_test()
	if "--traffictest" in OS.get_cmdline_user_args():
		_traffic_test()
	if _heat > 0 and race.state == 2 and not _heated:
		_heat_up(p)
	# --no-ai-speeds: without the speed tables only.
	if "--no-ai-speeds" in OS.get_cmdline_user_args() and race.path and not race.path.ai_speeds[0].is_empty():
		race.path.ai_speeds = [PackedFloat32Array(), PackedFloat32Array()]
	# --no-ai-tables: the AI without the original game's speed tables and racing line (to compare).
	if "--no-ai-tables" in OS.get_cmdline_user_args() and race.path and not race.path.ai_speeds[0].is_empty():
		race.path.ai_speeds = [PackedFloat32Array(), PackedFloat32Array()]
		race.path.racing_line = [PackedFloat32Array(), PackedFloat32Array()]
	# --rbcam: the camera on the roadblock (its outer cruiser) once one is up.
	if "--rbcam" in OS.get_cmdline_user_args() and not race.roadblock.is_empty() and race.cam.target != race.roadblock[0]:
		race.cam.target = race.roadblock[0]
		race.cam.mode = 1
	if "--ram" in OS.get_cmdline_user_args() and race.state == 2:
		_ram(p, dt)
	elif "--resttest" in OS.get_cmdline_user_args() and race.state == 2:
		_rest_test(p, dt)
	elif race.spectating():
		# Nothing to drive: flick through the field for a while instead.
		if race.state == 2 and t < 30.0 and int(t / 6.0) != int((t - dt) / 6.0):
			race._watch_step(1)
	elif _surrender >= 0.0 and race.heat > 0 and _chased_t >= _surrender:
		# Pulled over: brake to a stop, then sit on the handbrake (holding the brake reverses).
		for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
			Input.action_release(a)
		Input.action_press("brake" if p.speed > 1.0 else "handbrake")
		if _ai:
			_ai.enabled = false
	elif race.path and r.size() > 0:
		_drive(p)
	if race.heat > 0:
		_chased_t += dt
	if int(t * 2) != int((t - dt) * 2):
		print("t=%.1f state=%d kmh=%d gear=%d rpm=%d wheels=%d lap=%d node=%d pos=%d slip=%.2f" % [t, race.state, p.kmh(), p.gear, p.rpm, p.grounded_wheels, r.get("lap", -9), r.get("node", -1), race.position_of(p), p.slip])
		if race.spectating():
			var rs := []
			for rr: Dictionary in race.racers:
				rs.append("%s L%d%s %dkmh" % [rr.name.left(10), rr.lap, "F" if rr.finished else "", rr.car.kmh()])
			print("  field ", " | ".join(rs))
		if not race.cops.is_empty():
			var cs := []
			for c: Car in race.cops:
				var ai: AIController = race._controller(c)
				cs.append("%s%s%d@%dm/%dkmh" % ["B" if c.has_meta("backup") else "", "C" if ai.chasing else ("H" if ai.home >= 0 else "P"),
					ai.chase_slot, c.global_position.distance_to(p.global_position), c.kmh()])
			print("  cops heat=%d tickets=%d flat=%s roadblock=%d spikes=%d %s" % [race.heat, race.tickets, p.tyres_flat(), race.roadblock.size(), race.spikes.size(), " ".join(cs)])
	# Reading the frame back stalls the GPU for a tenth of a second: no pictures when timing.
	if _perf:
		shots.clear()
	if shots.size() > 0 and t >= shots[0]:
		# No framebuffer to read back in --headless runs; telemetry only.
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			# --tag=NAME keeps parallel runs (other tracks, weather) from overwriting each other.
			var tag := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--tag="):
					tag = arg.trim_prefix("--tag=") + "_"
			var path := "shots/auto_%s%02d.png" % [tag, int(shots[0])]
			img.save_png(path)
			print("shot ", path)
		shots.pop_front()
	if t >= 3.0 and t - dt < 3.0:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--hide="):
				for what in arg.trim_prefix("--hide=").split(","):
					_hide(race, what)
			if arg.begins_with("--kill="):
				for what in arg.trim_prefix("--kill=").split(","):
					_kill(what)
	if "--drawstats" in OS.get_cmdline_user_args() and int(t / 5.0) != int((t - dt) / 5.0):
		_draw_stats()
	if "--dumptree" in OS.get_cmdline_user_args() and t >= 6.0 and t - dt < 6.0:
		_dump_tree(race, 0)
		for c: Car in race.cops.slice(0, 1) + [p]:
			for g: GeometryInstance3D in c.find_children("*", "GeometryInstance3D", true, false):
				var surfs: int = g.mesh.get_surface_count() if g is MeshInstance3D and g.mesh else 1
				print("  car part %s %s vis=%s surfs=%d tris=%d mat=%s" % [g.get_parent().name, g.get_class(), g.is_visible_in_tree(), surfs,
					_tris(g.mesh) if g is MeshInstance3D and g.mesh else 0, g.material_override.get_class() if g.material_override else "-"])
	if "--aistats" in OS.get_cmdline_user_args() and race.state == 2 and not _hit_armed:
		_hit_armed = true
		for rr: Dictionary in race.racers:
			var rc: Car = rr.car
			rc.body_entered.connect(_count_hit.bind(rc))
	if t > duration:
		if _hit_armed:
			print("aistats ", _hits)
		# How far each racer got (m along the lap, laps included), and how often it was reset.
		var dist := []
		for rr: Dictionary in race.racers:
			# A point-to-point run's is from the start line.
			var got: float = float(rr.get("progress", 0.0)) - race.path.cumulative[race.path.start_node] if not race.path.closed \
				else rr.lap * race.path.length + float(rr.get("progress", 0.0))
			dist.append("%s %.0f m" % [rr.name.left(10), got])
		print("distance ", " | ".join(dist))
		get_tree().quit()


func _count_hit(other: Node, c: Car) -> void:
	var rel := c.linear_velocity
	var kind := "wall"
	if other is Car:
		rel -= (other as Car).linear_velocity
		if other.has_meta("traffic"):
			kind = "traffic_oncoming" if c.forward_dir().dot((other as Car).forward_dir()) < 0.0 else "traffic_same"
		else:
			kind = "cop" if (other as Car).is_cop else "racer"
	elif other.name == "Road" or other.name == "Terrain":
		return
	if rel.length() < 4.0:
		return
	var who := "player" if c == race.player else "ai"
	var k := who + "_" + kind
	if other is Car:
		var d: Vector3 = (other as Car).global_position - c.global_position
		# Where the other car was (m ahead / right of this one), and which way it faced (deg).
		print("hit t=%.1f %s %s ahead=%.1f side=%.1f v=%.0f ov=%.0f heading=%.0f" % [t, c.name, k, d.dot(c.forward_dir()), d.dot(-c.global_basis.x),
			c.speed, (other as Car).linear_velocity.dot(c.forward_dir()), rad_to_deg(c.forward_dir().angle_to((other as Car).forward_dir()))])
	_hits[k] = _hits.get(k, 0) + 1


## Let a ghost AIController pick throttle/brake/steer (it brakes for bends and backs off
## walls), then feed those decisions through the real input actions so the player's
## controls path is what actually drives the car.
func _drive(p: Car) -> void:
	if _ai == null:
		_ai = AIController.new()
		_ai.role = AIController.Role.RACER
		_ai.path = race.path
		_ai.others = race.racers.map(func(x): return x.car) + race.traffic_cars + race.cops
		_ai.process_physics_priority = -20
		p.add_child(_ai)
		# add_child ran _ready, which resets the priority to -10.
		_ai.process_physics_priority = -20
	_ai.enabled = race.state == 2
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	if not _ai.enabled:
		return
	if p.throttle > 0.01:
		Input.action_press("accelerate", p.throttle)
	if p.brake > 0.01:
		Input.action_press("brake", p.brake)
	if p.steer > 0.01:
		Input.action_press("steer_right", p.steer)
	elif p.steer < -0.01:
		Input.action_press("steer_left", -p.steer)


var _ram_t := 0.0
var _ram_k := -1
var _ram_targets := []


## Every 4 s puts the car 22 m off a target, heading for it at 25 m/s.
func _ram(p: Car, dt: float) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	if _ram_targets.is_empty():
		var br := get_tree().root.find_child("Breakables", true, false) as Breakables
		var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
		if br:
			var n := br._items.size()
			for k in [0, n / 4, n / 2, 3 * n / 4, n - 1]:
				_ram_targets.append(["prop %d/%d" % [k, n], (br._items[k][0] as Transform3D).origin])
		for c: Car in race.parked_cars.slice(0, 1):
			_ram_targets.append(["parked car", c.global_position])
		if gr and not gr._chunks.is_empty():
			var box: AABB = gr._chunks[gr._chunks.size() / 2].box
			var mid := box.get_center()
			# A point on the rail itself: the vertex nearest the chunk's middle.
			var best := Vector3.INF
			for v: Vector3 in gr._chunks[gr._chunks.size() / 2].rest:
				if v.distance_to(mid) < best.distance_to(mid):
					best = v
			_ram_targets.append(["guardrail", best])
	_ram_t -= dt
	if _ram_t <= 0.0:
		_ram_report()
		_ram_k += 1
		if _ram_k == _ram_targets.size():
			_ram_look_at_bend()
		if _ram_k >= _ram_targets.size():
			return
		_ram_t = 4.0
		var target: Vector3 = _ram_targets[_ram_k][1]
		var i: int = race.path.closest(target)
		# From the road 24 m back, straight at it.
		var rail: bool = _ram_targets[_ram_k][0] == "guardrail"
		var start: Vector3 = race.path.points[race.path.idx(i - (2 if rail else 4))]
		var dir := Vector3(target.x - start.x, 0.0, target.z - start.z).normalized()
		p.reset_to(Transform3D(Basis.looking_at(-dir, Vector3.UP), start), 0.3)
		p.linear_velocity = dir * (35.0 if rail else 25.0)
		print("ram %s at %s" % [_ram_targets[_ram_k][0], target])
	Input.action_press("accelerate", 0.4)
	if absf(_ram_t - 3.0) < dt * 0.5 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("shots/ram_%d.png" % _ram_k)


func _ram_report() -> void:
	if _ram_k < 0 or _ram_k >= _ram_targets.size():
		return
	var br := get_tree().root.find_child("Breakables", true, false) as Breakables
	var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
	var loose := 0
	if br:
		for c in br.get_children():
			if c is KnockableProp:
				loose += 1
	var bent := 0
	if gr:
		for ch: Dictionary in gr._chunks:
			var v: PackedVector3Array = ch.arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedVector3Array = ch.rest
			for k in v.size():
				if v[k].distance_to(rest[k]) > 0.02:
					bent += 1
	var frozen: int = race.parked_cars.filter(func(c: Car) -> bool: return c.freeze).size()
	print("  after %s: %d props knocked loose, %d guardrail vertices bent, %d/%d parked cars asleep" % [
		_ram_targets[_ram_k][0], loose, bent, frozen, race.parked_cars.size()])


## A last shot of the most bent guardrail, from a camera of its own.
func _ram_look_at_bend() -> void:
	var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
	if gr == null or DisplayServer.get_name() == "headless":
		return
	var worst := 0.0
	var at := Vector3.ZERO
	var out := Vector3.ZERO
	for ch: Dictionary in gr._chunks:
		var v: PackedVector3Array = ch.arrays[Mesh.ARRAY_VERTEX]
		var rest: PackedVector3Array = ch.rest
		for k in v.size():
			var d := v[k].distance_to(rest[k])
			if d > worst:
				worst = d
				at = rest[k]
				out = v[k] - rest[k]
	if worst <= 0.0:
		return
	out.y = 0.0
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	var side := out.normalized().cross(Vector3.UP)
	cam.global_position = at - out.normalized() * 4.0 + side * 3.0 + Vector3.UP * 1.6
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("shots/ram_bend.png")
	print("bend shot: %.2f m at %s" % [worst, at])


## --dumptree: what the race draws, by branch: meshes, multimesh instances, triangles.
func _dump_tree(n: Node, depth: int) -> void:
	var stats := {"mi": 0, "mm": 0, "inst": 0, "tris": 0, "vr": 0.0, "mats": {}}
	_count(n, stats)
	if stats.mi + stats.mm > 0 or depth == 0:
		print("%s%s [%s] mi=%d mm=%d inst=%d tris=%dk maxvr=%.0f mats=%s" % ["  ".repeat(depth), n.name, n.get_class(),
			stats.mi, stats.mm, stats.inst, stats.tris / 1000, stats.vr, ",".join(stats.mats.keys()).left(160)])
	if depth < 3:
		for c in n.get_children():
			_dump_tree(c, depth + 1)


func _count(n: Node, st: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh and n.is_visible_in_tree():
		st.mi += 1
		st.tris += _tris(n.mesh)
		st.vr = maxf(st.vr, n.visibility_range_end)
		var m: Material = n.material_override if n.material_override else n.mesh.surface_get_material(0)
		if m is ShaderMaterial and m.shader:
			st.mats[m.shader.resource_path.get_file() if m.shader.resource_path else "inline"] = 1
		elif m:
			st.mats[m.get_class()] = 1
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh and n.is_visible_in_tree():
		st.mm += 1
		var c: int = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
		st.inst += c
		st.tris += _tris(n.multimesh.mesh) * c
		st.vr = maxf(st.vr, n.visibility_range_end)
	for c in n.get_children():
		_count(c, st)


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var ix = a[Mesh.ARRAY_INDEX]
		t += (ix.size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


## --hide=a,b,...: ablation for GPU profiling. Hides one kind of thing throughout the race.
func _hide(n: Node, what: String) -> void:
	if what == "mirror":
		var hud: Node = race.get("hud")
		if hud:
			hud._mirror.visible = false
		return
	if what == "hud":
		race.hud.visible = false
		for c in race.hud.get_children():
			if c is CanvasItem:
				c.visible = false
		return
	if what == "fog":
		get_viewport().get_camera_3d().get_world_3d().environment.fog_enabled = false
		return
	var hit := false
	if n is GeometryInstance3D:
		var shader := ""
		var m: Material = n.material_override
		if m == null and n is MeshInstance3D and n.mesh and n.mesh.get_surface_count() > 0:
			m = n.mesh.surface_get_material(0)
		if m is ShaderMaterial and m.shader:
			shader = m.shader.resource_path.get_file()
			# Game.shader's quality variants have no path: know them by their description.
			if shader == "" and "procedural track's land" in m.shader.code:
				shader = "proc_ground.gdshader"
			elif shader == "" and "procedural track's asphalt" in m.shader.code:
				shader = "proc_road.gdshader"
		var in_car := false
		var p := n.get_parent()
		while p:
			if p is Car:
				in_car = true
				break
			p = p.get_parent()
		match what:
			"cars": hit = in_car
			"mm": hit = n is MultiMeshInstance3D and not in_car
			"ground": hit = shader == "proc_ground.gdshader"
			"road": hit = shader == "proc_road.gdshader"
			"std": hit = not in_car and n is MeshInstance3D and (m is StandardMaterial3D or m == null) and not "Guardrails" in str(n.get_path())
			"rails": hit = "Guardrails" in str(n.get_path())
			"precip": hit = shader == "precipitation.gdshader"
			"skid": hit = n.name == "SkidMarks"
	if hit:
		n.visible = false
		return
	for c in n.get_children():
		_hide(c, what)


## --kill=a,b,...: switches a system off for CPU ablation.
func _kill(what: String) -> void:
	match what:
		"audio":
			for a in race.find_children("*", "AudioStreamPlayer3D", true, false):
				a.stop()
				a.set_process(false)
				a.process_mode = Node.PROCESS_MODE_DISABLED
		"parked":
			for c: Car in race.parked_cars:
				c.queue_free()
			race.parked_cars.clear()
		"particles":
			for p in race.find_children("*", "CPUParticles3D", true, false):
				p.emitting = false
				p.process_mode = Node.PROCESS_MODE_DISABLED
		"areas":
			for a in race.find_children("*", "Area3D", true, false):
				a.monitoring = false
		"effects":
			for e in race.find_children("*", "CarEffects", true, false):
				e.process_mode = Node.PROCESS_MODE_DISABLED
		"hud":
			race.hud.process_mode = Node.PROCESS_MODE_DISABLED
			race.hud.visible = false


class _PerfMark extends Node:
	var cb: Callable
	var pcb: Callable
	func _physics_process(_dt: float) -> void:
		cb.call()
	func _process(_dt: float) -> void:
		if pcb.is_valid():
			pcb.call()


var _rt_cop: Car
var _rt_t := 0.0
var _rt_from := Vector3.ZERO


## --resttest (Hot Pursuit): once a parked cruiser has gone to sleep (Car.resting), fires the
## player's car into its tail and checks that the hit wakes it and it stays on its wheels.
func _rest_test(p: Car, dt: float) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	if _rt_cop == null:
		for c: Car in race.cops:
			if c.resting:
				_rt_cop = c
				_rt_from = c.global_position
				var back := -c.global_basis.z
				p.reset_to(Transform3D(c.global_basis, c.global_position + back * 20.0 - c.global_basis.y * 0.5), 0.3)
				p.linear_velocity = -back * 15.0
				print("resttest: ramming resting cop at ", _rt_from)
				break
		return
	_rt_t += dt
	if int(_rt_t * 4) != int((_rt_t - dt) * 4):
		print("resttest t=%.2f cop resting=%s sleeping=%s moved=%.2f m wheels=%d up=%.2f speed=%.1f" % [_rt_t, _rt_cop.resting,
			_rt_cop.sleeping, _rt_cop.global_position.distance_to(_rt_from), _rt_cop.grounded_wheels, _rt_cop.global_basis.y.y, _rt_cop.linear_velocity.length()])
	if _rt_t > 4.0:
		get_tree().quit()


## --heat=N (Hot Pursuit, Free Roam): the worst case for the police - every cruiser brought up
## behind the player and after it, and the chase already at heat N (backup, roadblocks, spikes).
func _heat_up(p: Car) -> void:
	_heated = true
	var n: int = race.player_racer().node
	for i in race.cops.size():
		var c: Car = race.cops[i]
		c.reset_to(race.path.transform_at(race.path.idx(n - 8 - 5 * i), -2.0 if i % 2 == 0 else 2.0, 0.0))
		c.linear_velocity = p.linear_velocity
		race._start_chase(c, p)
	race.pursuit_time = race.HEAT_STEP * (_heat - 1) + 0.5
	print("heat: %d cops on the player at heat %d" % [race.cops.size(), _heat])


## --drawstats: every 5 s, what the camera draws by kind (surfaces in view and in range).
func _draw_stats() -> void:
	var cam := get_viewport().get_camera_3d()
	var planes := cam.get_frustum()
	var eye := cam.global_position
	var by := {}
	for g: GeometryInstance3D in race.find_children("*", "GeometryInstance3D", true, false):
		if not g.is_visible_in_tree() or not (g.layers & cam.cull_mask):
			continue
		var aabb := g.global_transform * g.get_aabb()
		if g.visibility_range_end > 0.0 and aabb.get_center().distance_to(eye) > g.visibility_range_end + aabb.size.length() * 0.5:
			continue
		var inside := true
		for pl in planes:
			var c := aabb.get_center()
			var e := aabb.size * 0.5
			var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
			if pl.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var kind := g.get_class()
		var p := g.get_parent()
		while p:
			if p is Car:
				kind = "car:" + ("cop" if p.is_cop else "other")
				break
			p = p.get_parent()
		if not kind.begins_with("car"):
			var m: Material = g.material_override
			if m is ShaderMaterial:
				kind += ":" + (m.shader.resource_path.get_file() if m.shader.resource_path else m.shader.code.substr(0, 60).split("\n")[1])
			elif g is MultiMeshInstance3D:
				kind += ":" + str(g.multimesh.instance_count)
		var surfs := 1
		if g is MeshInstance3D and g.mesh:
			surfs = g.mesh.get_surface_count()
		by[kind] = by.get(kind, 0) + surfs
	var keys := by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b])
	var total := 0
	for k in keys:
		total += by[k]
	var out := []
	for k in keys.slice(0, 14):
		out.append("%s=%d" % [k.left(50), by[k]])
	print("draws ~%d: %s" % [total, ", ".join(out)])


var _gt_state := {}      # traffic car -> [gliding, seconds since it last changed]


## --ghosttest: logs far-off traffic changing between gliding and driving, and how each is
## doing half a second after it drives again (wheels down, upright, at its speed).
func _ghost_test() -> void:
	for c: Car in race.traffic_cars:
		var ai: AIController = race._controller(c)
		var g: bool = ai._ghost
		var st: Array = _gt_state.get(c, [g, 0.0])
		st[1] += get_physics_process_delta_time()
		if g != st[0]:
			print("ghost %s %s node=%d at %.0f m from the camera" % [c.name, "glides" if g else "drives",
				ai.node, c.global_position.distance_to(get_viewport().get_camera_3d().global_position)])
			st = [g, 0.0]
		elif not g and absf(st[1] - 0.5) < 0.009:
			print("  %s 0.5 s later: wheels=%d up=%.2f speed=%.1f (cruise %.1f) lateral=%.1f (lane %.1f)" % [c.name,
				c.grounded_wheels, c.global_basis.y.y, c.speed, ai.cruise_speed, race.path.lateral(c.global_position, ai.node), ai.lane])
		_gt_state[c] = st


var _tt_next := 0.0
var _tt_pos := {}        # traffic car -> where it was at the last line, to spot it being brought back


## --traffictest: every 2 s, each traffic car: its distance from the player, which way it's
## going, its lane (and the lateral offset it holds against the lane's), its speed against
## its cruising speed, whether it's giving way to a cop or sounding the horn, and "BACK"
## when the race brought it back into play since the last line.
func _traffic_test() -> void:
	if t < _tt_next:
		return
	_tt_next = t + 2.0
	var p := race.path as TrackPath
	print("traffic t=%.0f player %.0f km/h" % [t, race.player.kmh()])
	for c: Car in race.traffic_cars:
		var ai: AIController = race._controller(c)
		var dir := -1 if ai.reverse_dir else 1
		var back: bool = _tt_pos.has(c) and (_tt_pos[c] as Vector3).distance_to(c.global_position) > 150.0
		_tt_pos[c] = c.global_position
		print("  %-8s %5.0f m %s lane %d/%d lat %5.1f (want %5.1f) %4.1f m/s of %4.1f%s%s%s%s" % [c.display_name.left(8),
			c.global_position.distance_to(race.player.global_position), "fwd" if dir > 0 else "rev",
			ai.traffic_lane, p.lane_count(ai.node, ai.drive_side * dir), p.lateral(c.global_position, ai.node),
			p.lane_offset(ai.node, ai.drive_side * dir, ai.traffic_lane), c.speed, ai.traffic_speed(ai.node, dir),
			" YIELD%d" % ai._yield if ai._yield != AIController.Yield.NONE else "", " HORN" if c.horn else "",
			" glide" if ai._ghost else "", " BACK" if back else ""])


func _log_stops() -> void:
	for rr: Dictionary in race.racers:
		var c: Car = rr.car
		var h: Array = _speeds.get_or_add(c, [])
		h.append(c.kmh())
		if h.size() > 90:
			h.pop_front()
		if h.size() < 90 or h[0] < 50 or c.kmh() > 8 or t - _stopped.get(c, -99.0) < 5.0:
			continue
		_stopped[c] = t
		var q := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 3.5
		q.shape = sphere
		q.transform = Transform3D(Basis(), c.global_position + Vector3.UP)
		q.collision_mask = 1 | Nfs3TrackBuilder.SCENERY_LAYER
		q.exclude = [c.get_rid()]
		var near := []
		for hit in c.get_world_3d().direct_space_state.intersect_shape(q, 16):
			var o: Node = hit.collider
			near.append("car" if o is Car else "%s/%s" % [o.get_parent().name, o.name])
		var n: int = rr.get("node", 0)
		var ai: AIController = race._controller(c)
		print("stop t=%.1f %s node=%d at %s (%.1f m right of the line, lane %.1f) from %d km/h, near: %s" % [
			t, rr.name, n, c.global_position.round(), race.path.lateral(c.global_position, n),
			ai.lane if ai else 0.0, h[0], ", ".join(near)])
